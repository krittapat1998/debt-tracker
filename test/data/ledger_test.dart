import 'dart:convert';
import 'dart:io';

import 'package:debt_tracker/data/backup/backup_service.dart';
import 'package:debt_tracker/data/db/app_database.dart';
import 'package:debt_tracker/data/repositories/sqlite_repositories.dart';
import 'package:debt_tracker/data/services/ledger_service.dart';
import 'package:debt_tracker/data/services/settings_service.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
import 'package:debt_tracker/domain/models/recurring_charge.dart';
import 'package:debt_tracker/domain/models/spending.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late LedgerService ledger;
  late SqliteCreditLineRepository lines;
  late SqlitePaymentRepository payments;
  late SqliteInstallmentRepository plans;
  late SqliteSpendingRepository spendings;
  late SqliteRecurringChargeRepository recurring;
  // The account below is set up, balance typed in, on 1 Oct.
  late DateTime now;

  final account = Account(id: 'a', name: 'KTC', type: AccountType.creditCard, createdAt: DateTime(2026));
  CreditLine cardLine({double balance = 10000}) =>
      CreditLine(id: 'l', accountId: 'a', name: 'บัตร', balance: balance, annualRate: 16, creditLimit: 50000);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    now = DateTime(2026, 10, 1, 9);
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    lines = SqliteCreditLineRepository(db);
    payments = SqlitePaymentRepository(db);
    plans = SqliteInstallmentRepository(db);
    spendings = SqliteSpendingRepository(db);
    recurring = SqliteRecurringChargeRepository(db);
    ledger = LedgerService(
      accounts: SqliteAccountRepository(db),
      lines: lines,
      plans: plans,
      payments: payments,
      spendings: spendings,
      recurring: recurring,
      clock: () => now,
    );
    await ledger.saveAccount(account, [cardLine()]);
  });

  tearDown(() => db.close());

  Payment payment(double amount, {String? planId}) => Payment(
        id: 'p${DateTime.now().microsecondsSinceEpoch}',
        accountId: 'a',
        creditLineId: planId == null ? 'l' : null,
        planId: planId,
        date: DateTime(2026, 10, 25),
        amount: amount,
        type: PaymentType.minimum,
        createdAt: now,
      );

  test('revolving payment reduces the sub-limit balance and delete restores it', () async {
    final p = await ledger.recordPayment(payment(3000));
    expect((await lines.getById('l'))!.balance, 7000);
    expect(p.lineBalanceApplied, 3000);

    await ledger.deletePayment(p.id);
    expect((await lines.getById('l'))!.balance, 10000);
    expect(await payments.getAll(), isEmpty);
  });

  test('editing a payment gives back the old amount and takes off the new one', () async {
    Payment edit(Payment p, double amount, {PaymentType type = PaymentType.full}) => Payment(id: p.id, accountId: 'a',
        creditLineId: 'l', date: DateTime(2026, 10, 26), amount: amount, type: type, createdAt: p.createdAt);
    final p = await ledger.recordPayment(payment(3000));
    final edited = await ledger.updatePayment(edit(p, 1200), alreadyInBalance: false);
    expect((await lines.getById('l'))!.balance, 8800);
    expect(edited.lineBalanceApplied, 1200);
    final stored = (await payments.getById(p.id))!;
    expect((stored.amount, stored.type, stored.date), (1200, PaymentType.full, DateTime(2026, 10, 26)));

    // "The bank balance already has it": nothing is taken off any more.
    await ledger.updatePayment(stored, alreadyInBalance: true);
    expect((await lines.getById('l'))!.balance, 10000);
    expect((await payments.getById(p.id))!.lineBalanceApplied, 0);

    // A balance typed in from the bank after the payment is left alone.
    final again = await ledger.updatePayment(stored, alreadyInBalance: false);
    expect((await lines.getById('l'))!.balance, 8800);
    now = now.add(const Duration(days: 1));
    await ledger.setLineBalance('l', 9500);
    await ledger.updatePayment(edit(again, 500), alreadyInBalance: false);
    expect((await lines.getById('l'))!.balance, 9500);
  });

  test('moving a payment onto an installment plan stops it reducing the card balance', () async {
    await ledger.savePlan(InstallmentPlan(id: 'plan', accountId: 'a', name: 'ผ่อนทีวี', principal: 12000, annualRate: 0,
        interestMethod: InterestMethod.reducing, termMonths: 12, startDate: DateTime(2026, 10, 25), createdAt: now));
    final p = await ledger.recordPayment(payment(2000));
    await ledger.updatePayment(Payment(id: p.id, accountId: 'a', planId: 'plan', date: p.date, amount: 2000,
        type: PaymentType.installment, createdAt: p.createdAt), alreadyInBalance: false);
    expect((await lines.getById('l'))!.balance, 10000);
    expect((await payments.getById(p.id))!.planId, 'plan');
  });

  Spending spending(double amount, {String? note}) => Spending(
        id: 's${DateTime.now().microsecondsSinceEpoch}',
        accountId: 'a',
        creditLineId: 'l',
        date: DateTime(2026, 10, 28),
        amount: amount,
        note: note,
        createdAt: now,
      );

  test('spending is kept with its note, added to the balance, and delete takes it off', () async {
    final s = spending(1200, note: 'ค่าอาหาร');
    await ledger.recordSpending(s);
    expect((await lines.getById('l'))!.balance, 11200);
    final saved = (await spendings.getAll()).single;
    expect(saved.note, 'ค่าอาหาร');
    expect(saved.amount, 1200);
    expect(saved.date, DateTime(2026, 10, 28));

    await ledger.deleteSpending(s.id);
    expect((await lines.getById('l'))!.balance, 10000);
    expect(await spendings.getAll(), isEmpty);
  });

  test('deleting spending never takes the balance below zero', () async {
    final s = spending(1200);
    await ledger.recordSpending(s);
    await ledger.saveAccount(account, [cardLine(balance: 500)]);
    // Same moment as the entry, so not "typed in after" it.
    await ledger.deleteSpending(s.id);
    expect((await lines.getById('l'))!.balance, 0);
  });

  group('editing spending', () {
    Future<double> balance([String id = 'l']) async => (await lines.getById(id))!.balance;

    test('moves the balance by the difference', () async {
      final s = await ledger.recordSpending(spending(1200));
      expect(await balance(), 11200);

      final bigger = await ledger.updateSpending(
        Spending(id: s.id, accountId: 'a', creditLineId: 'l', date: s.date, amount: 1500, note: 'ค่าอาหาร',
            createdAt: s.createdAt),
        alreadyInBalance: false,
      );
      expect(await balance(), 11500);
      expect(bigger.lineBalanceApplied, 1500);
      expect((await spendings.getAll()).single.note, 'ค่าอาหาร');

      // Added by mistake to a balance that already had it.
      final fixed = await ledger.updateSpending(bigger, alreadyInBalance: true);
      expect(await balance(), 10000);
      expect(fixed.lineBalanceApplied, 0);
      expect(await spendings.getAll(), hasLength(1));
    });

    test('can move it to another sub-limit', () async {
      await ledger.saveAccount(account, [
        cardLine(),
        const CreditLine(id: 'l2', accountId: 'a', name: 'สินเชื่อ', annualRate: 25),
      ]);
      final s = await ledger.recordSpending(spending(700));
      await ledger.updateSpending(
        Spending(id: s.id, accountId: 'a', creditLineId: 'l2', date: s.date, amount: 700, createdAt: s.createdAt),
        alreadyInBalance: false,
      );
      expect(await balance(), 10000);
      expect(await balance('l2'), 700);
    });

    test('a balance typed in after the entry was recorded stays as typed', () async {
      final s = await ledger.recordSpending(spending(1200));
      final p = await ledger.recordPayment(payment(500));
      now = DateTime(2026, 10, 2, 9);
      await ledger.setLineBalance('l', 13000);

      await ledger.updateSpending(
        Spending(id: s.id, accountId: 'a', creditLineId: 'l', date: s.date, amount: 120, createdAt: s.createdAt),
        alreadyInBalance: false,
      );
      expect(await balance(), 13000);
      await ledger.deleteSpending(s.id);
      await ledger.deletePayment(p.id);
      expect(await balance(), 13000);
    });
  });

  group('balance typed in from the bank', () {
    Spending spentOn(DateTime date, double amount) => Spending(
          id: 's${date.day}-$amount',
          accountId: 'a',
          creditLineId: 'l',
          date: date,
          amount: amount,
          createdAt: now,
        );
    Payment paidOn(DateTime date, double amount) => Payment(
          id: 'p${date.day}-$amount',
          accountId: 'a',
          creditLineId: 'l',
          date: date,
          amount: amount,
          type: PaymentType.other,
          createdAt: now,
        );
    Future<double> balance() async => (await lines.getById('l'))!.balance;

    setUp(() async {
      now = DateTime(2026, 11, 1, 20);
      await ledger.setLineBalance('l', 11500);
    });

    test('remembers the day it was typed in', () async {
      expect((await lines.getById('l'))!.balanceAsOf, DateTime(2026, 11, 1, 20));
    });

    test('older spending and payments are kept in the history without counting twice', () async {
      final s = await ledger.recordSpending(spentOn(DateTime(2026, 10, 28), 1500));
      expect(s.lineBalanceApplied, 0);
      final p = await ledger.recordPayment(paidOn(DateTime(2026, 10, 30), 2000));
      expect(p.lineBalanceApplied, 0);
      expect(await balance(), 11500);
      expect(await spendings.getAll(), hasLength(1));

      // Deleting them leaves the typed-in balance alone too.
      await ledger.deleteSpending(s.id);
      await ledger.deletePayment(p.id);
      expect(await balance(), 11500);
    });

    test('later entries still count', () async {
      await ledger.recordSpending(spentOn(DateTime(2026, 11, 2), 300));
      await ledger.recordPayment(paidOn(DateTime(2026, 11, 3), 800));
      expect(await balance(), 11000);
    });

    test('the same day counts unless the user says the balance has it', () async {
      await ledger.recordSpending(spentOn(DateTime(2026, 11, 1), 200));
      expect(await balance(), 11700);
      await ledger.recordSpending(spentOn(DateTime(2026, 11, 1), 300), alreadyInBalance: true);
      expect(await balance(), 11700);
      // And the user can say an older one is not in it after all.
      await ledger.recordSpending(spentOn(DateTime(2026, 10, 28), 100), alreadyInBalance: false);
      expect(await balance(), 11800);
    });
  });

  test('saving the account stamps only balances that were typed in', () async {
    expect((await lines.getById('l'))!.balanceAsOf, DateTime(2026, 10, 1, 9));

    now = DateTime(2026, 10, 15);
    await ledger.saveAccount(account, [cardLine().copyWith(name: 'วงเงินบัตร')]);
    expect((await lines.getById('l'))!.balanceAsOf, DateTime(2026, 10, 1, 9));

    await ledger.saveAccount(account, [
      cardLine(balance: 9500),
      const CreditLine(id: 'l2', accountId: 'a', name: 'สินเชื่อ', annualRate: 25),
    ]);
    expect((await lines.getById('l'))!.balanceAsOf, DateTime(2026, 10, 15));
    expect((await lines.getById('l2'))!.balanceAsOf, isNull);
  });

  group('recurring charges', () {
    RecurringCharge netflix({DateTime? next, RecurrenceInterval interval = RecurrenceInterval.monthly, bool active = true}) {
      final d = next ?? DateTime(2026, 8, 31);
      return RecurringCharge(
        id: 'r',
        accountId: 'a',
        creditLineId: 'l',
        name: 'Netflix',
        amount: 419,
        interval: interval,
        nextDate: d,
        anchorDay: d.day,
        active: active,
        createdAt: now,
      );
    }

    test('a charge on the 31st falls on the last day of shorter months', () {
      final c = netflix(next: DateTime(2027, 1, 31));
      expect(c.following(DateTime(2027, 1, 31)), DateTime(2027, 2, 28));
      expect(c.following(DateTime(2027, 2, 28)), DateTime(2027, 3, 31));
      expect(netflix(next: DateTime(2026, 11, 1), interval: RecurrenceInterval.yearly).following(DateTime(2026, 11, 1)),
          DateTime(2027, 11, 1));
    });

    test('records every charge that came due, once', () async {
      // Set up the day before its first charge.
      now = DateTime(2026, 8, 30, 9);
      await ledger.saveRecurring(netflix());
      // The app wasn't opened for two months.
      now = DateTime(2026, 11, 1, 8);
      expect(await ledger.recordDueCharges(), 3);
      final recorded = (await spendings.getAll()).reversed.toList();
      expect(recorded.map((s) => s.date), [DateTime(2026, 8, 31), DateTime(2026, 9, 30), DateTime(2026, 10, 31)]);
      expect(recorded.every((s) => s.note == 'Netflix' && s.source == PaymentSource.recurring), isTrue);
      // The balance was typed in on 1 Oct, so only the 31 Oct charge is new.
      expect((await lines.getById('l'))!.balance, 10419);
      expect((await recurring.getAll()).single.nextDate, DateTime(2026, 11, 30));

      expect(await ledger.recordDueCharges(), 0);
      expect(await spendings.getAll(), hasLength(3));
    });

    test('overlapping runs record nothing twice', () async {
      now = DateTime(2026, 8, 30, 9);
      await ledger.saveRecurring(netflix());
      now = DateTime(2026, 11, 1, 8);
      await Future.wait([ledger.recordDueCharges(), ledger.recordDueCharges()]);
      expect(await spendings.getAll(), hasLength(3));
    });

    test('a paused charge records nothing', () async {
      await ledger.saveRecurring(netflix(active: false));
      now = DateTime(2026, 11, 1, 8);
      expect(await ledger.recordDueCharges(), 0);
    });

    test("the bank's SMS for the same charge is not recorded twice", () async {
      now = DateTime(2026, 10, 30, 8);
      await ledger.saveRecurring(netflix(next: DateTime(2026, 10, 31)));
      await ledger.recordSpending(Spending(id: 'sms', accountId: 'a', creditLineId: 'l', date: DateTime(2026, 10, 30),
          amount: 419, source: PaymentSource.sms, createdAt: now));
      now = DateTime(2026, 11, 1, 8);
      expect(await ledger.recordDueCharges(), 0);
      expect((await recurring.getAll()).single.nextDate, DateTime(2026, 11, 30));

      // And the other way round: the SMS comes after the automatic entry.
      now = DateTime(2026, 12, 1, 8);
      await ledger.recordDueCharges();
      expect(await ledger.coveredByRecurring('a', 419, DateTime(2026, 12, 1)), isTrue);
      expect(await ledger.coveredByRecurring('a', 420, DateTime(2026, 12, 1)), isFalse);
    });

    test('a charge the card just took is recorded on saving, once, as the user says about the balance', () async {
      // Netflix was charged yesterday; the balance typed in on 1 Oct does not have it.
      final saved = await ledger.saveRecurring(netflix(next: DateTime(2026, 9, 30)), alreadyInBalance: false);
      // Charged on the 30th, so the next one is on 30 Oct.
      expect(saved.nextDate, DateTime(2026, 10, 30));
      expect((await recurring.getAll()).single.nextDate, DateTime(2026, 10, 30));
      final s = (await spendings.getAll()).single;
      expect((s.date, s.amount, s.note, s.source), (DateTime(2026, 9, 30), 419.0, 'Netflix', PaymentSource.recurring));
      expect((await lines.getById('l'))!.balance, 10419);

      // Saving it again on the same date (an edit) records nothing new.
      await ledger.saveRecurring(netflix(next: DateTime(2026, 9, 30)), alreadyInBalance: false);
      expect(await spendings.getAll(), hasLength(1));
      expect(await ledger.recordDueCharges(), 0);
    });

    test('"the balance already has it" keeps it out of the balance', () async {
      await ledger.saveRecurring(netflix(next: DateTime(2026, 9, 30)), alreadyInBalance: true);
      expect((await spendings.getAll()).single.lineBalanceApplied, 0);
      expect((await lines.getById('l'))!.balance, 10000);
    });

    test('deleting a charge keeps what it recorded', () async {
      await ledger.saveRecurring(netflix(next: DateTime(2026, 10, 1)));
      await ledger.recordDueCharges();
      await ledger.deleteRecurring('r');
      expect(await recurring.getAll(), isEmpty);
      expect(await spendings.getAll(), hasLength(1));
    });
  });

  test('the card color is saved with the account and survives a backup', () async {
    final colored = Account(id: 'a', name: 'KTC', type: AccountType.creditCard, color: 0xFF6A1B9A, createdAt: DateTime(2026));
    await ledger.saveAccount(colored, [cardLine()]);
    expect((await SqliteAccountRepository(db).getById('a'))!.color, 0xFF6A1B9A);

    final backup = BackupService(db);
    final json = await backup.exportJson();
    await ledger.deleteAccount('a');
    await backup.importJson(json);
    expect((await SqliteAccountRepository(db).getById('a'))!.color, 0xFF6A1B9A);
  });

  test('the theme choice is remembered, and anything unknown falls back to the system', () async {
    final settings = SettingsService(SqliteSettingsRepository(db));
    expect(await settings.themeChoice(), ThemeChoice.system);
    await settings.setThemeChoice(ThemeChoice.blue);
    expect(await settings.themeChoice(), ThemeChoice.blue);
    expect(ThemeChoice.fromName('purple'), ThemeChoice.system);
  });

  test('deleting the account deletes its spending', () async {
    await ledger.recordSpending(spending(1200));
    await ledger.deleteAccount('a');
    expect(await spendings.getAll(), isEmpty);
  });

  test('overpaying never pushes the balance below zero, and undo is exact', () async {
    final p = await ledger.recordPayment(payment(15000));
    expect((await lines.getById('l'))!.balance, 0);
    expect(p.lineBalanceApplied, 10000);
    await ledger.deletePayment(p.id);
    expect((await lines.getById('l'))!.balance, 10000);
  });

  test('editing an account keeps its payments and plans (no cascade on update)', () async {
    await ledger.savePlan(InstallmentPlan(
      id: 'plan',
      accountId: 'a',
      creditLineId: 'l',
      name: 'iPhone',
      principal: 30000,
      annualRate: 0,
      interestMethod: InterestMethod.reducing,
      termMonths: 10,
      startDate: DateTime(2026, 11, 1),
      createdAt: DateTime(2026),
    ));
    await ledger.recordPayment(payment(1000));
    await ledger.recordPayment(payment(3000, planId: 'plan'));

    await ledger.saveAccount(
      Account(id: 'a', name: 'KTC Visa', type: AccountType.creditCard, createdAt: DateTime(2026)),
      [cardLine(balance: 9000).copyWith(name: 'วงเงินบัตร')],
    );
    final p = await plans.getById('plan');
    expect(p, isNotNull);
    expect(p!.creditLineId, 'l');
    expect(await payments.getAll(), hasLength(2));
    expect((await payments.getAll()).any((x) => x.planId == 'plan'), isTrue);

    // Re-saving a plan must not detach its payments either.
    await ledger.savePlan(p);
    expect((await payments.getAll()).where((x) => x.planId == 'plan'), hasLength(1));
  });

  test('removing a sub-limit from the account deletes only that sub-limit', () async {
    await ledger.saveAccount(account, [
      cardLine(),
      const CreditLine(id: 'l2', accountId: 'a', name: 'สินเชื่อ', annualRate: 25),
    ]);
    expect(await lines.getAll(), hasLength(2));
    await ledger.saveAccount(account, [cardLine()]);
    expect((await lines.getAll()).map((l) => l.id), ['l']);
  });

  test('statement update', () async {
    await ledger.applyStatement(
      accountId: 'a',
      statementBalance: 15230.5,
      minimumPayment: 1523.05,
      statementDate: DateTime(2026, 10, 10),
      dueDate: DateTime(2026, 10, 25),
    );
    final a = (await SqliteAccountRepository(db).getById('a'))!;
    expect(a.statementBalance, 15230.5);
    expect(a.minimumPayment, 1523.05);
    expect(a.statementDueDate, DateTime(2026, 10, 25));
  });

  group('card-billed plans', () {
    final cashCard = Account(id: 'c', name: 'First Choice', type: AccountType.cashCard, billingDay: 20, createdAt: DateTime(2026));
    // 6 installments of 1,785; the card shows up to 3/6 on 2 Nov.
    InstallmentPlan loan({int posted = 3}) => InstallmentPlan(
          id: 'loan',
          accountId: 'c',
          creditLineId: 'cl',
          name: 'เงินยืม',
          principal: 10000,
          annualRate: 25,
          interestMethod: InterestMethod.reducing,
          termMonths: 6,
          monthlyPaymentOverride: 1785,
          startDate: InstallmentPlan.firstCutoff(billingDay: 20, posted: posted, today: now),
          includedInStatement: true,
          paidBeforeTracking: posted,
          anchorDay: 20,
          postedThrough: posted,
          createdAt: now,
        );

    setUp(() async {
      now = DateTime(2026, 11, 2, 9);
      await ledger.saveAccount(cashCard, [
        const CreditLine(id: 'cl', accountId: 'c', name: 'วงเงินกดเงินสด', balance: 1785, annualRate: 25, creditLimit: 50000),
      ]);
    });

    test('the first cutoff counts back from the next one, keeping a day-31 cutoff', () {
      expect(InstallmentPlan.firstCutoff(billingDay: 20, posted: 3, today: DateTime(2026, 11, 2)), DateTime(2026, 8, 20));
      // On the cutoff day the card already shows that day's installment.
      expect(InstallmentPlan.firstCutoff(billingDay: 20, posted: 0, today: DateTime(2026, 11, 20)), DateTime(2026, 12, 20));
      final p = loan().copyWith(
          startDate: InstallmentPlan.firstCutoff(billingDay: 31, posted: 3, today: DateTime(2026, 11, 2)), anchorDay: 31);
      expect(p.startDate, DateTime(2026, 8, 31));
      expect([p.dueDateOf(4), p.dueDateOf(5), p.dueDateOf(6)],
          [DateTime(2026, 11, 30), DateTime(2026, 12, 31), DateTime(2027, 1, 31)]);
    });

    test('each installment goes on the card at its cutoff, catching up', () async {
      await ledger.savePlan(loan());
      expect(await ledger.postDueInstallments(), 0);
      expect((await lines.getById('cl'))!.balance, 1785);

      now = DateTime(2026, 11, 20, 8);
      expect(await ledger.postDueInstallments(), 1);
      expect((await lines.getById('cl'))!.balance, 3570);
      final s = (await spendings.getAll()).single;
      expect((s.date, s.amount, s.note, s.source), (DateTime(2026, 11, 20), 1785.0, 'เงินยืม งวด 4/6', PaymentSource.installment));
      expect((await plans.getById('loan'))!.postedThrough, 4);
      expect(await ledger.postDueInstallments(), 0);

      // Not opened over two cutoffs.
      now = DateTime(2027, 1, 25);
      expect(await ledger.postDueInstallments(), 2);
      expect([for (final s in await spendings.getAll()) s.note]..sort(),
          ['เงินยืม งวด 4/6', 'เงินยืม งวด 5/6', 'เงินยืม งวด 6/6']);
      expect((await plans.getById('loan'))!.postedThrough, 6);
    });

    test('a balance typed in on or after the cutoff already has the installment', () async {
      await ledger.savePlan(loan());
      now = DateTime(2026, 11, 20, 18);
      await ledger.setLineBalance('cl', 3570);
      expect(await ledger.postDueInstallments(), 1);
      expect((await lines.getById('cl'))!.balance, 3570);
      expect((await spendings.getAll()).single.lineBalanceApplied, 0);
    });

    test('a plan from an older version moves to cutoffs and starts from what is on the card', () async {
      // Saved with due dates on the 5th: 5 Sep, 5 Oct, 5 Nov, ...
      await ledger.savePlan(InstallmentPlan(
        id: 'old',
        accountId: 'c',
        creditLineId: 'cl',
        name: 'ผ่อนทีวี',
        principal: 6000,
        annualRate: 0,
        interestMethod: InterestMethod.reducing,
        termMonths: 6,
        startDate: DateTime(2026, 9, 5),
        includedInStatement: true,
        createdAt: now,
      ));
      expect(await ledger.postDueInstallments(), 0);
      final p = (await plans.getById('old'))!;
      expect((p.startDate, p.anchorDay), (DateTime(2026, 8, 20), 20));
      // Cutoffs 20 Aug, 20 Sep and 20 Oct have passed; the typed-in balance has them.
      expect(p.postedThrough, 3);
      expect((await lines.getById('cl'))!.balance, 1785);
      expect(await spendings.getAll(), isEmpty);
    });

    test('changing the cutoff day moves card-billed plans', () async {
      await ledger.savePlan(loan());
      await ledger.setBillingDay('c', 25);
      var p = (await plans.getById('loan'))!;
      expect((p.startDate, p.anchorDay, p.dueDateOf(4)), (DateTime(2026, 8, 25), 25, DateTime(2026, 11, 25)));

      await ledger.saveAccount(cashCard.withBillingDay(10), [(await lines.getById('cl'))!]);
      p = (await plans.getById('loan'))!;
      expect((p.startDate, p.anchorDay), (DateTime(2026, 8, 10), 10));
    });
  });

  test('opening a version 1 database adds the spendings table and keeps the data', () async {
    final dir = Directory.systemTemp.createTempSync('debt_db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
            await db.execute('CREATE TABLE credit_lines (id TEXT PRIMARY KEY)');
            await db.execute('CREATE TABLE installment_plans (id TEXT PRIMARY KEY)');
          },
        ));
    await v1.insert('accounts', {'id': 'old', 'name': 'KTC'});
    await v1.close();

    final upgraded = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(upgraded.close);
    expect(await upgraded.db.getVersion(), 8);
    expect(await upgraded.db.query('accounts'), [
      {'id': 'old', 'name': 'KTC', 'color': null},
    ]);
    expect(await upgraded.db.query('spendings'), isEmpty);
    expect(await upgraded.db.query('recurring_charges'), isEmpty);
  });

  test('a database an older build lowered the version of opens again without re-adding columns', () async {
    final dir = Directory.systemTemp.createTempSync('debt_db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/downgraded.db';
    final current = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    // An older TestFlight build opened it: newer columns stay, the version drops.
    await current.db.setVersion(6);
    await current.close();

    final reopened = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(reopened.close);
    expect(await reopened.db.getVersion(), 8);
    final columns = [for (final c in await reopened.db.rawQuery('PRAGMA table_info(installment_plans)')) c['name']];
    expect(columns.where((c) => c == 'rate_steps'), hasLength(1));
    expect(columns, containsAll(['disbursed_on', 'first_payment_on']));
  });

  test('opening a version 2 database keeps spending as added to the balance', () async {
    final dir = Directory.systemTemp.createTempSync('debt_db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v2.db';
    final v2 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
            await db.execute('CREATE TABLE credit_lines (id TEXT PRIMARY KEY, account_id TEXT, name TEXT, '
                'credit_limit REAL, balance REAL, annual_rate REAL, interest_method TEXT, sort_order INTEGER)');
            await db.execute('CREATE TABLE spendings (id TEXT PRIMARY KEY, account_id TEXT, credit_line_id TEXT, '
                'date TEXT, amount REAL, note TEXT, source TEXT, created_at TEXT)');
            await db.execute('CREATE TABLE installment_plans (id TEXT PRIMARY KEY)');
          },
        ));
    await v2.insert('credit_lines', {'id': 'l', 'account_id': 'a', 'name': 'บัตร', 'balance': 5000, 'annual_rate': 16,
        'interest_method': 'reducing'});
    await v2.insert('spendings', {'id': 's', 'account_id': 'a', 'credit_line_id': 'l', 'date': '2026-10-28',
        'amount': 1200, 'source': 'manual', 'created_at': '2026-10-28T12:00:00.000'});
    await v2.close();

    final upgraded = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(upgraded.close);
    expect(await upgraded.db.getVersion(), 8);
    expect((await SqliteSpendingRepository(upgraded).getAll()).single.lineBalanceApplied, 1200);
    expect((await SqliteCreditLineRepository(upgraded).getAll()).single.balanceAsOf, isNull);
  });

  group('backup', () {
    test('plain JSON round-trip', () async {
      await ledger.saveRecurring(RecurringCharge(id: 'r', accountId: 'a', creditLineId: 'l', name: 'Netflix', amount: 419,
          nextDate: DateTime(2026, 11, 15), anchorDay: 15, createdAt: now));
      await ledger.recordPayment(payment(1000));
      await ledger.recordSpending(spending(300, note: 'ค่ากาแฟ'));
      final backup = BackupService(db);
      final json = await backup.exportJson();
      await ledger.deleteAccount('a');
      final counts = await backup.importJson(json);
      expect(counts['accounts'], 1);
      expect(counts['payments'], 1);
      expect(counts['spendings'], 1);
      expect(counts['recurring_charges'], 1);
      expect((await recurring.getAll()).single.name, 'Netflix');
      expect((await lines.getById('l'))!.balance, 9300);
      expect((await spendings.getAll()).single.note, 'ค่ากาแฟ');
    });

    test('a backup from before version 3 restores spending as added to the balance', () async {
      await ledger.recordSpending(spending(300));
      final backup = BackupService(db);
      final json = jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      for (final r in [...data['credit_lines'] as List, ...data['spendings'] as List]) {
        (r as Map)
          ..remove('balance_as_of')
          ..remove('line_balance_applied');
      }
      await backup.importJson(jsonEncode(json));
      final restored = (await spendings.getAll()).single;
      expect(restored.lineBalanceApplied, 300);
      await ledger.deleteSpending(restored.id);
      expect((await lines.getById('l'))!.balance, 10000);
    });

    test('encrypted backup needs the right password', () async {
      final backup = BackupService(db);
      final json = await backup.exportJson(password: 'correct horse');
      expect(BackupService.isEncrypted(json), isTrue);
      expect(json.contains('KTC'), isFalse);
      await expectLater(backup.importJson(json, password: 'wrong'), throwsA(isA<BackupException>()));
      final counts = await backup.importJson(json, password: 'correct horse');
      expect(counts['accounts'], 1);
    });

    test('CSV export has a UTF-8 BOM and Thai labels', () async {
      await ledger.recordPayment(payment(1000));
      await ledger.recordSpending(spending(300, note: 'ค่ากาแฟ'));
      final files = await BackupService(db).exportCsv();
      expect(files.keys, containsAll(['accounts.csv', 'payments.csv', 'spendings.csv']));
      expect(files['payments.csv']!.startsWith('﻿'), isTrue);
      expect(files['payments.csv'], contains('จ่ายขั้นต่ำ'));
      expect(files['spendings.csv'], contains('ค่ากาแฟ'));
      expect(files['spendings.csv'], contains(',บัตร,'));
    });
  });
}
