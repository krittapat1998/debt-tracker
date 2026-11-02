import 'package:debt_tracker/domain/finance/loan_math.dart';
import 'package:debt_tracker/domain/finance/loan_state.dart';
import 'package:debt_tracker/domain/finance/prepayment.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amortization formula', () {
    test('payment = P × r / (1 − (1 + r)^−n)', () {
      // 100,000 at 12% p.a. over 12 months.
      expect(LoanMath.amortizedPayment(100000, 0.01, 12), closeTo(8884.88, 0.01));
    });

    test('zero rate splits principal evenly', () {
      expect(LoanMath.amortizedPayment(12000, 0, 12), 1000);
      expect(LoanMath.monthsToPayoff(12000, 0, 1000), 12);
    });

    test('balanceAfter matches the projected schedule', () {
      final s = LoanState.initial(
        method: InterestMethod.reducing,
        principal: 100000,
        annualRate: 12,
        termMonths: 12,
      );
      final rows = s.project();
      expect(rows, hasLength(12));
      expect(rows[5].balance,
          closeTo(LoanMath.balanceAfter(100000, 0.01, s.payment, 6), 0.01));
      expect(rows.last.balance, 0);
    });

    test('principalForPayment undoes the installment formula, reducing and flat', () {
      expect(LoanMath.principalForPayment(8884.88, 12, 12), closeTo(100000, 0.1));
      expect(LoanMath.principalForPayment(1000, 0, 12), 12000);
      final flat = LoanMath.flatMonthlyPayment(60000, 15, 24);
      expect(LoanMath.principalForPayment(flat, 15, 24, flat: true), closeTo(60000, 0.001));
      expect(LoanMath.principalForPayment(0, 25, 11), 0);
    });

    test('monthsToPayoff returns null when payment does not cover interest', () {
      expect(LoanMath.monthsToPayoff(100000, 0.01, 1000), isNull);
      expect(LoanMath.monthsToPayoff(100000, 0.01, 8884.88), 12);
    });
  });

  group('reducing balance vs flat rate', () {
    test('reducing balance total interest', () {
      expect(LoanMath.reducingTotalInterest(100000, 12, 12), closeTo(6618.55, 0.01));
    });

    test('flat interest is charged on the original principal every month', () {
      expect(LoanMath.flatTotalInterest(100000, 10, 12), closeTo(10000, 1e-9));
      expect(LoanMath.flatMonthlyPayment(100000, 10, 12), closeTo(9166.67, 0.01));

      final s = LoanState.initial(
        method: InterestMethod.flat,
        principal: 100000,
        annualRate: 10,
        termMonths: 12,
      );
      final rows = s.project();
      expect(rows, hasLength(12));
      for (final r in rows) {
        expect(r.interest, closeTo(833.33, 0.01));
        expect(r.principal, closeTo(8333.33, 0.01));
      }
      expect(rows.fold(0.0, (t, r) => t + r.interest), closeTo(10000, 0.01));
    });

    test('same headline rate: flat costs far more than reducing', () {
      final flat = LoanMath.flatTotalInterest(100000, 10, 36);
      final reducing = LoanMath.reducingTotalInterest(100000, 10, 36);
      expect(flat, closeTo(30000, 0.01));
      expect(reducing, closeTo(16161.87, 0.01));
      expect(flat / reducing, greaterThan(1.8));
    });

    test('flat 10% is ~18% effective (almost double)', () {
      expect(LoanMath.flatToEffectiveAnnualRate(10, 12), closeTo(17.97, 0.01));
      expect(LoanMath.flatToEffectiveAnnualRate(10, 24), closeTo(18.16, 0.01));
      expect(LoanMath.flatToEffectiveAnnualRate(10, 36), closeTo(17.92, 0.01));
      expect(LoanMath.flatToEffectiveAnnualRate(10, 60), closeTo(17.27, 0.01));
    });

    test('effective rate of a reducing loan round-trips', () {
      final p = LoanMath.amortizedPayment(250000, LoanMath.monthlyRate(25), 48);
      expect(LoanMath.effectiveAnnualRate(250000, p, 48), closeTo(25, 1e-6));
    });

    test('bank-defined installment overrides the computed one', () {
      final s = LoanState.initial(
        method: InterestMethod.flat,
        principal: 12000,
        annualRate: 0,
        termMonths: 12,
        paymentOverride: 1100,
      );
      // 1,100 − 1,000 principal = 100 interest per month.
      expect(s.flatInterestPerMonth, closeTo(100, 1e-9));
      expect(s.annualRate, closeTo(10, 1e-9));
      expect(s.projectedInterest, closeTo(1200, 0.01));
    });
  });

  group('extra prepayment', () {
    LoanState afterSixPayments() {
      var s = LoanState.initial(
        method: InterestMethod.reducing,
        principal: 100000,
        annualRate: 12,
        termMonths: 12,
      );
      for (var i = 0; i < 6; i++) {
        s = s.payInstallment().state;
      }
      return s;
    }

    test('state after 6 installments', () {
      final s = afterSixPayments();
      expect(s.balance, closeTo(51492.11, 0.01));
      expect(s.remainingTerm, 6);
      expect(s.projectedInterest, closeTo(1817.17, 0.01));
    });

    test('reduce payment keeps the term and lowers the installment', () {
      final after = afterSixPayments().prepay(20000, PrepaymentMode.reducePayment);
      expect(after.balance, closeTo(31492.11, 0.01));
      expect(after.remainingTerm, 6);
      expect(after.payment, closeTo(5433.91, 0.01));
      expect(after.projectedInterest, closeTo(1111.36, 0.01));
    });

    test('reduce term keeps the installment and closes sooner', () {
      final before = afterSixPayments();
      final after = before.prepay(20000, PrepaymentMode.reduceTerm);
      expect(after.payment, closeTo(before.payment, 1e-9));
      expect(after.remainingTerm, 4);
      expect(after.projectedMonths, 4);
      expect(after.projectedInterest, closeTo(742.05, 0.01));
    });

    test('comparison: reduce term saves more interest on a reducing loan', () {
      final c = PrepaymentComparison.compute(afterSixPayments(), 20000);
      expect(c.baselineInterest, closeTo(1817.17, 0.01));
      expect(c.reducePayment.interestSaved, closeTo(705.80, 0.01));
      expect(c.reduceTerm.interestSaved, closeTo(1075.12, 0.01));
      expect(c.reduceTerm.monthsSaved, 2);
      expect(c.bestForInterest.mode, PrepaymentMode.reduceTerm);
    });

    test('penalty is subtracted from the savings', () {
      final c = PrepaymentComparison.compute(afterSixPayments(), 20000, penalty: 300);
      expect(c.reduceTerm.interestSaved, closeTo(775.12, 0.01));
    });

    test('prepaying more than the balance closes the loan', () {
      final after = afterSixPayments().prepay(1e9, PrepaymentMode.reduceTerm);
      expect(after.isClosed, isTrue);
      expect(after.project(), isEmpty);
    });

    test('flat loan: prepayment re-computes flat interest on the new principal', () {
      var s = LoanState.initial(
        method: InterestMethod.flat,
        principal: 120000,
        annualRate: 10,
        termMonths: 12,
      );
      for (var i = 0; i < 6; i++) {
        s = s.payInstallment().state;
      }
      expect(s.balance, closeTo(60000, 0.01));
      expect(s.projectedInterest, closeTo(6000, 0.01));

      final reducePayment = s.prepay(30000, PrepaymentMode.reducePayment);
      expect(reducePayment.remainingTerm, 6);
      expect(reducePayment.flatInterestPerMonth, closeTo(250, 0.01));
      expect(reducePayment.payment, closeTo(5250, 0.01));
      expect(reducePayment.projectedInterest, closeTo(1500, 0.01));

      final reduceTerm = s.prepay(30000, PrepaymentMode.reduceTerm);
      expect(reduceTerm.payment, closeTo(s.payment, 1e-9));
      // 11,000 − 250 interest = 10,750 principal/month → 3 installments.
      expect(reduceTerm.remainingTerm, 3);
      expect(reduceTerm.projectedInterest, closeTo(750, 0.01));
    });
  });
}
