import '../../core/date_utils.dart';
import 'enums.dart';

/// One purchase charged to a sub-limit (added to its revolving balance).
class Spending {
  const Spending({
    required this.id,
    required this.accountId,
    this.creditLineId,
    required this.date,
    required this.amount,
    this.note,
    this.source = PaymentSource.manual,
    required this.createdAt,
  });

  final String id;
  final String accountId;

  /// Sub-limit whose balance this was added to.
  final String? creditLineId;
  final DateTime date;
  final double amount;

  /// What it was for, e.g. "ค่าอาหาร".
  final String? note;
  final PaymentSource source;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'credit_line_id': creditLineId,
        'date': isoDate(date),
        'amount': amount,
        'note': note,
        'source': source.name,
        'created_at': createdAt.toIso8601String(),
      };

  factory Spending.fromMap(Map<String, Object?> m) => Spending(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        creditLineId: m['credit_line_id'] as String?,
        date: DateTime.parse(m['date'] as String),
        amount: (m['amount'] as num).toDouble(),
        note: m['note'] as String?,
        source: PaymentSource.fromName(m['source'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
