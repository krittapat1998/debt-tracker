import 'package:debt_tracker/domain/finance/loan_math.dart';
import 'package:debt_tracker/domain/finance/payoff_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 2);

  test('an installment alone runs its term and costs its schedule interest', () {
    final pay = LoanMath.amortizedPayment(12000, 0.01, 12);
    final r = PayoffPlanner.baseline(
      [PayoffDebt(id: 'p', name: 'ผ่อน', balance: 12000, annualRate: 12, payment: pay)],
      start: start,
    );
    expect(r.months, 12);
    expect(r.totalInterest, closeTo(pay * 12 - 12000, 0.05));
    expect(r.balances.first, 12000);
    expect(r.balances.last, 0);
    expect(r.paidOff, {'p': 12});
  });

  test('paying extra on a card finishes sooner and saves interest', () {
    const card = PayoffDebt(id: 'c', name: 'บัตร', balance: 50000, annualRate: 16, minimumRatio: 0.08);
    final base = PayoffPlanner.baseline([card], start: start);
    final plan = PayoffPlanner.plan([card], start: start, extra: 2000);
    expect(base.months, isNotNull);
    expect(plan.months!, lessThan(base.months!));
    expect(plan.totalInterest, lessThan(base.totalInterest));
    // The minimum is 8% of the balance with the month's interest on it.
    expect(plan.firstMonthPayment, closeTo((50000 + 50000 * 16 / 1200) * 0.08 + 2000, 0.01));
  });

  test('the extra goes to the most expensive balance, then rolls over', () {
    final pay = LoanMath.amortizedPayment(30000, 0.01, 24);
    final debts = [
      PayoffDebt(id: 'cheap', name: 'ผ่อน 12%', balance: 30000, annualRate: 12, payment: pay),
      const PayoffDebt(id: 'dear', name: 'บัตรกดเงินสด 25%', balance: 20000, annualRate: 25, minimumRatio: 0.05),
    ];
    final plan = PayoffPlanner.plan(debts, start: start, extra: 3000);
    expect(plan.paidOff.keys.first, 'dear');
    expect(plan.paidOff['cheap']!, lessThan(24));
    final base = PayoffPlanner.baseline(debts, start: start);
    expect(plan.totalInterest, lessThan(base.totalInterest));
  });

  test('a balance in lock-in takes no extra until the lock ends', () {
    final pay = LoanMath.amortizedPayment(20000, 0.02, 12);
    final locked = PayoffDebt(
        id: 'l', name: 'สินเชื่อ', balance: 20000, annualRate: 24, payment: pay, lockedUntil: DateTime(2027, 5, 2));
    final plan = PayoffPlanner.plan([locked], start: start, extra: 5000);
    // Months 1–5 (Dec–Apr) follow the schedule; the extra starts in May.
    final base = PayoffPlanner.baseline([locked], start: start);
    expect(plan.balances.sublist(0, 6), base.balances.sublist(0, 6));
    expect(plan.months!, lessThan(12));
  });

  test('a monthly total pays what is due and prepays the rest', () {
    final pay = LoanMath.amortizedPayment(30000, 0.01, 24);
    final debts = [
      PayoffDebt(id: 'loan', name: 'ผ่อน', balance: 30000, annualRate: 12, payment: pay),
      const PayoffDebt(id: 'card', name: 'บัตร', balance: 20000, annualRate: 16, minimumRatio: 0.08),
    ];
    final due = PayoffPlanner.dueNow(debts, start: start);
    expect(due, closeTo(pay + (20000 + 20000 * 16 / 1200) * 0.08, 0.01));

    final within = PayoffPlanner.planWithin(debts, start: start, budget: 15000)!;
    final same = PayoffPlanner.plan(debts, start: start, extra: 15000 - due);
    expect(within.firstMonthPayment, closeTo(15000, 0.01));
    expect(within.months, same.months);
    expect(within.totalInterest, closeTo(same.totalInterest, 0.01));

    // Exactly what is due still works; anything less does not cover it.
    expect(PayoffPlanner.planWithin(debts, start: start, budget: due), isNotNull);
    expect(PayoffPlanner.planWithin(debts, start: start, budget: due - 1), isNull);
  });

  test('a minimum that never beats the interest never finishes', () {
    const debt = PayoffDebt(id: 'x', name: 'ผ่อนน้อยเกิน', balance: 100000, annualRate: 24, payment: 1000);
    final r = PayoffPlanner.baseline([debt], start: start);
    expect(r.months, isNull);
    expect(r.balances, hasLength(PayoffPlanner.maxMonths + 1));
  });
}
