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

  CreditLine copyWith({
    String? name,
    double? creditLimit,
    double? balance,
    double? annualRate,
    InterestMethod? interestMethod,
    int? sortOrder,
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
      );
}
