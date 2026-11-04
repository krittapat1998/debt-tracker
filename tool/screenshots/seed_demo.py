"""Fill the simulator's app database with made-up demo data for README screenshots.

usage: python3 tool/screenshots/seed_demo.py <path to debt_tracker.db> [theme]   (app must not be running)
Nothing here is real: names are common Thai card products, amounts are invented.
"""
import sqlite3
import sys
from datetime import date, timedelta, datetime

db = sqlite3.connect(sys.argv[1])
theme = sys.argv[2] if len(sys.argv) > 2 else "light"
today = date.today()
d = lambda n: (today + timedelta(days=n))
iso = lambda n: d(n).isoformat()
created = (datetime.now() - timedelta(days=200)).isoformat()

for t in ["recurring_charges", "spendings", "payments", "installment_plans", "credit_lines", "accounts"]:
    db.execute(f"DELETE FROM {t}")

purple, blue, yellow, green = 0xFF6A1B9A, 0xFF1565C0, 0xFFF9A825, 0xFF2E7D32

acc = ("INSERT INTO accounts (id,name,type,issuer,card_last4,billing_day,due_day,statement_balance,minimum_payment,"
       "statement_date,statement_due_date,shared_limit,reminder_days_before,note,color,created_at) "
       "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
# KTC: bill out, due in 3 days.
db.execute(acc, ("a1", "KTC Visa Platinum", "creditCard", "ktc", "4821", d(-14).day, d(3).day, 23120.5, 6180.25,
                 iso(-14), iso(3), None, 3, None, purple, created))
# UOB: bill out, due in 12 days.
db.execute(acc, ("a2", "UOB Preferred Platinum", "creditCard", "uob", "1937", d(-8).day, d(12).day, 9480, 948,
                 iso(-8), iso(12), None, 3, None, blue, created))
db.execute(acc, ("a3", "Krungsri First Choice", "cashCard", None, None, None, d(9).day, 0, 0, None, None, None, 3,
                 None, yellow, created))
db.execute(acc, ("a4", "KBank Xpress Loan", "personalLoan", None, None, None, d(20).day, 0, 0, None, None, None, 3,
                 None, green, created))

line = ("INSERT INTO credit_lines (id,account_id,name,credit_limit,balance,annual_rate,interest_method,sort_order) "
        "VALUES (?,?,?,?,?,?,?,?)")
db.execute(line, ("l1", "a1", "วงเงินบัตรเครดิต", 120000, 23120.5, 16, "reducing", 0))
db.execute(line, ("l2", "a2", "วงเงินบัตรเครดิต", 100000, 9480, 16, "reducing", 0))
db.execute(line, ("l3", "a2", "วงเงินสินเชื่อ", 80000, 0, 22, "reducing", 1))
db.execute(line, ("l4", "a3", "วงเงินกดเงินสด", 60000, 0, 25, "reducing", 0))
db.execute(line, ("l5", "a4", "วงเงินสินเชื่อ", 150000, 0, 25, "reducing", 0))

plan = ("INSERT INTO installment_plans (id,account_id,credit_line_id,name,principal,annual_rate,interest_method,"
        "term_months,monthly_payment_override,start_date,lock_in_months,penalty_percent,penalty_fixed,"
        "included_in_statement,paid_before_tracking,note,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
db.execute(plan, ("p1", "a1", "l1", "ผ่อน iPhone 0% 10 เดือน", 45900, 0, "reducing", 10, None, iso(-80), 0, 0, 0, 1, 0,
                  None, created))
db.execute(plan, ("p2", "a2", "l3", "สินเชื่อ Express", 60000, 22, "reducing", 24, None, iso(-70), 12, 3, 0, 0, 2,
                  None, created))
db.execute(plan, ("p3", "a3", "l4", "กดเงินสดผ่อน 36 งวด", 50000, 15, "flat", 36, None, iso(-130), 0, 0, 0, 0, 4,
                  None, created))
db.execute(plan, ("p4", "a4", "l5", "สินเชื่อซ่อมบ้าน", 120000, 25, "reducing", 48, None, iso(-200), 0, 0, 0, 0, 6,
                  None, created))

pay = ("INSERT INTO payments (id,account_id,credit_line_id,plan_id,date,amount,type,prepayment_mode,note,source,"
       "line_balance_applied,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)")
rows = [
    ("x1", "a2", "l2", None, -38, 7800, "full", None, None, "manual", 7800),
    ("x2", "a1", "l1", None, -40, 5200, "minimum", None, None, "sms", 5200),
    ("x3", "a3", None, "p3", -21, 2014, "installment", None, None, "manual", 0),
    ("x4", "a4", None, "p4", -10, 3979, "installment", None, None, "sms", 0),
    ("x5", "a2", None, "p2", -6, 3111, "installment", None, None, "manual", 0),
    ("x6", "a3", None, "p3", -4, 5000, "extra", "reduceTerm", "โบนัสออก โปะก้อนดอกแพง", "manual", 0),
]
for (i, a, l, p, n, amt, typ, mode, note, src, applied) in rows:
    db.execute(pay, (i, a, l, p, iso(n), amt, typ, mode, note, src, applied, iso(n)))

sp = "INSERT INTO spendings (id,account_id,credit_line_id,date,amount,note,source,created_at) VALUES (?,?,?,?,?,?,?,?)"
for i, (n, amt, note, src) in enumerate([
        (-1, 420, "ค่าอาหาร", "manual"), (-2, 1290, "ซื้อของออนไลน์", "sms"),
        (-3, 2400, "เติมน้ำมัน", "manual"), (-5, 189, None, "sms")]):
    db.execute(sp, (f"s{i}", "a1", "l1", iso(n), amt, note, src, iso(n)))

rc = ("INSERT INTO recurring_charges (id,account_id,credit_line_id,name,amount,every,next_date,anchor_day,active,created_at) "
      "VALUES (?,?,?,?,?,?,?,?,?,?)")
db.execute(rc, ("r1", "a1", "l1", "Netflix", 419, "monthly", iso(6), d(6).day, 1, created))
db.execute(rc, ("r2", "a2", "l2", "Spotify", 149, "monthly", iso(15), d(15).day, 1, created))
db.execute(rc, ("r3", "a2", "l2", "iCloud+", 99, "monthly", iso(17), d(17).day, 1, created))

for k, v in {"payoff_budget": "25000.0", "payoff_budget_max": "35000.0", "theme": theme,
             "notif_asked": "1", "app_lock": "0"}.items():
    db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (k, v))

db.commit()
print("seeded", {t: db.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                 for t in ["accounts", "credit_lines", "installment_plans", "payments", "spendings", "recurring_charges"]})
