import 'dart:math' as math;

import '../../core/date_utils.dart';
import '../models/enums.dart';
import '../models/installment_plan.dart';
import '../models/payment.dart';
import 'loan_math.dart';
import 'loan_state.dart';

/// Snapshot of an installment plan rebuilt from its payment history.
class InstallmentState {
  const InstallmentState({
    required this.plan,
    required this.initial,
    required this.current,
    required this.paidRows,
    required this.projection,
    required this.interestPaid,
    required this.principalPaid,
    required this.extraPaid,
  });

  final InstallmentPlan plan;
  final LoanState initial;
  final LoanState current;
  final List<ScheduleRow> paidRows;
  final List<ScheduleRow> projection;
  final double interestPaid;
  final double principalPaid;
  final double extraPaid;

  int get paidInstallments => paidRows.length;
  int get remainingInstallments => projection.length;
  double get remainingPrincipal => current.isClosed ? 0 : current.balance;
  double get currentPayment => current.payment;
  bool get isClosed => current.isClosed;

  double get projectedRemainingInterest =>
      projection.fold(0.0, (s, r) => s + r.interest);

  /// Interest of the original contract if no prepayment ever happened.
  double get originalTotalInterest => initial.projectedInterest;

  /// Interest already avoided thanks to prepayments so far.
  double get interestSavedSoFar =>
      math.max(0, originalTotalInterest - interestPaid - projectedRemainingInterest);

  DateTime? get nextDueDate => projection.isEmpty ? null : projection.first.dueDate;
  ScheduleRow? get nextRow => projection.isEmpty ? null : projection.first;
  DateTime? get projectedPayoffDate => projection.isEmpty ? null : projection.last.dueDate;

  /// The real cost of the plan expressed as a reducing-balance rate.
  double get effectiveAnnualRate => plan.interestMethod == InterestMethod.reducing
      ? plan.annualRate
      : LoanMath.effectiveAnnualRate(plan.principal, initial.payment, plan.termMonths);

  DateTime? get earliestClosureDate => plan.earliestClosureDate;

  bool isLockedOn(DateTime day) {
    final e = earliestClosureDate;
    return e != null && dateOnly(day).isBefore(e);
  }

  /// Early-closure fee if the remaining principal were paid off now.
  double get earlyClosurePenalty {
    if (isClosed || remainingInstallments <= 1) return 0;
    return remainingPrincipal * plan.penaltyPercent / 100 + plan.penaltyFixed;
  }

  double get payoffAmount => remainingPrincipal + earlyClosurePenalty;

  double get progress => plan.termMonths == 0
      ? 1
      : (paidInstallments / (paidInstallments + remainingInstallments)).clamp(0, 1);

  List<ScheduleRow> get fullSchedule => [...paidRows, ...projection];
}

class InstallmentEngine {
  InstallmentEngine._();

  static LoanState initialState(InstallmentPlan plan) => LoanState.initial(
        method: plan.interestMethod,
        principal: plan.principal,
        annualRate: plan.annualRate,
        termMonths: plan.termMonths,
        paymentOverride: plan.monthlyPaymentOverride,
      );

  /// Replays [payments] (any order, other plans are ignored) on top of the
  /// contract terms. For plans billed through the card statement, every
  /// installment due on or before [asOf] is advanced automatically, because
  /// the bank posts it whether or not the card was paid.
  static InstallmentState replay(
    InstallmentPlan plan,
    Iterable<Payment> payments, {
    required DateTime asOf,
  }) {
    final initial = initialState(plan);
    var state = initial;
    final paidRows = <ScheduleRow>[];
    var interestPaid = 0.0;
    var principalPaid = 0.0;
    var extraPaid = 0.0;

    void applyInstallment({double? amount, DateTime? paidOn, bool automatic = false}) {
      final step = state.payInstallment(amount);
      final number = paidRows.length + 1;
      paidRows.add(ScheduleRow(
        number: number,
        dueDate: plan.dueDateOf(number),
        payment: step.payment,
        interest: step.interest,
        principal: step.principal,
        balance: step.state.balance,
        paidOn: paidOn,
        automatic: automatic,
      ));
      interestPaid += step.interest;
      principalPaid += step.principal;
      state = step.state;
    }

    for (var i = 0; i < plan.paidBeforeTracking && !state.isClosed; i++) {
      applyInstallment(automatic: true);
    }

    final events = payments.where((p) => p.planId == plan.id).toList()
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
      });
    final today = dateOnly(asOf);

    void autoAdvanceUntil(DateTime limit, {required bool inclusive}) {
      if (!plan.includedInStatement) return;
      while (!state.isClosed) {
        final due = plan.dueDateOf(paidRows.length + 1);
        final reached = inclusive ? !due.isAfter(limit) : due.isBefore(limit);
        if (!reached || due.isAfter(today)) break;
        applyInstallment(automatic: true);
      }
    }

    for (final p in events) {
      autoAdvanceUntil(dateOnly(p.date), inclusive: false);
      if (state.isClosed) break;
      switch (p.type) {
        case PaymentType.extra:
        case PaymentType.full:
          final applied = math.min(p.amount, state.balance);
          extraPaid += applied;
          principalPaid += applied;
          state = state.prepay(
            p.amount,
            p.type == PaymentType.full
                ? PrepaymentMode.reduceTerm
                : (p.prepaymentMode ?? PrepaymentMode.reduceTerm),
          );
        case PaymentType.installment:
        case PaymentType.minimum:
        case PaymentType.other:
          // Statement-billed installments advance by schedule; a logged
          // installment would double count, so it only shows in history.
          if (!plan.includedInStatement) {
            applyInstallment(amount: p.amount, paidOn: p.date);
          }
      }
    }
    autoAdvanceUntil(today, inclusive: true);

    final projection = state.project(
      firstNumber: paidRows.length + 1,
      dueDateOf: plan.dueDateOf,
    );

    return InstallmentState(
      plan: plan,
      initial: initial,
      current: state,
      paidRows: paidRows,
      projection: projection,
      interestPaid: interestPaid,
      principalPaid: principalPaid,
      extraPaid: extraPaid,
    );
  }
}
