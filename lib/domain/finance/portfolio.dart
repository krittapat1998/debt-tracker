import 'dart:math' as math;

import '../../core/date_utils.dart';
import '../models/account.dart';
import '../models/credit_line.dart';
import '../models/installment_plan.dart';
import '../models/payment.dart';
import '../models/spending.dart';
import 'installment_engine.dart';

enum DebtKind { revolving, installment }

/// One interest-bearing balance, used for the avalanche ranking.
class DebtItem {
  const DebtItem({
    required this.accountId,
    required this.accountName,
    required this.label,
    required this.kind,
    required this.refId,
    required this.balance,
    required this.effectiveRate,
    required this.monthlyInterest,
    this.lockedUntil,
  });

  final String accountId;
  final String accountName;
  final String label;
  final DebtKind kind;

  /// Credit line id or installment plan id.
  final String refId;
  final double balance;
  final double effectiveRate;
  final double monthlyInterest;
  final DateTime? lockedUntil;

  bool lockedOn(DateTime day) =>
      lockedUntil != null && dateOnly(day).isBefore(lockedUntil!);
}

class MonthlyDue {
  const MonthlyDue({this.gross = 0, this.paid = 0});
  final double gross;
  final double paid;
  double get remaining => math.max(0, gross - paid);

  MonthlyDue operator +(MonthlyDue o) =>
      MonthlyDue(gross: gross + o.gross, paid: paid + o.paid);
}

class AccountSummary {
  AccountSummary({
    required this.account,
    required List<CreditLine> lines,
    required List<InstallmentState> plans,
    required List<Payment> payments,
    List<Spending> spendings = const [],
    required DateTime today,
  })  : lines = List.unmodifiable([...lines]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))),
        plans = List.unmodifiable(plans),
        payments = List.unmodifiable([...payments]
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
          })),
        spendings = List.unmodifiable([...spendings]
          ..sort((a, b) {
            final c = b.date.compareTo(a.date);
            return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
          })),
        today = dateOnly(today);

  final Account account;
  final List<CreditLine> lines;
  final List<InstallmentState> plans;

  /// Newest first.
  final List<Payment> payments;

  /// Newest first.
  final List<Spending> spendings;
  final DateTime today;

  List<InstallmentState> get activePlans => plans.where((p) => !p.isClosed).toList();

  double get revolvingBalance => lines.fold(0.0, (s, l) => s + math.max(0, l.balance));

  double get installmentBalance => plans.fold(0.0, (s, p) => s + p.remainingPrincipal);

  double get totalDebt => revolvingBalance + installmentBalance;

  double get creditLimit =>
      account.sharedLimit ?? lines.fold(0.0, (s, l) => s + l.creditLimit);

  /// Revolving balances plus plans that consume a sub-limit.
  double get usedLimit =>
      revolvingBalance +
      plans
          .where((p) => p.plan.creditLineId != null)
          .fold(0.0, (s, p) => s + p.remainingPrincipal);

  double get availableLimit => math.max(0, creditLimit - usedLimit);

  double usedOnLine(CreditLine line) =>
      math.max(0, line.balance) +
      plans
          .where((p) => p.plan.creditLineId == line.id)
          .fold(0.0, (s, p) => s + p.remainingPrincipal);

  List<DebtItem> get debtItems => [
        for (final l in lines)
          if (l.balance > 0.005)
            DebtItem(
              accountId: account.id,
              accountName: account.name,
              label: l.name,
              kind: DebtKind.revolving,
              refId: l.id,
              balance: l.balance,
              effectiveRate: l.annualRate,
              monthlyInterest: l.balance * l.annualRate / 1200,
            ),
        for (final p in plans)
          if (!p.isClosed)
            DebtItem(
              accountId: account.id,
              accountName: account.name,
              label: p.plan.name,
              kind: DebtKind.installment,
              refId: p.plan.id,
              balance: p.remainingPrincipal,
              effectiveRate: p.effectiveAnnualRate,
              monthlyInterest: p.current.nextInterest,
              lockedUntil: p.earliestClosureDate,
            ),
      ];

  /// Highest effective rate among balances still owed (falls back to the
  /// highest configured rate when nothing is owed).
  double get topRate {
    final items = debtItems;
    if (items.isNotEmpty) return items.map((e) => e.effectiveRate).reduce(math.max);
    final rates = [
      ...lines.map((l) => l.annualRate),
      ...plans.map((p) => p.effectiveAnnualRate),
    ];
    return rates.isEmpty ? 0 : rates.reduce(math.max);
  }

  double get estimatedMonthlyInterest =>
      debtItems.fold(0.0, (s, d) => s + d.monthlyInterest);

  /// Due date of the latest statement.
  DateTime? get statementDueDate {
    if (account.statementDueDate != null) return account.statementDueDate;
    final sd = account.statementDate;
    final dd = account.dueDay;
    if (sd == null || dd == null) return null;
    return nextDayAfter(dd, sd);
  }

  bool _countsTowardStatement(Payment p) {
    if (p.planId == null) return true;
    for (final s in plans) {
      if (s.plan.id == p.planId) return s.plan.includedInStatement;
    }
    return true;
  }

  /// Paid toward the card statement since it was issued.
  double get paidTowardStatement {
    final sd = account.statementDate;
    return payments
        .where((p) => sd == null || !p.date.isBefore(sd))
        .where(_countsTowardStatement)
        .fold(0.0, (s, p) => s + p.amount);
  }

  double get minimumOutstanding =>
      math.max(0, account.minimumPayment - paidTowardStatement);

  double get statementOutstanding =>
      math.max(0, account.statementBalance - paidTowardStatement);

  bool get isStatementPaid =>
      account.minimumPayment <= 0 || minimumOutstanding <= 0.005;

  /// ขั้นต่ำ + ค่าผ่อนที่ต้องจ่ายในเดือนปฏิทินนี้.
  MonthlyDue get monthlyDue {
    var due = const MonthlyDue();
    final stmtDue = statementDueDate;
    if (account.minimumPayment > 0 &&
        (minimumOutstanding > 0.005 || (stmtDue != null && isSameMonth(stmtDue, today)))) {
      due += MonthlyDue(
        gross: account.minimumPayment,
        paid: math.min(account.minimumPayment, paidTowardStatement),
      );
    }
    final monthEnd = endOfMonth(today);
    for (final p in plans) {
      if (p.plan.includedInStatement) continue;
      for (final r in p.paidRows) {
        if (r.dueDate != null && isSameMonth(r.dueDate!, today)) {
          due += MonthlyDue(gross: r.payment, paid: r.payment);
        }
      }
      for (final r in p.projection) {
        if (r.dueDate == null || r.dueDate!.isAfter(monthEnd)) break;
        due += MonthlyDue(gross: r.payment);
      }
    }
    return due;
  }

  double paidInMonth(DateTime month) => payments
      .where((p) => isSameMonth(p.date, month))
      .fold(0.0, (s, p) => s + p.amount);

  /// Earliest upcoming (or overdue) payment date across the card and its
  /// separately-billed plans.
  DateTime? get nextDueDate {
    final candidates = <DateTime>[];
    final stmtDue = statementDueDate;
    final dd = account.dueDay;
    if (stmtDue != null && !isStatementPaid) {
      candidates.add(stmtDue);
    } else if (dd != null && (account.minimumPayment > 0 || revolvingBalance > 0 || _hasStatementPlans)) {
      final next = nextOccurrenceOfDay(dd, today);
      candidates.add(stmtDue != null && !stmtDue.isBefore(next) ? nextDayAfter(dd, stmtDue) : next);
    }
    for (final p in plans) {
      if (p.plan.includedInStatement) continue;
      final d = p.nextDueDate;
      if (d != null) candidates.add(d);
    }
    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.first;
  }

  bool get _hasStatementPlans =>
      plans.any((p) => p.plan.includedInStatement && !p.isClosed);

  int? get daysUntilDue {
    final d = nextDueDate;
    return d == null ? null : daysBetween(today, d);
  }

  /// Amount expected on [nextDueDate].
  double get nextDueAmount {
    final d = nextDueDate;
    if (d == null) return 0;
    var amount = 0.0;
    final stmtDue = statementDueDate;
    if (stmtDue != null && !isStatementPaid && stmtDue == d) amount += minimumOutstanding;
    for (final p in plans) {
      if (p.plan.includedInStatement) continue;
      final row = p.nextRow;
      if (row != null && row.dueDate == d) amount += row.payment;
    }
    return amount;
  }
}

class PortfolioSummary {
  PortfolioSummary({required List<AccountSummary> accounts, required DateTime today})
      : accounts = List.unmodifiable([...accounts]
          ..sort((a, b) {
            final c = b.topRate.compareTo(a.topRate);
            return c != 0 ? c : b.totalDebt.compareTo(a.totalDebt);
          })),
        today = dateOnly(today);

  /// Joins raw rows into per-account summaries; accounts are sorted from
  /// the highest to the lowest interest rate (debt avalanche order).
  factory PortfolioSummary.build({
    required List<Account> accounts,
    required List<CreditLine> lines,
    required List<InstallmentPlan> plans,
    required List<Payment> payments,
    List<Spending> spendings = const [],
    required DateTime today,
  }) {
    final summaries = [
      for (final a in accounts)
        AccountSummary(
          account: a,
          lines: lines.where((l) => l.accountId == a.id).toList(),
          plans: [
            for (final p in plans.where((p) => p.accountId == a.id))
              InstallmentEngine.replay(p, payments, asOf: today),
          ],
          payments: payments.where((p) => p.accountId == a.id).toList(),
          spendings: spendings.where((s) => s.accountId == a.id).toList(),
          today: today,
        ),
    ];
    return PortfolioSummary(accounts: summaries, today: today);
  }

  final List<AccountSummary> accounts;
  final DateTime today;

  bool get isEmpty => accounts.isEmpty;

  double get totalDebt => accounts.fold(0.0, (s, a) => s + a.totalDebt);
  double get totalRevolving => accounts.fold(0.0, (s, a) => s + a.revolvingBalance);
  double get totalInstallment => accounts.fold(0.0, (s, a) => s + a.installmentBalance);
  double get totalLimit => accounts.fold(0.0, (s, a) => s + a.creditLimit);
  double get estimatedMonthlyInterest =>
      accounts.fold(0.0, (s, a) => s + a.estimatedMonthlyInterest);

  MonthlyDue get monthlyDue =>
      accounts.fold(const MonthlyDue(), (s, a) => s + a.monthlyDue);

  double get paidThisMonth => accounts.fold(0.0, (s, a) => s + a.paidInMonth(today));

  /// All balances, most expensive first (ties: smaller balance first).
  List<DebtItem> get avalanche {
    final items = [for (final a in accounts) ...a.debtItems];
    items.sort((a, b) {
      final c = b.effectiveRate.compareTo(a.effectiveRate);
      return c != 0 ? c : a.balance.compareTo(b.balance);
    });
    return items;
  }

  /// Most expensive balance that can actually be prepaid today.
  DebtItem? get recommendedTarget {
    for (final item in avalanche) {
      if (!item.lockedOn(today)) return item;
    }
    return null;
  }

  AccountSummary? get mostExpensive {
    for (final a in accounts) {
      if (a.totalDebt > 0.005) return a;
    }
    return null;
  }

  /// Accounts by their next payment date, overdue first and those with
  /// nothing due last; ties keep the interest-rate order.
  List<AccountSummary> get byDueDate {
    final rank = {for (final (i, a) in accounts.indexed) a: i};
    return [...accounts]..sort((a, b) {
        final da = a.nextDueDate, db = b.nextDueDate;
        final c = da == null || db == null
            ? (da == null ? 1 : 0) - (db == null ? 1 : 0)
            : da.compareTo(db);
        return c != 0 ? c : rank[a]!.compareTo(rank[b]!);
      });
  }

  AccountSummary? get nextDue {
    AccountSummary? best;
    for (final a in accounts) {
      final d = a.nextDueDate;
      if (d == null) continue;
      if (best == null || d.isBefore(best.nextDueDate!)) best = a;
    }
    return best;
  }

  AccountSummary? byId(String id) {
    for (final a in accounts) {
      if (a.account.id == id) return a;
    }
    return null;
  }
}
