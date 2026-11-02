import '../../domain/models/account.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/installment_plan.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/recurring_charge.dart';
import '../../domain/models/spending.dart';

/// Storage-agnostic contracts. The UI and services only depend on these, so
/// a different store (or a synced one) can be swapped in later.
abstract interface class AccountRepository {
  Future<List<Account>> getAll();
  Future<Account?> getById(String id);

  /// Saves the account together with its full list of sub-limits
  /// (sub-limits missing from [lines] are removed).
  Future<void> save(Account account, List<CreditLine> lines);
  Future<void> update(Account account);
  Future<void> delete(String id);
}

abstract interface class CreditLineRepository {
  Future<List<CreditLine>> getAll();
  Future<CreditLine?> getById(String id);
  Future<void> update(CreditLine line);
}

abstract interface class InstallmentRepository {
  Future<List<InstallmentPlan>> getAll();
  Future<InstallmentPlan?> getById(String id);
  Future<void> save(InstallmentPlan plan);
  Future<void> delete(String id);
}

abstract interface class PaymentRepository {
  Future<List<Payment>> getAll();
  Future<Payment?> getById(String id);
  Future<void> insert(Payment payment);
  Future<void> update(Payment payment);
  Future<void> delete(String id);
}

abstract interface class SpendingRepository {
  Future<List<Spending>> getAll();
  Future<Spending?> getById(String id);
  Future<void> insert(Spending spending);
  Future<void> update(Spending spending);
  Future<void> delete(String id);
}

abstract interface class RecurringChargeRepository {
  Future<List<RecurringCharge>> getAll();
  Future<void> save(RecurringCharge charge);
  Future<void> delete(String id);
}

abstract interface class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String? value);
}
