import 'dart:io';

import 'package:debt_tracker/data/backup/backup_service.dart';
import 'package:debt_tracker/data/db/app_database.dart';
import 'package:debt_tracker/data/repositories/sqlite_repositories.dart';
import 'package:debt_tracker/data/services/ledger_service.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
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

  final account = Account(id: 'a', name: 'KTC', type: AccountType.creditCard, createdAt: DateTime(2026));
  CreditLine cardLine({double balance = 10000}) =>
      CreditLine(id: 'l', accountId: 'a', name: 'บัตร', balance: balance, annualRate: 16, creditLimit: 50000);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    lines = SqliteCreditLineRepository(db);
    payments = SqlitePaymentRepository(db);
    plans = SqliteInstallmentRepository(db);
    spendings = SqliteSpendingRepository(db);
    ledger = LedgerService(
      accounts: SqliteAccountRepository(db),
      lines: lines,
      plans: plans,
      payments: payments,
      spendings: spendings,
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
        createdAt: DateTime.now(),
      );

  test('revolving payment reduces the sub-limit balance and delete restores it', () async {
    final p = await ledger.recordPayment(payment(3000));
    expect((await lines.getById('l'))!.balance, 7000);
    expect(p.lineBalanceApplied, 3000);

    await ledger.deletePayment(p.id);
    expect((await lines.getById('l'))!.balance, 10000);
    expect(await payments.getAll(), isEmpty);
  });

  Spending spending(double amount, {String? note}) => Spending(
        id: 's${DateTime.now().microsecondsSinceEpoch}',
        accountId: 'a',
        creditLineId: 'l',
        date: DateTime(2026, 10, 28),
        amount: amount,
        note: note,
        createdAt: DateTime.now(),
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

  test('deleting spending after the balance was corrected never goes below zero', () async {
    final s = spending(1200);
    await ledger.recordSpending(s);
    await ledger.setLineBalance('l', 500);
    await ledger.deleteSpending(s.id);
    expect((await lines.getById('l'))!.balance, 0);
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

  test('opening a version 1 database adds the spendings table and keeps the data', () async {
    final dir = Directory.systemTemp.createTempSync('debt_db');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/v1.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute('CREATE TABLE accounts (id TEXT PRIMARY KEY, name TEXT NOT NULL)'),
        ));
    await v1.insert('accounts', {'id': 'old', 'name': 'KTC'});
    await v1.close();

    final upgraded = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    addTearDown(upgraded.close);
    expect(await upgraded.db.getVersion(), 2);
    expect(await upgraded.db.query('accounts'), hasLength(1));
    expect(await upgraded.db.query('spendings'), isEmpty);
  });

  group('backup', () {
    test('plain JSON round-trip', () async {
      await ledger.recordPayment(payment(1000));
      await ledger.recordSpending(spending(300, note: 'ค่ากาแฟ'));
      final backup = BackupService(db);
      final json = await backup.exportJson();
      await ledger.deleteAccount('a');
      final counts = await backup.importJson(json);
      expect(counts['accounts'], 1);
      expect(counts['payments'], 1);
      expect(counts['spendings'], 1);
      expect((await lines.getById('l'))!.balance, 9300);
      expect((await spendings.getAll()).single.note, 'ค่ากาแฟ');
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
