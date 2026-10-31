import 'dart:math' as math;

/// Pure loan formulas. Rates passed as "annual" are percentages (16 = 16%).
class LoanMath {
  LoanMath._();

  static const _eps = 1e-12;

  static double monthlyRate(double annualPercent) => annualPercent / 1200;

  /// Standard amortization: `payment = P × r / (1 − (1 + r)^−n)`.
  static double amortizedPayment(double principal, double monthlyRate, int months) {
    if (months <= 0) return principal;
    if (monthlyRate.abs() < _eps) return principal / months;
    return principal * monthlyRate / (1 - math.pow(1 + monthlyRate, -months));
  }

  /// Flat rate: the same interest every month, computed on the original
  /// principal no matter how much has been repaid.
  static double flatInterestPerMonth(double principal, double annualPercent) =>
      principal * annualPercent / 1200;

  static double flatMonthlyPayment(double principal, double annualPercent, int months) =>
      principal / months + flatInterestPerMonth(principal, annualPercent);

  static double flatTotalInterest(double principal, double annualPercent, int months) =>
      flatInterestPerMonth(principal, annualPercent) * months;

  /// Total interest of a reducing-balance loan paid with equal installments.
  static double reducingTotalInterest(double principal, double annualPercent, int months) =>
      amortizedPayment(principal, monthlyRate(annualPercent), months) * months -
      principal;

  /// The true (effective, reducing-balance) annual rate of a loan where
  /// [principal] is repaid with [months] equal payments of [payment].
  /// This is the monthly IRR × 12, the convention Thai lenders disclose as
  /// "อัตราดอกเบี้ยที่แท้จริง".
  static double effectiveAnnualRate(double principal, double payment, int months) {
    if (principal <= 0 || months <= 0) return 0;
    if (payment * months <= principal + 1e-9) return 0;
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 200; i++) {
      final mid = (lo + hi) / 2;
      if (amortizedPayment(principal, mid, months) > payment) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return (lo + hi) / 2 * 1200;
  }

  /// Converts an advertised flat rate to its effective equivalent.
  static double flatToEffectiveAnnualRate(double flatAnnualPercent, int months) =>
      effectiveAnnualRate(1, flatMonthlyPayment(1, flatAnnualPercent, months), months);

  /// Outstanding balance of a reducing-balance loan after [k] payments.
  static double balanceAfter(double principal, double monthlyRate, double payment, int k) {
    if (monthlyRate.abs() < _eps) return math.max(0, principal - payment * k);
    final g = math.pow(1 + monthlyRate, k).toDouble();
    return math.max(0, principal * g - payment * (g - 1) / monthlyRate);
  }

  /// Number of [payment]s needed to clear [balance], or null when the
  /// payment does not even cover the interest (the debt never shrinks).
  static int? monthsToPayoff(double balance, double monthlyRate, double payment) {
    if (balance <= 0) return 0;
    if (payment <= 0) return null;
    if (monthlyRate.abs() < _eps) return (balance / payment - 1e-9).ceil();
    if (payment <= balance * monthlyRate) return null;
    final n = -math.log(1 - monthlyRate * balance / payment) / math.log(1 + monthlyRate);
    return (n - 1e-9).ceil();
  }

  static double round2(double v) => (v * 100).roundToDouble() / 100;
}
