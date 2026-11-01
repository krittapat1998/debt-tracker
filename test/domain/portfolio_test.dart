import 'package:debt_tracker/domain/finance/installment_engine.dart';
import 'package:debt_tracker/domain/finance/loan_math.dart';
import 'package:debt_tracker/domain/finance/portfolio.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
import 'package:debt_tracker/domain/models/spending.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 1, 1);

Account account(String id, {double min = 0, double stmt = 0, DateTime? stmtDate, int? dueDay, DateTime? stmtDue}) =>
    Account(
      id: id,
      name: id.toUpperCase(),
      type: AccountType.creditCard,
      minimumPayment: min,
      statementBalance: stmt,
      statementDate: stmtDate,
      statementDueDate: stmtDue,
      dueDay: dueDay,
      createdAt: _created,
    );

CreditLine line(String id, String accountId, {double balance = 0, double rate = 16, double limit = 0}) => CreditLine(
      id: id,
      accountId: accountId,
      name: id,
      balance: balance,
      annualRate: rate,
      creditLimit: limit,
    );

InstallmentPlan plan(
  String id,
  String accountId, {
  double principal = 12000,
  double rate = 12,
  InterestMethod method = InterestMethod.reducing,
  int term = 12,
  DateTime? start,
  bool included = false,
  int paidBefore = 0,
  int lockIn = 0,
  double penaltyPercent = 0,
  String? lineId,
}) =>
    InstallmentPlan(
      id: id,
      accountId: accountId,
      creditLineId: lineId,
      name: id,
      principal: principal,
      annualRate: rate,
      interestMethod: method,
      termMonths: term,
      startDate: start ?? DateTime(2026, 1, 25),
      includedInStatement: included,
      paidBeforeTracking: paidBefore,
      lockInMonths: lockIn,
      penaltyPercent: penaltyPercent,
      createdAt: _created,
    );

var _seq = 0;
Payment pay(String accountId, DateTime date, double amount, PaymentType type,
        {String? planId, String? lineId, PrepaymentMode? mode}) =>
    Payment(
      id: 'p${_seq++}',
      accountId: accountId,
      planId: planId,
      creditLineId: lineId,
      date: date,
      amount: amount,
      type: type,
      prepaymentMode: mode,
      createdAt: DateTime(2026, 1, 1).add(Duration(seconds: _seq)),
    );

void main() {
  group('InstallmentEngine.replay', () {
    final p = plan('loan', 'a');
    final m = LoanMath.amortizedPayment(12000, 0.01, 12);

    test('logged installments advance the plan', () {
      final s = InstallmentEngine.replay(
        p,
        [
          pay('a', DateTime(2026, 1, 25), m, PaymentType.installment, planId: 'loan'),
          pay('a', DateTime(2026, 2, 25), m, PaymentType.installment, planId: 'loan'),
          pay('a', DateTime(2026, 2, 26), 999, PaymentType.installment, planId: 'other-plan'),
        ],
        asOf: DateTime(2026, 3, 1),
      );
      expect(s.paidInstallments, 2);
      expect(s.remainingPrincipal, closeTo(LoanMath.balanceAfter(12000, 0.01, m, 2), 0.01));
      expect(s.interestPaid, closeTo(120 + (12000 - (m - 120)) * 0.01, 0.01));
      expect(s.nextDueDate, DateTime(2026, 3, 25));
      expect(s.remainingInstallments, 10);
      expect(s.originalTotalInterest, closeTo(LoanMath.reducingTotalInterest(12000, 12, 12), 0.01));
    });

    test('extra prepayment (reduce term) closes sooner and saves interest', () {
      final s = InstallmentEngine.replay(
        p,
        [
          pay('a', DateTime(2026, 1, 25), m, PaymentType.installment, planId: 'loan'),
          pay('a', DateTime(2026, 2, 1), 5000, PaymentType.extra, planId: 'loan', mode: PrepaymentMode.reduceTerm),
        ],
        asOf: DateTime(2026, 2, 2),
      );
      expect(s.extraPaid, 5000);
      expect(s.currentPayment, closeTo(m, 1e-9));
      expect(s.remainingInstallments, lessThan(11));
      expect(s.interestSavedSoFar, greaterThan(0));
    });

    test('extra prepayment (reduce payment) keeps the term', () {
      final s = InstallmentEngine.replay(
        p,
        [pay('a', DateTime(2026, 1, 10), 6000, PaymentType.extra, planId: 'loan', mode: PrepaymentMode.reducePayment)],
        asOf: DateTime(2026, 1, 11),
      );
      expect(s.remainingInstallments, 12);
      expect(s.currentPayment, closeTo(LoanMath.amortizedPayment(6000, 0.01, 12), 0.01));
    });

    test('statement-billed plans advance automatically on due dates', () {
      final card = plan('ipad', 'a', principal: 30000, rate: 0, term: 10, start: DateTime(2026, 8, 15), included: true);
      final s = InstallmentEngine.replay(card, const [], asOf: DateTime(2026, 10, 31));
      expect(s.paidInstallments, 3);
      expect(s.remainingPrincipal, closeTo(21000, 0.01));
      expect(s.nextDueDate, DateTime(2026, 11, 15));
      expect(s.paidRows.every((r) => r.automatic), isTrue);
    });

    test('statement-billed plan: extra prepayment lands between automatic installments', () {
      final card = plan('ipad', 'a', principal: 30000, rate: 0, term: 10, start: DateTime(2026, 8, 15), included: true);
      final s = InstallmentEngine.replay(
        card,
        [pay('a', DateTime(2026, 9, 20), 9000, PaymentType.extra, planId: 'ipad', mode: PrepaymentMode.reduceTerm)],
        asOf: DateTime(2026, 10, 31),
      );
      // Aug 15, Sep 15 → 24,000; prepay → 15,000; Oct 15 → 12,000.
      expect(s.paidInstallments, 3);
      expect(s.remainingPrincipal, closeTo(12000, 0.01));
      expect(s.remainingInstallments, 4);
    });

    test('installments paid before tracking are applied first', () {
      final s = InstallmentEngine.replay(plan('loan', 'a', paidBefore: 5), const [], asOf: DateTime(2026, 1, 1));
      expect(s.paidInstallments, 5);
      expect(s.nextDueDate, DateTime(2026, 6, 25));
      expect(s.remainingPrincipal, closeTo(LoanMath.balanceAfter(12000, 0.01, m, 5), 0.01));
    });

    test('lock-in and early-closure penalty', () {
      final s = InstallmentEngine.replay(
        plan('loan', 'a', lockIn: 6, penaltyPercent: 3),
        const [],
        asOf: DateTime(2026, 1, 1),
      );
      expect(s.earliestClosureDate, DateTime(2026, 7, 25));
      expect(s.isLockedOn(DateTime(2026, 7, 24)), isTrue);
      expect(s.isLockedOn(DateTime(2026, 7, 25)), isFalse);
      expect(s.earlyClosurePenalty, closeTo(360, 0.01));
      expect(s.payoffAmount, closeTo(12360, 0.01));
    });

    test('flat plan reports its effective rate', () {
      final s = InstallmentEngine.replay(
        plan('flat', 'a', principal: 100000, rate: 10, method: InterestMethod.flat, term: 12),
        const [],
        asOf: DateTime(2026, 1, 1),
      );
      expect(s.effectiveAnnualRate, closeTo(17.97, 0.01));
      expect(s.projectedRemainingInterest, closeTo(10000, 0.01));
    });
  });

  group('PortfolioSummary', () {
    final today = DateTime(2026, 10, 31);

    test('one card with two sub-limits at different rates', () {
      final s = PortfolioSummary.build(
        accounts: [account('uob')],
        lines: [
          line('credit', 'uob', balance: 20000, rate: 16, limit: 100000),
          line('loan', 'uob', balance: 50000, rate: 25, limit: 60000),
        ],
        plans: const [],
        payments: const [],
        today: today,
      );
      final a = s.accounts.single;
      expect(a.totalDebt, 70000);
      expect(a.creditLimit, 160000);
      expect(a.topRate, 25);
      expect(a.estimatedMonthlyInterest, closeTo(20000 * 16 / 1200 + 50000 * 25 / 1200, 1e-9));
      expect(s.avalanche.map((d) => d.refId), ['loan', 'credit']);
    });

    test('shared limit overrides the sum of sub-limits', () {
      final s = PortfolioSummary.build(
        accounts: [
          Account(id: 'x', name: 'X', type: AccountType.creditCard, sharedLimit: 100000, createdAt: _created),
        ],
        lines: [line('a', 'x', limit: 100000, balance: 1000), line('b', 'x', limit: 100000, balance: 2000)],
        plans: const [],
        payments: const [],
        today: today,
      );
      expect(s.accounts.single.creditLimit, 100000);
      expect(s.accounts.single.availableLimit, 97000);
    });

    test('accounts are sorted by interest rate, high to low', () {
      final s = PortfolioSummary.build(
        accounts: [account('low'), account('high'), account('mid')],
        lines: [
          line('l1', 'low', balance: 1000, rate: 10),
          line('l2', 'high', balance: 1000, rate: 28),
          line('l3', 'mid', balance: 1000, rate: 18),
        ],
        plans: const [],
        payments: const [],
        today: today,
      );
      expect(s.accounts.map((a) => a.account.id), ['high', 'mid', 'low']);
      expect(s.mostExpensive!.account.id, 'high');
    });

    test('spending after the last cutoff waits for the next bill', () {
      Spending spent(String id, DateTime date, double amount) =>
          Spending(id: id, accountId: 'a', creditLineId: 'l', date: date, amount: amount, createdAt: date);
      AccountSummary summary({DateTime? stmtDate, int? billingDay}) => AccountSummary(
            account: Account(
              id: 'a',
              name: 'KTC',
              type: AccountType.creditCard,
              billingDay: billingDay,
              statementDate: stmtDate,
              createdAt: _created,
            ),
            lines: [line('l', 'a', balance: 20000)],
            plans: const [],
            payments: const [],
            spendings: [
              spent('s1', DateTime(2026, 10, 20), 900), // before the cutoff: on the bill already
              spent('s2', DateTime(2026, 10, 25), 400), // on the cutoff day: on that bill
              spent('s3', DateTime(2026, 10, 28), 1500),
            ],
            today: DateTime(2026, 11, 1),
          );

      final byDay = summary(billingDay: 25);
      expect(byDay.lastCutoff, DateTime(2026, 10, 25));
      expect(byDay.nextCutoff, DateTime(2026, 11, 25));
      expect(byDay.spendingSinceCutoff, 1500);

      // A newer typed-in statement date wins over the billing day.
      final byStatement = summary(billingDay: 25, stmtDate: DateTime(2026, 10, 27));
      expect(byStatement.lastCutoff, DateTime(2026, 10, 27));
      expect(byStatement.spendingSinceCutoff, 1500);

      // No billing day and no statement: nothing to split.
      expect(summary().lastCutoff, isNull);
      expect(summary().spendingSinceCutoff, 0);
    });

    test('byDueDate puts overdue first and accounts with nothing due last', () {
      final s = PortfolioSummary.build(
        accounts: [
          account('nothing'),
          account('later', dueDay: 20),
          account('overdue', min: 500, stmt: 5000, stmtDate: DateTime(2026, 10, 1), dueDay: 25),
          account('soon', dueDay: 5),
        ],
        lines: [
          line('n', 'nothing', rate: 30),
          line('l', 'later', balance: 1000, rate: 28),
          line('o', 'overdue', balance: 5000, rate: 10),
          line('s', 'soon', balance: 1000, rate: 12),
        ],
        plans: const [],
        payments: const [],
        today: today,
      );
      expect(s.byDueDate.map((a) => a.account.id), ['overdue', 'soon', 'later', 'nothing']);
      // The rate order (and the most expensive pick) is unchanged.
      expect(s.accounts.first.account.id, 'nothing');
      expect(s.mostExpensive!.account.id, 'later');
    });

    test('avalanche recommendation skips balances still in lock-in', () {
      final s = PortfolioSummary.build(
        accounts: [account('a'), account('b')],
        lines: [line('card', 'b', balance: 5000, rate: 16)],
        plans: [plan('locked', 'a', rate: 30, start: DateTime(2026, 10, 1), lockIn: 12)],
        payments: const [],
        today: today,
      );
      expect(s.avalanche.first.refId, 'locked');
      expect(s.recommendedTarget!.refId, 'card');
    });

    test('monthly due = minimum + separately billed installments; payments reduce it', () {
      final s = PortfolioSummary.build(
        accounts: [
          account('card', min: 1000, stmt: 10000, stmtDate: DateTime(2026, 10, 20), dueDay: 5),
          account('loan'),
        ],
        lines: [line('c', 'card', balance: 10000), line('l', 'loan')],
        plans: [plan('pl', 'loan', start: DateTime(2026, 11, 25))],
        payments: [pay('card', DateTime(2026, 10, 25), 600, PaymentType.other, lineId: 'c')],
        today: DateTime(2026, 11, 2),
      );
      final card = s.byId('card')!;
      expect(card.statementDueDate, DateTime(2026, 11, 5));
      expect(card.minimumOutstanding, 400);
      expect(card.monthlyDue.gross, 1000);
      expect(card.monthlyDue.remaining, 400);
      expect(card.nextDueDate, DateTime(2026, 11, 5));
      expect(card.nextDueAmount, 400);

      final loan = s.byId('loan')!;
      final m = LoanMath.amortizedPayment(12000, 0.01, 12);
      expect(loan.monthlyDue.gross, closeTo(m, 0.01));
      expect(s.monthlyDue.gross, closeTo(1000 + m, 0.01));
      expect(s.nextDue!.account.id, 'card');
    });

    test('statement-billed installments are not added to the monthly due twice', () {
      final s = PortfolioSummary.build(
        accounts: [account('card', min: 3000, stmt: 3000, stmtDate: DateTime(2026, 10, 20), dueDay: 5)],
        lines: [line('c', 'card')],
        plans: [plan('ipad', 'card', rate: 0, start: DateTime(2026, 11, 5), included: true)],
        payments: const [],
        today: DateTime(2026, 11, 1),
      );
      expect(s.monthlyDue.gross, 3000);
    });

    test('a paid statement moves the next due date to the following cycle', () {
      final s = PortfolioSummary.build(
        accounts: [account('card', min: 1000, stmt: 5000, stmtDate: DateTime(2026, 10, 20), dueDay: 5)],
        lines: [line('c', 'card', balance: 2000)],
        plans: const [],
        payments: [pay('card', DateTime(2026, 10, 28), 5000, PaymentType.full, lineId: 'c')],
        today: DateTime(2026, 11, 1),
      );
      final a = s.accounts.single;
      expect(a.isStatementPaid, isTrue);
      expect(a.nextDueDate, DateTime(2026, 12, 5));
    });
  });
}
