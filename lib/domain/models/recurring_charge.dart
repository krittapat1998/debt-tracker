import '../../core/date_utils.dart';
import 'enums.dart';

/// A charge the card takes again and again, e.g. Netflix every month on the
/// 15th. Each date it comes due becomes a spending entry.
class RecurringCharge {
  const RecurringCharge({
    required this.id,
    required this.accountId,
    this.creditLineId,
    required this.name,
    required this.amount,
    this.interval = RecurrenceInterval.monthly,
    required this.nextDate,
    required this.anchorDay,
    this.active = true,
    required this.createdAt,
  });

  final String id;
  final String accountId;

  /// Sub-limit each charge is added to.
  final String? creditLineId;
  final String name;
  final double amount;
  final RecurrenceInterval interval;

  /// The next charge that hasn't been recorded yet.
  final DateTime nextDate;

  /// Day of month it is charged on. Kept apart from [nextDate] so a charge
  /// on the 31st goes back to the 31st after a short month.
  final int anchorDay;

  /// False while paused.
  final bool active;
  final DateTime createdAt;

  /// The charge date after [d].
  DateTime following(DateTime d) => addMonths(d, interval.months, anchorDay: anchorDay);

  RecurringCharge copyWith({DateTime? nextDate, bool? active}) => RecurringCharge(
        id: id,
        accountId: accountId,
        creditLineId: creditLineId,
        name: name,
        amount: amount,
        interval: interval,
        nextDate: nextDate ?? this.nextDate,
        anchorDay: anchorDay,
        active: active ?? this.active,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'credit_line_id': creditLineId,
        'name': name,
        'amount': amount,
        'every': interval.name,
        'next_date': isoDate(nextDate),
        'anchor_day': anchorDay,
        'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  factory RecurringCharge.fromMap(Map<String, Object?> m) => RecurringCharge(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        creditLineId: m['credit_line_id'] as String?,
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        interval: RecurrenceInterval.fromName(m['every'] as String?),
        nextDate: DateTime.parse(m['next_date'] as String),
        anchorDay: (m['anchor_day'] as num).toInt(),
        active: (m['active'] as num? ?? 1) != 0,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
