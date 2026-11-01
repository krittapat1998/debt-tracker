import '../../core/date_utils.dart';
import 'enums.dart';

/// A sub-limit (วงเงินย่อย) inside an account, with its own rate and balance.
/// [balance] is the revolving outstanding amount and excludes installment
/// plans, which track their own remaining principal.
class CreditLine {
  const CreditLine({
    required this.id,
    required this.accountId,
    required this.name,
    this.creditLimit = 0,
    this.balance = 0,
    required this.annualRate,
    this.interestMethod = InterestMethod.reducing,
    this.sortOrder = 0,
    this.balanceAsOf,
  });

  final String id;
  final String accountId;
  final String name;
  final double creditLimit;
  final double balance;

  /// Annual interest rate in percent (e.g. 16 = 16% p.a.).
  final double annualRate;
  final InterestMethod interestMethod;
  final int sortOrder;

  /// When [balance] was last typed in to match the bank. Spending and
  /// payments dated before that day are already counted in [balance].
  final DateTime? balanceAsOf;

  /// Whether something dated [d] is already in [balance].
  bool alreadyCounts(DateTime d) => balanceAsOf != null && dateOnly(d).isBefore(dateOnly(balanceAsOf!));

  /// Whether [d] is on or before the day of [balanceAsOf], so the typed-in
  /// balance may already include it. The same day can go either way.
  bool mayCount(DateTime d) => balanceAsOf != null && !dateOnly(d).isAfter(dateOnly(balanceAsOf!));

  /// Whether the balance was typed in after [t] (an entry's createdAt): the
  /// bank figure replaced whatever that entry did, so editing or deleting
  /// the entry leaves the balance alone.
  bool typedInAfter(DateTime t) => balanceAsOf != null && balanceAsOf!.isAfter(t);

  CreditLine copyWith({
    String? name,
    double? creditLimit,
    double? balance,
    double? annualRate,
    InterestMethod? interestMethod,
    int? sortOrder,
    DateTime? balanceAsOf,
  }) {
    return CreditLine(
      id: id,
      accountId: accountId,
      name: name ?? this.name,
      creditLimit: creditLimit ?? this.creditLimit,
      balance: balance ?? this.balance,
      annualRate: annualRate ?? this.annualRate,
      interestMethod: interestMethod ?? this.interestMethod,
      sortOrder: sortOrder ?? this.sortOrder,
      balanceAsOf: balanceAsOf ?? this.balanceAsOf,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'name': name,
        'credit_limit': creditLimit,
        'balance': balance,
        'annual_rate': annualRate,
        'interest_method': interestMethod.name,
        'sort_order': sortOrder,
        'balance_as_of': balanceAsOf?.toIso8601String(),
      };

  factory CreditLine.fromMap(Map<String, Object?> m) => CreditLine(
        id: m['id'] as String,
        accountId: m['account_id'] as String,
        name: m['name'] as String,
        creditLimit: (m['credit_limit'] as num?)?.toDouble() ?? 0,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        annualRate: (m['annual_rate'] as num?)?.toDouble() ?? 0,
        interestMethod: InterestMethod.fromName(m['interest_method'] as String?),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        balanceAsOf: parseIsoDate(m['balance_as_of']),
      );
}
