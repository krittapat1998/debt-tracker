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
    this.lineBalanceApplied = 0,
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

  /// How much this added to the sub-limit balance: 0 when the balance was
  /// typed in from the bank after it and already had it.
  final double lineBalanceApplied;
  final DateTime createdAt;

  Spending copyWith({double? lineBalanceApplied}) => Spending(
        id: id,
        accountId: accountId,
        creditLineId: creditLineId,
        date: date,
        amount: amount,
        note: note,
        source: source,
        lineBalanceApplied: lineBalanceApplied ?? this.lineBalanceApplied,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'credit_line_id': creditLineId,
        'date': isoDate(date),
        'amount': amount,
        'note': note,
        'source': source.name,
        'line_balance_applied': lineBalanceApplied,
        'created_at': createdAt.toIso8601String(),
      };

  factory Spending.fromMap(Map<String, Object?> m) {
    final lineId = m['credit_line_id'] as String?;
    final amount = (m['amount'] as num).toDouble();
    return Spending(
      id: m['id'] as String,
      accountId: m['account_id'] as String,
      creditLineId: lineId,
      date: DateTime.parse(m['date'] as String),
      amount: amount,
      note: m['note'] as String?,
      source: PaymentSource.fromName(m['source'] as String?),
      // Rows from before version 3 (and old backups) always added their amount.
      lineBalanceApplied: (m['line_balance_applied'] as num?)?.toDouble() ?? (lineId != null ? amount : 0),
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
