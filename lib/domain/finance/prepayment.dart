import 'dart:math' as math;

import '../models/enums.dart';
import 'loan_state.dart';

class PrepaymentOutcome {
  const PrepaymentOutcome({
    required this.mode,
    required this.after,
    required this.remainingInterest,
    required this.interestSaved,
    required this.months,
    required this.monthsSaved,
    required this.totalOutlay,
  });

  final PrepaymentMode mode;
  final LoanState after;
  final double remainingInterest;
  final double interestSaved;

  /// Installments left after the prepayment.
  final int months;
  final int monthsSaved;

  /// Extra + every remaining installment (+ penalty).
  final double totalOutlay;

  double get newPayment => after.isClosed ? 0 : after.payment;
}

/// "What if I prepay X now?" for both re-amortization strategies.
class PrepaymentComparison {
  const PrepaymentComparison({
    required this.before,
    required this.extra,
    required this.penalty,
    required this.baselineInterest,
    required this.baselineMonths,
    required this.reducePayment,
    required this.reduceTerm,
  });

  factory PrepaymentComparison.compute(LoanState before, double extra, {double penalty = 0}) {
    final baseline = before.project();
    final baselineInterest = baseline.fold(0.0, (s, r) => s + r.interest);
    final baselineMonths = baseline.length;
    final applied = math.min(extra, before.balance);

    PrepaymentOutcome outcome(PrepaymentMode mode) {
      final after = before.prepay(applied, mode);
      final rows = after.project();
      final interest = rows.fold(0.0, (s, r) => s + r.interest);
      final outlay = applied + penalty + rows.fold(0.0, (s, r) => s + r.payment);
      return PrepaymentOutcome(
        mode: mode,
        after: after,
        remainingInterest: interest,
        interestSaved: baselineInterest - interest - penalty,
        months: rows.length,
        monthsSaved: baselineMonths - rows.length,
        totalOutlay: outlay,
      );
    }

    return PrepaymentComparison(
      before: before,
      extra: applied,
      penalty: penalty,
      baselineInterest: baselineInterest,
      baselineMonths: baselineMonths,
      reducePayment: outcome(PrepaymentMode.reducePayment),
      reduceTerm: outcome(PrepaymentMode.reduceTerm),
    );
  }

  final LoanState before;
  final double extra;
  final double penalty;
  final double baselineInterest;
  final int baselineMonths;
  final PrepaymentOutcome reducePayment;
  final PrepaymentOutcome reduceTerm;

  PrepaymentOutcome get bestForInterest =>
      reduceTerm.interestSaved >= reducePayment.interestSaved ? reduceTerm : reducePayment;
}
