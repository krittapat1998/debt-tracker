import '../../core/date_utils.dart';
import 'enums.dart';

/// One real-world payment (every transfer to a card/loan).
class Payment {
  const Payment({
    required this.id,
    required this.accountId,
    this.creditLineId,
    this.planId,
    required this.date,
    required this.amount,
    required this.type,
    this.prepaymentMode,
    this.note,
    this.source = PaymentSource.manual,
    this.lineBalanceApplied = 0,
    required this.createdAt,
  });

  final String id;
  final String accountId;

  /// Target sub-limit for revolving payments.
  final String? creditLineId;

  /// Target installment plan, when paying an installment or prepaying it.
  final String? planId;
  final DateTime date;
  final double amount;
  final PaymentType type;

  /// For [PaymentType.extra] on a plan: how the plan is re-amortized.
  final PrepaymentMode? prepaymentMode;
  final String? note;
  final PaymentSource source;

  /// How much this payment reduced the sub-limit balance (for exact undo).
  final double lineBalanceApplied;
  final DateTime createdAt;

  Payment copyWith({double? lineBalanceApplied}) => Payment(
        id: id,
        accountId: accountId,
        creditLineId: creditLineId,
        planId: planId,
        date: date,
        amount: amount,
        type: type,
        prepaymentMode: prepaymentMode,
        note: note,
        source: source,
        lineBalanceApplied: lineBalanceApplied ?? this.lineBalanceApplied,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'credit_line_id': creditLineId,
        'plan_id': planId,
        'date': isoDate(date),
        'amount': amount,
        'type': type.name,
        'prepayment_mode': prepaymentMode?.name,
        'note': note,
        'source': source.name,
        'line_balance_applied': lineBalanceApplied,
        'created_at': createdAt.toIso8601String(),
      };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        creditLineId: m['credit_line_id'] as String?,
        planId: m['plan_id'] as String?,
        date: DateTime.parse(m['date'] as String),
        amount: (m['amount'] as num).toDouble(),
        type: PaymentType.fromName(m['type'] as String?),
        prepaymentMode: PrepaymentMode.fromName(m['prepayment_mode'] as String?),
        note: m['note'] as String?,
        source: PaymentSource.fromName(m['source'] as String?),
        lineBalanceApplied:
            (m['line_balance_applied'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
