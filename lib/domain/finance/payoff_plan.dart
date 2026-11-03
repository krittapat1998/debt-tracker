import 'dart:math' as math;

import '../../core/date_utils.dart';
import '../models/enums.dart';
import 'portfolio.dart';

/// One balance as the payoff plan sees it.
class PayoffDebt {
  const PayoffDebt({
    required this.id,
    required this.name,
    required this.balance,
    required this.annualRate,
    this.payment = 0,
    this.minimumRatio = 0,
    this.lockedUntil,
  });

  final String id;
  final String name;
  final double balance;

  /// Effective (reducing-balance) rate in percent.
  final double annualRate;

  /// Fixed monthly installment (installment plans).
  final double payment;

  /// Revolving balances: the minimum payment as a share of the balance.
  final double minimumRatio;

  /// No prepayment before this day (lock-in).
  final DateTime? lockedUntil;

  /// Smallest revolving minimum, as Thai cards do (or the whole balance).
  static const minimumFloor = 300.0;

  /// Card minimums when the latest statement does not say: 8% for credit
  /// cards (Bank of Thailand), 5% for cash cards and revolving loans.
  static double defaultRatio(AccountType type) => type == AccountType.creditCard ? 0.08 : 0.05;

  /// Every balance still owed, with what has to be paid on it each month.
  static List<PayoffDebt> fromPortfolio(PortfolioSummary s) => [
        for (final a in s.accounts) ...[
          for (final l in a.lines)
            if (l.balance > 0.005)
              PayoffDebt(
                id: l.id,
                name: a.lines.length > 1 ? '${a.account.name} · ${l.name}' : a.account.name,
                balance: l.balance,
                annualRate: l.annualRate,
                minimumRatio: a.account.minimumPayment > 0 && a.account.statementBalance > 0
                    ? math.min(1, a.account.minimumPayment / a.account.statementBalance)
                    : defaultRatio(a.account.type),
              ),
          for (final p in a.activePlans)
            PayoffDebt(
              id: p.plan.id,
              name: '${a.account.name} · ${p.plan.name}',
              balance: p.remainingPrincipal,
              annualRate: p.effectiveAnnualRate,
              payment: p.current.payment,
              lockedUntil: p.earliestClosureDate,
            ),
        ],
      ];
}

/// How a run of the plan turns out.
class PayoffResult {
  const PayoffResult({
    required this.months,
    required this.totalInterest,
    required this.balances,
    required this.paidOff,
    required this.firstMonthPayment,
  });

  /// Months until everything is paid; null when it never is (a minimum
  /// smaller than the interest) within [PayoffPlanner.maxMonths].
  final int? months;
  final double totalInterest;

  /// Total owed at the start ([0]) and after each month.
  final List<double> balances;

  /// Debt id → the month (1-based) it is paid off, in that order.
  final Map<String, int> paidOff;

  /// What the first month costs: the minimums plus the extra.
  final double firstMonthPayment;
}

/// Month-by-month payoff of every balance. The baseline pays only what is
/// due (installments and card minimums). The plan keeps paying the same
/// total as in its first month plus [extra], and puts everything above the
/// minimums on the most expensive balance that may be prepaid (avalanche),
/// so each paid-off debt's payment rolls over to the next.
class PayoffPlanner {
  PayoffPlanner._();

  static const maxMonths = 600;

  static PayoffResult baseline(List<PayoffDebt> debts, {required DateTime start}) =>
      _run(debts, start: start, extra: 0, rollOver: false);

  static PayoffResult plan(List<PayoffDebt> debts, {required DateTime start, required double extra}) =>
      _run(debts, start: start, extra: extra, rollOver: true);

  /// What the coming month asks for: card minimums plus installments.
  static double dueNow(List<PayoffDebt> debts, {required DateTime start}) =>
      baseline(debts, start: start).firstMonthPayment;

  /// Paying [budget] a month in all (what is due, the rest as prepayment);
  /// null when [budget] does not cover what is due.
  static PayoffResult? planWithin(List<PayoffDebt> debts, {required DateTime start, required double budget}) {
    final due = dueNow(debts, start: start);
    if (budget < due - 0.005) return null;
    return plan(debts, start: start, extra: math.max(0, budget - due));
  }

  static double _minimum(PayoffDebt d, double balance) {
    if (d.minimumRatio > 0) return math.min(balance, math.max(d.minimumRatio * balance, PayoffDebt.minimumFloor));
    return math.min(balance, d.payment);
  }

  static PayoffResult _run(List<PayoffDebt> debts,
      {required DateTime start, required double extra, required bool rollOver}) {
    final balance = [for (final d in debts) math.max(0.0, d.balance)];
    // Most expensive first; on a tie the smaller balance goes first.
    final order = [for (var i = 0; i < debts.length; i++) i]..sort((a, b) {
        final c = debts[b].annualRate.compareTo(debts[a].annualRate);
        return c != 0 ? c : debts[a].balance.compareTo(debts[b].balance);
      });
    final balances = [balance.fold(0.0, (s, b) => s + b)];
    final paidOff = <String, int>{};
    var interest = 0.0;
    double? budget;
    var firstPayment = 0.0;

    for (var month = 1; month <= maxMonths; month++) {
      if (balances.last < 0.01) break;
      final day = addMonths(dateOnly(start), month);
      var minimums = 0.0;
      for (var i = 0; i < debts.length; i++) {
        if (balance[i] < 0.01) continue;
        final charge = balance[i] * debts[i].annualRate / 1200;
        interest += charge;
        balance[i] += charge;
        final pay = _minimum(debts[i], balance[i]);
        balance[i] -= pay;
        minimums += pay;
      }
      budget ??= minimums + extra;
      if (month == 1) firstPayment = budget;
      var pool = rollOver ? math.max(0.0, budget - minimums) : 0.0;
      for (final i in order) {
        if (pool < 0.01) break;
        final locked = debts[i].lockedUntil;
        if (balance[i] < 0.01 || (locked != null && day.isBefore(locked))) continue;
        final put = math.min(pool, balance[i]);
        balance[i] -= put;
        pool -= put;
      }
      for (var i = 0; i < debts.length; i++) {
        if (balance[i] < 0.01 && !paidOff.containsKey(debts[i].id) && debts[i].balance > 0.005) {
          balance[i] = 0;
          paidOff[debts[i].id] = month;
        }
      }
      balances.add(balance.fold(0.0, (s, b) => s + b));
    }
    return PayoffResult(
      months: balances.last < 0.01 ? balances.length - 1 : null,
      totalInterest: interest,
      balances: balances,
      paidOff: paidOff,
      firstMonthPayment: firstPayment,
    );
  }
}
