import 'dart:math' as math;

import '../models/enums.dart';
import 'loan_math.dart';

/// One installment in a schedule (paid or projected).
class ScheduleRow {
  const ScheduleRow({
    required this.number,
    this.dueDate,
    required this.payment,
    required this.interest,
    required this.principal,
    required this.balance,
    this.paidOn,
    this.automatic = false,
  });

  final int number;
  final DateTime? dueDate;
  final double payment;
  final double interest;
  final double principal;

  /// Remaining principal after this installment.
  final double balance;

  /// Date the payment was logged; null for projected rows.
  final DateTime? paidOn;

  /// Advanced automatically (billed through the card statement or paid
  /// before tracking) rather than from a logged payment.
  final bool automatic;

  bool get isPaid => paidOn != null || automatic;
}

class InstallmentStep {
  const InstallmentStep(this.state, this.interest, this.principal, this.payment);
  final LoanState state;
  final double interest;
  final double principal;
  final double payment;
}

/// The live terms of a loan at one point in time. Immutable: every payment
/// returns a new state, which makes replaying history and "what if"
/// simulations the same code path.
///
/// Reducing balance: interest = balance × r each month.
/// Flat: interest is a fixed amount per month ([flatInterestPerMonth]),
/// computed on the principal at the time of (re)amortization. After a
/// prepayment the flat interest is recomputed on the new, lower principal.
/// Real flat-rate contracts differ between lenders, so treat flat-rate
/// prepayment results as an estimate.
class LoanState {
  const LoanState({
    required this.method,
    required this.annualRate,
    required this.balance,
    required this.payment,
    required this.remainingTerm,
    this.flatInterestPerMonth = 0,
  });

  /// Terms of a brand-new loan. [paymentOverride] is the bank-defined
  /// installment if any; for flat loans it also defines the real interest.
  factory LoanState.initial({
    required InterestMethod method,
    required double principal,
    required double annualRate,
    required int termMonths,
    double? paymentOverride,
  }) {
    final n = math.max(1, termMonths);
    switch (method) {
      case InterestMethod.reducing:
        return LoanState(
          method: method,
          annualRate: annualRate,
          balance: principal,
          payment: paymentOverride ??
              LoanMath.amortizedPayment(principal, LoanMath.monthlyRate(annualRate), n),
          remainingTerm: n,
        );
      case InterestMethod.flat:
        final flatInterest = paymentOverride != null
            ? math.max(0.0, paymentOverride - principal / n)
            : LoanMath.flatInterestPerMonth(principal, annualRate);
        final impliedRate = principal > 0 ? flatInterest * 1200 / principal : annualRate;
        return LoanState(
          method: method,
          annualRate: impliedRate,
          balance: principal,
          payment: paymentOverride ?? principal / n + flatInterest,
          remainingTerm: n,
          flatInterestPerMonth: flatInterest,
        );
    }
  }

  final InterestMethod method;

  /// Annual % — reducing: the nominal rate; flat: the flat rate on the
  /// principal used for [flatInterestPerMonth].
  final double annualRate;
  final double balance;
  final double payment;
  final int remainingTerm;
  final double flatInterestPerMonth;

  double get monthlyRate => LoanMath.monthlyRate(annualRate);

  bool get isClosed => balance <= 0.005;

  double get nextInterest {
    if (isClosed) return 0;
    return method == InterestMethod.reducing ? balance * monthlyRate : flatInterestPerMonth;
  }

  /// The scheduled amount for the next installment (the last one clears
  /// whatever is left).
  double get nextPaymentDue {
    if (isClosed) return 0;
    final interest = nextInterest;
    if (remainingTerm <= 1 || payment - interest >= balance) return balance + interest;
    return payment;
  }

  LoanState _copy({double? balance, double? payment, int? remainingTerm, double? flatInterestPerMonth, double? annualRate}) {
    return LoanState(
      method: method,
      annualRate: annualRate ?? this.annualRate,
      balance: balance ?? this.balance,
      payment: payment ?? this.payment,
      remainingTerm: remainingTerm ?? this.remainingTerm,
      flatInterestPerMonth: flatInterestPerMonth ?? this.flatInterestPerMonth,
    );
  }

  LoanState get _closed => _copy(balance: 0, payment: 0, remainingTerm: 0, flatInterestPerMonth: 0);

  /// Pays one regular installment. [amount] defaults to [nextPaymentDue];
  /// a different amount moves principal accordingly (interest first).
  InstallmentStep payInstallment([double? amount]) {
    if (isClosed) return InstallmentStep(this, 0, 0, 0);
    final interest = nextInterest;
    final paid = amount ?? nextPaymentDue;
    final principalPart = math.min(paid - interest, balance);
    final newBalance = balance - principalPart;
    final next = newBalance <= 0.005
        ? _closed
        : _copy(balance: newBalance, remainingTerm: math.max(0, remainingTerm - 1));
    return InstallmentStep(next, interest, principalPart, paid);
  }

  /// Applies an extra principal prepayment and re-amortizes the rest.
  LoanState prepay(double extra, PrepaymentMode mode) {
    if (isClosed) return this;
    final b = balance - extra;
    if (b <= 0.005) return _closed;
    final t = math.max(1, remainingTerm);
    switch (method) {
      case InterestMethod.reducing:
        final r = monthlyRate;
        if (mode == PrepaymentMode.reducePayment) {
          return _copy(balance: b, payment: LoanMath.amortizedPayment(b, r, t), remainingTerm: t);
        }
        final months = LoanMath.monthsToPayoff(b, r, payment) ?? t;
        return _copy(balance: b, remainingTerm: math.min(months, t));
      case InterestMethod.flat:
        final flatInterest = LoanMath.flatInterestPerMonth(b, annualRate);
        if (mode == PrepaymentMode.reducePayment) {
          return _copy(balance: b, payment: b / t + flatInterest, remainingTerm: t, flatInterestPerMonth: flatInterest);
        }
        final principalPerMonth = payment - flatInterest;
        final months = principalPerMonth > 0 ? (b / principalPerMonth - 1e-9).ceil() : t;
        return _copy(balance: b, remainingTerm: math.min(months, t), flatInterestPerMonth: flatInterest);
    }
  }

  /// The same loan from now on at [rate], e.g. when a promotional rate
  /// ends. A bank-fixed installment ([keepPayment]) stays; otherwise the
  /// payment is re-amortized over the remaining term. Reducing balance only.
  LoanState atRate(double rate, {required bool keepPayment}) {
    if (method != InterestMethod.reducing || isClosed || (rate - annualRate).abs() < 1e-9) return this;
    return _copy(
      annualRate: rate,
      payment: keepPayment
          ? payment
          : LoanMath.amortizedPayment(balance, LoanMath.monthlyRate(rate), math.max(1, remainingTerm)),
    );
  }

  /// Future installments if every one is paid as scheduled. Dates are
  /// attached by the caller through [dueDateOf]; [rateOf] gives a
  /// promotional plan's rate per installment (see [atRate]).
  List<ScheduleRow> project({
    int firstNumber = 1,
    DateTime? Function(int number)? dueDateOf,
    double Function(int number)? rateOf,
    bool keepPayment = true,
    int maxRows = 600,
  }) {
    final rows = <ScheduleRow>[];
    var s = this;
    var number = firstNumber;
    while (!s.isClosed && rows.length < maxRows) {
      if (rateOf != null) s = s.atRate(rateOf(number), keepPayment: keepPayment);
      final step = s.payInstallment();
      if (step.principal <= 0 && step.state.balance >= s.balance) break; // never amortizes
      rows.add(ScheduleRow(
        number: number,
        dueDate: dueDateOf?.call(number),
        payment: step.payment,
        interest: step.interest,
        principal: step.principal,
        balance: step.state.balance,
      ));
      s = step.state;
      number++;
    }
    return rows;
  }

  double get projectedInterest => project().fold(0.0, (sum, r) => sum + r.interest);

  int get projectedMonths => project().length;
}
