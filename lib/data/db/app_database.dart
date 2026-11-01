import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All data stays on the device.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  /// 2: spendings table. 3: credit_lines.balance_as_of and
  /// spendings.line_balance_applied (backdated entries vs typed-in balances).
  /// 4: recurring_charges table.
  static const _version = 4;
  static const fileName = 'debt_tracker.db';

  /// Parents before children (backup restore inserts in this order).
  static const tables = [
    'accounts', 'credit_lines', 'installment_plans', 'recurring_charges', 'payments', 'spendings', 'settings',
  ];

  static Future<AppDatabase> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => _create(db),
        onUpgrade: (db, oldVersion, _) async {
          final batch = db.batch();
          if (oldVersion < 2) _createSpendings(batch);
          if (oldVersion < 3) {
            batch.execute('ALTER TABLE credit_lines ADD COLUMN balance_as_of TEXT');
            // A version 1 database just got the spendings table with this column.
            if (oldVersion == 2) batch.execute('ALTER TABLE spendings ADD COLUMN line_balance_applied REAL');
          }
          if (oldVersion < 4) _createRecurringCharges(batch);
          await batch.commit(noResult: true);
        },
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
        sort_order INTEGER NOT NULL DEFAULT 0,
        balance_as_of TEXT
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
    _createSpendings(batch);
    _createRecurringCharges(batch);
    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    await batch.commit(noResult: true);
  }

  static void _createSpendings(Batch batch) {
    batch.execute('''
      CREATE TABLE spendings (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        credit_line_id TEXT REFERENCES credit_lines(id) ON DELETE SET NULL,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        line_balance_applied REAL,
        created_at TEXT NOT NULL
      )''');
    batch.execute('CREATE INDEX idx_spendings_account ON spendings(account_id, date)');
  }

  static void _createRecurringCharges(Batch batch) {
    batch.execute('''
      CREATE TABLE recurring_charges (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        credit_line_id TEXT REFERENCES credit_lines(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        every TEXT NOT NULL,
        next_date TEXT NOT NULL,
        anchor_day INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )''');
  }

  Future<void> close() => db.close();
}
