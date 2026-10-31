import '../../core/date_utils.dart';
import 'enums.dart';

/// A card or loan contract. Balances and interest live on its [CreditLine]s
/// (sub-limits) and installment plans, so one card can hold e.g. a revolving
/// credit limit and a personal-loan limit at different rates.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    this.issuer,
    this.cardLast4,
    this.billingDay,
    this.dueDay,
    this.statementBalance = 0,
    this.minimumPayment = 0,
    this.statementDate,
    this.statementDueDate,
    this.sharedLimit,
    this.reminderDaysBefore = 3,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String name;
  final AccountType type;

  /// Bank id from the SMS pattern config (e.g. "ktc"), used to match SMS.
  final String? issuer;
  final String? cardLast4;

  /// วันตัดรอบบิล (1-31).
  final int? billingDay;

  /// วันครบกำหนดชำระ (1-31).
  final int? dueDay;

  /// ยอดเรียกเก็บงวดล่าสุด.
  final double statementBalance;

  /// ยอดขั้นต่ำงวดล่าสุด.
  final double minimumPayment;

  /// Date of the latest statement (payments after this count toward it).
  final DateTime? statementDate;

  /// Exact due date of the latest statement, when known (e.g. from SMS).
  final DateTime? statementDueDate;

  /// Overall limit when sub-limits share one pool; null = sum of sub-limits.
  final double? sharedLimit;
  final int reminderDaysBefore;
  final String? note;
  final DateTime createdAt;

  Account withStatement({
    required double statementBalance,
    required double minimumPayment,
    required DateTime statementDate,
    DateTime? statementDueDate,
  }) {
    return Account(
      id: id,
      name: name,
      type: type,
      issuer: issuer,
      cardLast4: cardLast4,
      billingDay: billingDay,
      dueDay: dueDay,
      statementBalance: statementBalance,
      minimumPayment: minimumPayment,
      statementDate: statementDate,
      statementDueDate: statementDueDate,
      sharedLimit: sharedLimit,
      reminderDaysBefore: reminderDaysBefore,
      note: note,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'issuer': issuer,
        'card_last4': cardLast4,
        'billing_day': billingDay,
        'due_day': dueDay,
        'statement_balance': statementBalance,
        'minimum_payment': minimumPayment,
        'statement_date': statementDate == null ? null : isoDate(statementDate!),
        'statement_due_date':
            statementDueDate == null ? null : isoDate(statementDueDate!),
        'shared_limit': sharedLimit,
        'reminder_days_before': reminderDaysBefore,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as String,
        name: m['name'] as String,
        type: AccountType.fromName(m['type'] as String?),
        issuer: m['issuer'] as String?,
        cardLast4: m['card_last4'] as String?,
        billingDay: (m['billing_day'] as num?)?.toInt(),
        dueDay: (m['due_day'] as num?)?.toInt(),
        statementBalance: (m['statement_balance'] as num?)?.toDouble() ?? 0,
        minimumPayment: (m['minimum_payment'] as num?)?.toDouble() ?? 0,
        statementDate: parseIsoDate(m['statement_date']),
        statementDueDate: parseIsoDate(m['statement_due_date']),
        sharedLimit: (m['shared_limit'] as num?)?.toDouble(),
        reminderDaysBefore: (m['reminder_days_before'] as num?)?.toInt() ?? 3,
        note: m['note'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
