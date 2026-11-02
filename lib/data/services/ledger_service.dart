import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../core/date_utils.dart';

import '../../domain/finance/installment_engine.dart';
import '../../domain/models/account.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/installment_plan.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/recurring_charge.dart';
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
    required this.recurring,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final AccountRepository accounts;
  final CreditLineRepository lines;
  final InstallmentRepository plans;
  final PaymentRepository payments;
  final SpendingRepository spendings;
  final RecurringChargeRepository recurring;
  final DateTime Function() _now;

  /// Saves the account. A sub-limit whose balance was typed in (a new one
  /// with a balance, or a changed one) now matches the bank as of now.
  Future<void> saveAccount(Account account, List<CreditLine> creditLines) async {
    final stamped = <CreditLine>[];
    for (final l in creditLines) {
      final old = await lines.getById(l.id);
      final typedIn = old == null ? l.balance > 0 : (old.balance - l.balance).abs() >= 0.005;
      stamped.add(l.copyWith(balanceAsOf: typedIn ? _now() : old?.balanceAsOf));
    }
    final before = await accounts.getById(account.id);
    await accounts.save(account, stamped);
    await _moveCutoffs(account, before?.billingDay);
  }

  /// Sets the card's cutoff day (asked for by the plan form when missing).
  Future<void> setBillingDay(String accountId, int day) async {
    final a = await accounts.getById(accountId);
    if (a == null || a.billingDay == day) return;
    final updated = a.withBillingDay(day);
    await accounts.update(updated);
    await _moveCutoffs(updated, a.billingDay);
  }

  /// Card-billed plans follow the card's cutoff day when it changes.
  Future<void> _moveCutoffs(Account account, int? oldDay) async {
    final day = account.billingDay;
    if (day == null || day == oldDay) return;
    for (final p in await plans.getAll()) {
      if (p.accountId != account.id || !p.includedInStatement || p.anchorDay == null) continue;
      await plans.save(p.copyWith(startDate: clampedDate(p.startDate.year, p.startDate.month, day), anchorDay: day));
    }
  }

  Future<void> deleteAccount(String id) => accounts.delete(id);

  Future<void> savePlan(InstallmentPlan plan) => plans.save(plan);

  Future<void> deletePlan(String id) => plans.delete(id);

  /// Records a payment. Revolving payments reduce the sub-limit balance
  /// right away, unless the balance was typed in from the bank after the
  /// payment date and so already has it ([alreadyInBalance] overrides that
  /// guess). Plan payments are picked up by the installment replay.
  Future<Payment> recordPayment(Payment draft, {bool? alreadyInBalance}) async {
    final payment = await _applyPayment(draft, (line) => alreadyInBalance ?? line.alreadyCounts(draft.date));
    await payments.insert(payment);
    return payment;
  }

  /// Corrects a payment (date, amount, type, target, or whether the
  /// balance already had it): gives back what the old one took off and
  /// applies the new one. A balance typed in from the bank after the
  /// payment was recorded is left alone.
  Future<Payment> updatePayment(Payment payment, {required bool alreadyInBalance}) async {
    final old = await payments.getById(payment.id);
    if (old != null) await _giveBackPayment(old);
    final since = old?.createdAt ?? payment.createdAt;
    final saved = await _applyPayment(payment, (line) => alreadyInBalance || line.typedInAfter(since));
    await payments.update(saved);
    return saved;
  }

  /// Deletes a payment and restores exactly what it took off the balance,
  /// unless the balance was typed in from the bank after it was recorded.
  Future<void> deletePayment(String id) async {
    final p = await payments.getById(id);
    if (p == null) return;
    await _giveBackPayment(p);
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

  /// Sets the balance from the bank app; it now counts everything up to now.
  Future<void> setLineBalance(String lineId, double balance) async {
    final line = await lines.getById(lineId);
    if (line == null) return;
    await lines.update(line.copyWith(balance: math.max(0, balance), balanceAsOf: _now()));
  }

  /// New spending on a card (typed in, or from a "ใช้จ่ายบัตร" SMS): kept
  /// in the history and added to the sub-limit balance, unless the balance
  /// was typed in from the bank after it happened and so already has it
  /// ([alreadyInBalance] overrides that guess).
  Future<Spending> recordSpending(Spending spending, {bool? alreadyInBalance}) async {
    final saved = await _applySpending(spending, (line) => alreadyInBalance ?? line.alreadyCounts(spending.date));
    await spendings.insert(saved);
    return saved;
  }

  /// Corrects a spending entry (amount, date, note, sub-limit, or whether
  /// the balance already had it): takes back what the old entry added and
  /// applies the new one. A balance typed in from the bank after the entry
  /// was recorded is left alone.
  Future<Spending> updateSpending(Spending spending, {required bool alreadyInBalance}) async {
    final old = await spendings.getById(spending.id);
    if (old != null) await _takeBackSpending(old);
    final since = old?.createdAt ?? spending.createdAt;
    final saved = await _applySpending(spending, (line) => alreadyInBalance || line.typedInAfter(since));
    await spendings.update(saved);
    return saved;
  }

  /// Deletes spending and takes off what it added (never below zero),
  /// unless the balance was typed in from the bank after it was recorded.
  Future<void> deleteSpending(String id) async {
    final s = await spendings.getById(id);
    if (s == null) return;
    await _takeBackSpending(s);
    await spendings.delete(id);
  }

  Future<void> saveRecurring(RecurringCharge charge) => recurring.save(charge);

  /// Stops a recurring charge; what it already recorded stays in the history.
  Future<void> deleteRecurring(String id) => recurring.delete(id);

  Future<int>? _posting;

  /// Puts each installment of a card-billed plan on its sub-limit balance on
  /// the cutoff the bank does (kept in the history as spending), catching
  /// up on days the app wasn't opened. Returns how many were put on.
  /// Overlapping calls share one run so nothing is put on twice.
  Future<int> postDueInstallments() => _posting ??= _postDueInstallments().whenComplete(() => _posting = null);

  Future<int> _postDueInstallments() async {
    final today = dateOnly(_now());
    final cardPlans = (await plans.getAll()).where((p) => p.includedInStatement).toList();
    if (cardPlans.isEmpty) return 0;
    final allPayments = await payments.getAll();
    var count = 0;
    for (final plan in cardPlans) {
      if (plan.postedThrough == null) {
        await _startPosting(plan, allPayments, today);
        continue;
      }
      final state = InstallmentEngine.replay(plan, allPayments, asOf: today);
      final total = state.paidInstallments + state.remainingInstallments;
      final line = plan.creditLineId == null ? null : await lines.getById(plan.creditLineId!);
      var posted = plan.postedThrough!;
      for (final r in state.paidRows.skip(posted)) {
        if (line != null) {
          await recordSpending(
            Spending(
              id: newId(),
              accountId: plan.accountId,
              creditLineId: line.id,
              date: r.dueDate!,
              amount: r.payment,
              note: '${plan.name} งวด ${r.number}/$total',
              source: PaymentSource.installment,
              createdAt: _now(),
            ),
            // A balance typed in from the bank on or after the cutoff has it.
            alreadyInBalance: line.mayCount(r.dueDate!),
          );
          count++;
        }
        posted = r.number;
      }
      if (posted != plan.postedThrough) await plans.save(plan.copyWith(postedThrough: posted));
    }
    return count;
  }

  /// A card-billed plan saved by an older version, which advanced it on due
  /// dates: moves it to the cutoff before each one, when the bank puts it on
  /// the card, and counts what is on the card by now as already in the
  /// balance typed in from the bank.
  Future<void> _startPosting(InstallmentPlan plan, List<Payment> allPayments, DateTime today) async {
    var p = plan;
    final day = (await accounts.getById(plan.accountId))?.billingDay;
    if (day != null) {
      final cutoff = previousOccurrenceOfDay(day, p.startDate.subtract(const Duration(days: 1)));
      p = p.copyWith(startDate: cutoff, anchorDay: day);
    }
    final posted = InstallmentEngine.replay(p, allPayments, asOf: today).paidInstallments;
    await plans.save(p.copyWith(postedThrough: posted));
  }

  Future<int>? _recording;

  /// Records every recurring charge that has come due as spending, catching
  /// up on days the app wasn't opened. Returns how many were recorded.
  /// Overlapping calls share one run so nothing is recorded twice.
  Future<int> recordDueCharges() => _recording ??= _recordDueCharges().whenComplete(() => _recording = null);

  Future<int> _recordDueCharges() async {
    final today = dateOnly(_now());
    var count = 0;
    for (var c in await recurring.getAll()) {
      // Bounded in case of a corrupt date far in the past.
      for (var i = 0; c.active && !c.nextDate.isAfter(today) && i < 400; i++) {
        // The bank's own SMS for this charge may have been imported already.
        if (!await _hasNearby(c.accountId, c.amount, c.nextDate, const {PaymentSource.sms, PaymentSource.email})) {
          await recordSpending(Spending(
            id: newId(),
            accountId: c.accountId,
            creditLineId: c.creditLineId,
            date: c.nextDate,
            amount: c.amount,
            note: c.name,
            source: PaymentSource.recurring,
            createdAt: _now(),
          ));
          count++;
        }
        c = c.copyWith(nextDate: c.following(c.nextDate));
        await recurring.save(c);
      }
    }
    return count;
  }

  /// Whether a recurring charge already recorded this spending (same card
  /// and amount within 3 days), e.g. when the bank's SMS for it comes in.
  Future<bool> coveredByRecurring(String accountId, double amount, DateTime date) =>
      _hasNearby(accountId, amount, date, const {PaymentSource.recurring});

  /// Spending from [sources] on the same card, same amount, within 3 days.
  /// Typed-in entries never match: they may be a separate purchase.
  Future<bool> _hasNearby(String accountId, double amount, DateTime date, Set<PaymentSource> sources) async =>
      (await spendings.getAll()).any((s) =>
          s.accountId == accountId &&
          sources.contains(s.source) &&
          (s.amount - amount).abs() < 0.005 &&
          daysBetween(s.date, date).abs() <= 3);

  /// Adds [spending] to its sub-limit unless [skip] says the balance has it.
  Future<Spending> _applySpending(Spending spending, bool Function(CreditLine line) skip) async {
    var applied = 0.0;
    if (spending.creditLineId != null) {
      final line = await lines.getById(spending.creditLineId!);
      if (line != null && !skip(line)) {
        applied = spending.amount;
        await lines.update(line.copyWith(balance: line.balance + applied));
      }
    }
    return spending.copyWith(lineBalanceApplied: applied);
  }

  /// Takes a revolving [payment] off its sub-limit unless [skip] says the
  /// balance has it. Plan payments only feed the installment replay.
  Future<Payment> _applyPayment(Payment payment, bool Function(CreditLine line) skip) async {
    var applied = 0.0;
    if (payment.planId == null && payment.creditLineId != null) {
      final line = await lines.getById(payment.creditLineId!);
      if (line != null && !skip(line)) {
        applied = math.min(payment.amount, math.max(0.0, line.balance));
        await lines.update(line.copyWith(balance: line.balance - applied));
      }
    }
    return payment.copyWith(lineBalanceApplied: applied);
  }

  Future<void> _giveBackPayment(Payment p) async {
    if (p.lineBalanceApplied <= 0 || p.creditLineId == null) return;
    final line = await lines.getById(p.creditLineId!);
    if (line == null || line.typedInAfter(p.createdAt)) return;
    await lines.update(line.copyWith(balance: line.balance + p.lineBalanceApplied));
  }

  Future<void> _takeBackSpending(Spending s) async {
    if (s.lineBalanceApplied <= 0 || s.creditLineId == null) return;
    final line = await lines.getById(s.creditLineId!);
    if (line == null || line.typedInAfter(s.createdAt)) return;
    await lines.update(line.copyWith(balance: math.max(0, line.balance - s.lineBalanceApplied)));
  }
}
