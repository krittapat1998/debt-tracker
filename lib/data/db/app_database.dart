import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All data stays on the device.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _version = 1;
  static const fileName = 'debt_tracker.db';

  static const tables = ['accounts', 'credit_lines', 'installment_plans', 'payments', 'settings'];

  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _create(db),
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        issuer TEXT,
        card_last4 TEXT,
        billing_day INTEGER,
        due_day INTEGER,
        statement_balance REAL NOT NULL DEFAULT 0,
        minimum_payment REAL NOT NULL DEFAULT 0,
        statement_date TEXT,
        statement_due_date TEXT,
        shared_limit REAL,
        reminder_days_before INTEGER NOT NULL DEFAULT 3,
        note TEXT,
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE credit_lines (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        credit_limit REAL NOT NULL DEFAULT 0,
        balance REAL NOT NULL DEFAULT 0,
        annual_rate REAL NOT NULL DEFAULT 0,
        interest_method TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE installment_plans (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        credit_line_id TEXT REFERENCES credit_lines(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        principal REAL NOT NULL,
        annual_rate REAL NOT NULL DEFAULT 0,
        interest_method TEXT NOT NULL,
        term_months INTEGER NOT NULL,
        monthly_payment_override REAL,
        start_date TEXT NOT NULL,
        lock_in_months INTEGER NOT NULL DEFAULT 0,
        penalty_percent REAL NOT NULL DEFAULT 0,
        penalty_fixed REAL NOT NULL DEFAULT 0,
        included_in_statement INTEGER NOT NULL DEFAULT 0,
        paid_before_tracking INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        credit_line_id TEXT REFERENCES credit_lines(id) ON DELETE SET NULL,
        plan_id TEXT REFERENCES installment_plans(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        prepayment_mode TEXT,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        line_balance_applied REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_payments_account ON payments(account_id, date)');
    batch.execute('CREATE INDEX idx_payments_plan ON payments(plan_id)');
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}
