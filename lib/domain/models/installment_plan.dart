import '../../core/date_utils.dart';
import 'enums.dart';

/// A fixed-term installment contract (ผ่อนสินค้า, แบ่งจ่าย, สินเชื่อก้อน).
/// Its progress (paid installments, remaining principal, interest paid) is
/// never stored: it is replayed from the payment log by `InstallmentEngine`,
/// so deleting or editing a payment can never leave the plan out of sync.
class InstallmentPlan {
  const InstallmentPlan({
    required this.id,
    required this.accountId,
    this.creditLineId,
    required this.name,
    required this.principal,
    required this.annualRate,
    required this.interestMethod,
    required this.termMonths,
    this.monthlyPaymentOverride,
    required this.startDate,
    this.lockInMonths = 0,
    this.penaltyPercent = 0,
    this.penaltyFixed = 0,
    this.includedInStatement = false,
    this.paidBeforeTracking = 0,
    this.anchorDay,
    this.postedThrough,
    this.note,
    required this.createdAt,
  });

  /// First cutoff of a card-billed plan whose first [posted] installments
  /// are on the card already: the next one goes on at the next cutoff.
  static DateTime firstCutoff({required int billingDay, required int posted, required DateTime today}) =>
      addMonths(nextDayAfter(billingDay, today), -posted, anchorDay: billingDay);

  final String id;
  final String accountId;

  /// Sub-limit whose available credit this plan consumes (optional).
  final String? creditLineId;
  final String name;
  final double principal;

  /// Annual rate in percent, interpreted by [interestMethod].
  final double annualRate;
  final InterestMethod interestMethod;
  final int termMonths;

  /// Installment fixed by the bank; null = compute from principal/rate/term.
  final double? monthlyPaymentOverride;

  /// Due date of the first installment. For a plan billed through the card
  /// it is the cutoff the bank puts the first installment on the card.
  final DateTime startDate;

  /// No early closure allowed during the first N months.
  final int lockInMonths;

  /// Early-closure fee as % of the remaining principal.
  final double penaltyPercent;

  /// Early-closure fee as a fixed amount.
  final double penaltyFixed;

  /// True when the bank bills this installment inside the card statement:
  /// the dashboard must not add it a second time, and installments advance
  /// automatically on each cutoff (you pay the card, not the plan).
  final bool includedInStatement;

  /// Installments already paid (on the card, for a card-billed plan) before
  /// the plan was added to the app.
  final int paidBeforeTracking;

  /// Day of month the schedule keeps after a short month (the card's
  /// cutoff day for a card-billed plan); null = [startDate]'s day.
  final int? anchorDay;

  /// Card-billed plans: how many installments the app has put on the
  /// sub-limit balance. Null = not started (saved by an older version).
  final int? postedThrough;
  final String? note;
  final DateTime createdAt;

  DateTime dueDateOf(int installmentNumber) =>
      addMonths(startDate, installmentNumber - 1, anchorDay: anchorDay ?? startDate.day);

  InstallmentPlan copyWith({DateTime? startDate, int? anchorDay, int? postedThrough}) => InstallmentPlan(
        id: id,
        accountId: accountId,
        creditLineId: creditLineId,
        name: name,
        principal: principal,
        annualRate: annualRate,
        interestMethod: interestMethod,
        termMonths: termMonths,
        monthlyPaymentOverride: monthlyPaymentOverride,
        startDate: startDate ?? this.startDate,
        lockInMonths: lockInMonths,
        penaltyPercent: penaltyPercent,
        penaltyFixed: penaltyFixed,
        includedInStatement: includedInStatement,
        paidBeforeTracking: paidBeforeTracking,
        anchorDay: anchorDay ?? this.anchorDay,
        postedThrough: postedThrough ?? this.postedThrough,
        note: note,
        createdAt: createdAt,
      );

  DateTime? get earliestClosureDate =>
      lockInMonths > 0 ? addMonths(startDate, lockInMonths) : null;

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'credit_line_id': creditLineId,
        'name': name,
        'principal': principal,
        'annual_rate': annualRate,
        'interest_method': interestMethod.name,
        'term_months': termMonths,
        'monthly_payment_override': monthlyPaymentOverride,
        'start_date': isoDate(startDate),
        'lock_in_months': lockInMonths,
        'penalty_percent': penaltyPercent,
        'penalty_fixed': penaltyFixed,
        'included_in_statement': includedInStatement ? 1 : 0,
        'paid_before_tracking': paidBeforeTracking,
        'anchor_day': anchorDay,
        'posted_through': postedThrough,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  factory InstallmentPlan.fromMap(Map<String, Object?> m) => InstallmentPlan(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        creditLineId: m['credit_line_id'] as String?,
        name: m['name'] as String,
        principal: (m['principal'] as num).toDouble(),
        annualRate: (m['annual_rate'] as num?)?.toDouble() ?? 0,
        interestMethod: InterestMethod.fromName(m['interest_method'] as String?),
        termMonths: (m['term_months'] as num).toInt(),
        monthlyPaymentOverride:
            (m['monthly_payment_override'] as num?)?.toDouble(),
        startDate: DateTime.parse(m['start_date'] as String),
        lockInMonths: (m['lock_in_months'] as num?)?.toInt() ?? 0,
        penaltyPercent: (m['penalty_percent'] as num?)?.toDouble() ?? 0,
        penaltyFixed: (m['penalty_fixed'] as num?)?.toDouble() ?? 0,
        includedInStatement:
            ((m['included_in_statement'] as num?)?.toInt() ?? 0) == 1,
        paidBeforeTracking: (m['paid_before_tracking'] as num?)?.toInt() ?? 0,
        anchorDay: (m['anchor_day'] as num?)?.toInt(),
        postedThrough: (m['posted_through'] as num?)?.toInt(),
        note: m['note'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
