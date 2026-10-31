import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../domain/models/account.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/installment_plan.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/spending.dart';
import '../repositories/repositories.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Write-side use cases. Keeps balance bookkeeping in one place so every
/// entry point (form, SMS import, future email import) behaves the same.
class LedgerService {
  LedgerService({
    required this.accounts,
    required this.lines,
    required this.plans,
    required this.payments,
    required this.spendings,
  });

  final AccountRepository accounts;
  final CreditLineRepository lines;
  final InstallmentRepository plans;
  final PaymentRepository payments;
  final SpendingRepository spendings;

  Future<void> saveAccount(Account account, List<CreditLine> creditLines) =>
      accounts.save(account, creditLines);

  Future<void> deleteAccount(String id) => accounts.delete(id);

  Future<void> savePlan(InstallmentPlan plan) => plans.save(plan);

  Future<void> deletePlan(String id) => plans.delete(id);

  /// Records a payment. Revolving payments reduce the sub-limit balance
  /// right away; plan payments are picked up by the installment replay.
  Future<Payment> recordPayment(Payment draft) async {
    var applied = 0.0;
    if (draft.planId == null && draft.creditLineId != null) {
      final line = await lines.getById(draft.creditLineId!);
      if (line != null) {
        applied = math.min(draft.amount, math.max(0.0, line.balance));
        await lines.update(line.copyWith(balance: line.balance - applied));
      }
    }
    final payment = draft.copyWith(lineBalanceApplied: applied);
    await payments.insert(payment);
    return payment;
  }

  /// Deletes a payment and restores exactly what it took off the balance.
  Future<void> deletePayment(String id) async {
    final p = await payments.getById(id);
    if (p == null) return;
    if (p.lineBalanceApplied > 0 && p.creditLineId != null) {
      final line = await lines.getById(p.creditLineId!);
      if (line != null) {
        await lines.update(line.copyWith(balance: line.balance + p.lineBalanceApplied));
      }
    }
    await payments.delete(id);
  }

  /// Stores a new statement (ยอดเรียกเก็บ/ขั้นต่ำ/วันครบกำหนด).
  Future<void> applyStatement({
    required String accountId,
    required double statementBalance,
    required double minimumPayment,
    required DateTime statementDate,
    DateTime? dueDate,
  }) async {
    final a = await accounts.getById(accountId);
    if (a == null) return;
    await accounts.update(a.withStatement(
      statementBalance: statementBalance,
      minimumPayment: minimumPayment,
      statementDate: statementDate,
      statementDueDate: dueDate,
    ));
  }

  Future<void> setLineBalance(String lineId, double balance) async {
    final line = await lines.getById(lineId);
    if (line == null) return;
    await lines.update(line.copyWith(balance: math.max(0, balance)));
  }

  /// New spending on a card (typed in, or from a "ใช้จ่ายบัตร" SMS): kept
  /// in the history and added to the sub-limit balance.
  Future<void> recordSpending(Spending spending) async {
    if (spending.creditLineId != null) {
      final line = await lines.getById(spending.creditLineId!);
      if (line != null) await lines.update(line.copyWith(balance: line.balance + spending.amount));
    }
    await spendings.insert(spending);
  }

  /// Deletes spending and takes it back off the balance (never below zero,
  /// in case the balance was corrected by hand since).
  Future<void> deleteSpending(String id) async {
    final s = await spendings.getById(id);
    if (s == null) return;
    if (s.creditLineId != null) {
      final line = await lines.getById(s.creditLineId!);
      if (line != null) await lines.update(line.copyWith(balance: math.max(0, line.balance - s.amount)));
    }
    await spendings.delete(id);
  }
}
