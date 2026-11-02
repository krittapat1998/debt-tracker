import 'package:debt_tracker/domain/finance/due_calendar.dart';
import 'package:debt_tracker/domain/finance/portfolio.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
import 'package:debt_tracker/domain/models/recurring_charge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 11, 2);
  final created = DateTime(2026, 6, 1);

  PortfolioSummary portfolio() => PortfolioSummary.build(
        accounts: [
          Account(id: 'k', name: 'KTC', type: AccountType.creditCard, billingDay: 20, dueDay: 5, statementBalance: 15000,
              minimumPayment: 1500, statementDate: DateTime(2026, 10, 20), createdAt: created),
          Account(id: 'u', name: 'UOB Express', type: AccountType.personalLoan, createdAt: created),
        ],
        lines: [
          const CreditLine(id: 'kl', accountId: 'k', name: 'บัตร', creditLimit: 50000, balance: 15000, annualRate: 16),
        ],
        plans: [
          InstallmentPlan(id: 'loan', accountId: 'u', name: 'สินเชื่อ', principal: 30000, annualRate: 25,
              interestMethod: InterestMethod.reducing, termMonths: 11, startDate: DateTime(2026, 10, 20), createdAt: created),
          InstallmentPlan(id: 'tv', accountId: 'k', creditLineId: 'kl', name: 'ผ่อนทีวี', principal: 12000, annualRate: 0,
              interestMethod: InterestMethod.reducing, termMonths: 12, startDate: DateTime(2026, 8, 20),
              includedInStatement: true, anchorDay: 20, postedThrough: 3, createdAt: created),
        ],
        payments: [
          Payment(id: 'p1', accountId: 'u', planId: 'loan', date: DateTime(2026, 10, 19), amount: 3100,
              type: PaymentType.installment, createdAt: DateTime(2026, 10, 19)),
        ],
        recurring: [
          RecurringCharge(id: 'n', accountId: 'k', creditLineId: 'kl', name: 'Netflix', amount: 419,
              nextDate: DateTime(2026, 11, 15), anchorDay: 15, createdAt: created),
        ],
        today: today,
      );

  test('November: the KTC bill with its minimum, cutoff with the TV installment, loan, Netflix', () {
    final events = dueEvents(portfolio(), DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    String show(DueEvent e) => '${e.date.day} ${e.kind.name} ${e.title} ${e.amount?.toStringAsFixed(0)} ${e.paid}';
    expect(events.map(show), [
      '5 cardDue KTC 1500 false',
      '15 recurring Netflix 419 false',
      '20 installment สินเชื่อ งวด 2/11 ${portfolio().byId('u')!.plans.single.nextRow!.payment.toStringAsFixed(0)} false',
      '20 cutoff KTC null false',
      '20 cutoff ผ่อนทีวี งวด 4/12 1000 false',
    ]);
  });

  test('October shows what was paid; December has a bill with no amount yet', () {
    final october = dueEvents(portfolio(), DateTime(2026, 10, 1), DateTime(2026, 10, 31));
    final loan = october.singleWhere((e) => e.kind == DueEventKind.installment);
    expect((loan.date, loan.paid), (DateTime(2026, 10, 20), true));

    final december = dueEvents(portfolio(), DateTime(2026, 12, 1), DateTime(2026, 12, 31));
    final bill = december.singleWhere((e) => e.kind == DueEventKind.cardDue);
    expect((bill.date, bill.amount), (DateTime(2026, 12, 5), null));
    expect(december.where((e) => e.kind == DueEventKind.recurring).single.date, DateTime(2026, 12, 15));
  });
}
