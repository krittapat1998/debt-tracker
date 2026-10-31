import 'package:sqflite/sqflite.dart';

import '../../domain/models/account.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/installment_plan.dart';
import '../../domain/models/payment.dart';
import '../db/app_database.dart';
import 'repositories.dart';

/// INSERT OR REPLACE deletes the old row first, which would fire the
/// ON DELETE CASCADE / SET NULL foreign keys and wipe child rows, so rows
/// that other tables reference are upserted with UPDATE-then-INSERT.
Future<void> _upsert(DatabaseExecutor db, String table, Map<String, Object?> row) async {
  final id = row['id'];
  final changed = await db.update(table, row, where: 'id = ?', whereArgs: [id]);
  if (changed == 0) await db.insert(table, row);
}

class SqliteAccountRepository implements AccountRepository {
  SqliteAccountRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Account>> getAll() async {
    final rows = await _db.db.query('accounts', orderBy: 'created_at');
    return rows.map(Account.fromMap).toList();
  }

  @override
  Future<Account?> getById(String id) async {
    final rows = await _db.db.query('accounts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Account.fromMap(rows.first);
  }

  @override
  Future<void> save(Account account, List<CreditLine> lines) async {
    await _db.db.transaction((txn) async {
      await _upsert(txn, 'accounts', account.toMap());
      final keep = lines.map((l) => l.id).toList();
      await txn.delete(
        'credit_lines',
        where: keep.isEmpty
            ? 'account_id = ?'
            : 'account_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
        whereArgs: [account.id, ...keep],
      );
      for (final l in lines) {
        await _upsert(txn, 'credit_lines', l.toMap());
      }
    });
  }

  @override
  Future<void> update(Account account) =>
      _db.db.update('accounts', account.toMap(), where: 'id = ?', whereArgs: [account.id]);

  @override
  Future<void> delete(String id) =>
      _db.db.delete('accounts', where: 'id = ?', whereArgs: [id]);
}

class SqliteCreditLineRepository implements CreditLineRepository {
  SqliteCreditLineRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<CreditLine>> getAll() async {
    final rows = await _db.db.query('credit_lines', orderBy: 'sort_order');
    return rows.map(CreditLine.fromMap).toList();
  }

  @override
  Future<CreditLine?> getById(String id) async {
    final rows = await _db.db.query('credit_lines', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : CreditLine.fromMap(rows.first);
  }

  @override
  Future<void> update(CreditLine line) =>
      _db.db.update('credit_lines', line.toMap(), where: 'id = ?', whereArgs: [line.id]);
}

class SqliteInstallmentRepository implements InstallmentRepository {
  SqliteInstallmentRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<InstallmentPlan>> getAll() async {
    final rows = await _db.db.query('installment_plans', orderBy: 'start_date');
    return rows.map(InstallmentPlan.fromMap).toList();
  }

  @override
  Future<InstallmentPlan?> getById(String id) async {
    final rows = await _db.db.query('installment_plans', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : InstallmentPlan.fromMap(rows.first);
  }

  @override
  Future<void> save(InstallmentPlan plan) => _upsert(_db.db, 'installment_plans', plan.toMap());

  @override
  Future<void> delete(String id) async {
    await _db.db.transaction((txn) async {
      // Payments stay in the history but no longer drive a plan.
      await txn.update('payments', {'plan_id': null}, where: 'plan_id = ?', whereArgs: [id]);
      await txn.delete('installment_plans', where: 'id = ?', whereArgs: [id]);
    });
  }
}

class SqlitePaymentRepository implements PaymentRepository {
  SqlitePaymentRepository(this._db);
  final AppDatabase _db;

  @override
  Future<List<Payment>> getAll() async {
    final rows = await _db.db.query('payments', orderBy: 'date DESC, created_at DESC');
    return rows.map(Payment.fromMap).toList();
  }

  @override
  Future<Payment?> getById(String id) async {
    final rows = await _db.db.query('payments', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Payment.fromMap(rows.first);
  }

  @override
  Future<void> insert(Payment payment) => _db.db.insert('payments', payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace);

  @override
  Future<void> delete(String id) =>
      _db.db.delete('payments', where: 'id = ?', whereArgs: [id]);
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);
  final AppDatabase _db;

  @override
  Future<String?> get(String key) async {
    final rows = await _db.db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> set(String key, String? value) async {
    if (value == null) {
      await _db.db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
