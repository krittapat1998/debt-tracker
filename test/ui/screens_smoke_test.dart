import 'dart:io';

import 'package:debt_tracker/core/date_utils.dart';
import 'package:debt_tracker/core/formatters.dart';
import 'package:debt_tracker/data/repositories/repositories.dart';
import 'package:debt_tracker/data/services/ledger_service.dart';
import 'package:debt_tracker/data/services/settings_service.dart';
import 'package:debt_tracker/data/sources/sms/sms_parser_config.dart';
import 'package:debt_tracker/domain/finance/loan_math.dart';
import 'package:debt_tracker/domain/finance/portfolio.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
import 'package:debt_tracker/domain/models/recurring_charge.dart';
import 'package:debt_tracker/domain/models/spending.dart';
import 'package:debt_tracker/ui/providers.dart';
import 'package:debt_tracker/ui/screens/account_detail_screen.dart';
import 'package:debt_tracker/ui/screens/account_form_screen.dart';
import 'package:debt_tracker/ui/screens/calculator_screen.dart';
import 'package:debt_tracker/ui/screens/calendar_screen.dart';
import 'package:debt_tracker/ui/screens/dashboard_screen.dart';
import 'package:debt_tracker/ui/screens/history_screen.dart';
import 'package:debt_tracker/ui/screens/payment_form_screen.dart';
import 'package:debt_tracker/ui/screens/payoff_plan_screen.dart';
import 'package:debt_tracker/ui/screens/plan_form_screen.dart';
import 'package:debt_tracker/ui/screens/schedule_screen.dart';
import 'package:debt_tracker/ui/screens/settings_screen.dart';
import 'package:debt_tracker/ui/screens/sms_import_screen.dart';
import 'package:debt_tracker/ui/screens/sms_patterns_screen.dart';
import 'package:debt_tracker/ui/theme.dart';
import 'package:debt_tracker/ui/widgets/card_colors.dart';
import 'package:debt_tracker/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettings implements SettingsRepository {
  final _m = <String, String>{};
  @override
  Future<String?> get(String key) async => _m[key];
  @override
  Future<void> set(String key, String? value) async =>
      value == null ? _m.remove(key) : _m[key] = value;
}

/// Records spending instead of writing to a database.
class _RecordingLedger implements LedgerService {
  final spending = <Spending>[];
  final updated = <Spending>[];
  final charges = <RecurringCharge>[];
  final savedPlans = <InstallmentPlan>[];
  final billingDays = <(String, int)>[];
  final savedAccounts = <Account>[];
  final updatedPayments = <(Payment, bool)>[];
  @override
  Future<Payment> updatePayment(Payment p, {required bool alreadyInBalance}) async {
    updatedPayments.add((p, alreadyInBalance));
    return p;
  }
  @override
  Future<void> saveAccount(Account account, List<CreditLine> creditLines) async => savedAccounts.add(account);
  final recurringIncluded = <bool?>[];
  @override
  Future<RecurringCharge> saveRecurring(RecurringCharge c, {bool? alreadyInBalance}) async {
    charges.add(c);
    recurringIncluded.add(alreadyInBalance);
    // Like the ledger: rounds up to today are recorded and the charge moves on.
    var saved = c;
    while (!saved.nextDate.isAfter(dateOnly(DateTime.now()))) {
      saved = saved.copyWith(nextDate: saved.following(saved.nextDate));
    }
    return saved;
  }
  @override
  Future<void> savePlan(InstallmentPlan p) async => savedPlans.add(p);
  @override
  Future<void> setBillingDay(String accountId, int day) async => billingDays.add((accountId, day));
  final alreadyInBalance = <bool?>[];
  @override
  Future<Spending> recordSpending(Spending s, {bool? alreadyInBalance}) async {
    this.alreadyInBalance.add(alreadyInBalance);
    final saved = s.copyWith(lineBalanceApplied: alreadyInBalance == true ? 0 : s.amount);
    spending.add(saved);
    return saved;
  }

  @override
  Future<Spending> updateSpending(Spending s, {required bool alreadyInBalance}) async {
    this.alreadyInBalance.add(alreadyInBalance);
    final saved = s.copyWith(lineBalanceApplied: alreadyInBalance ? 0 : s.amount);
    updated.add(saved);
    return saved;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sample data shaped like real use: a card with a 0% installment billed
/// on the statement, a card with two sub-limits and a locked-in loan, and a
/// flat-rate cash-card loan with a prepayment.
PortfolioSummary samplePortfolio({
  List<Spending> spendings = const [],
  List<RecurringCharge> recurring = const [],
  DateTime? ktcBalanceAsOf,
  int? ktcColor,
}) {
  final today = dateOnly(DateTime.now());
  final created = today.subtract(const Duration(days: 120));
  DateTime ago(int days) => today.subtract(Duration(days: days));
  return PortfolioSummary.build(
    accounts: [
      Account(id: 'a1', name: 'KTC Visa Platinum', type: AccountType.creditCard, issuer: 'ktc', cardLast4: '1234',
          billingDay: 20, dueDay: 5, statementBalance: 15230.5, minimumPayment: 1523.05, statementDate: ago(10), color: ktcColor,
          createdAt: created),
      Account(id: 'a2', name: 'UOB Preferred Platinum', type: AccountType.creditCard, issuer: 'uob',
          billingDay: 10, dueDay: 28, statementBalance: 8400, minimumPayment: 840, statementDate: ago(20), createdAt: created),
      Account(id: 'a3', name: 'First Choice', type: AccountType.cashCard, dueDay: 15, createdAt: created),
    ],
    lines: [
      CreditLine(id: 'l1', accountId: 'a1', name: 'วงเงินบัตรเครดิต', creditLimit: 80000, balance: 12000, annualRate: 16,
          balanceAsOf: ktcBalanceAsOf),
      const CreditLine(id: 'l2', accountId: 'a2', name: 'วงเงินบัตรเครดิต', creditLimit: 100000, balance: 8400, annualRate: 16),
      const CreditLine(id: 'l3', accountId: 'a2', name: 'วงเงินสินเชื่อ', creditLimit: 60000, annualRate: 22, sortOrder: 1),
      const CreditLine(id: 'l4', accountId: 'a3', name: 'วงเงินกดเงินสด', creditLimit: 50000, annualRate: 25),
    ],
    plans: [
      InstallmentPlan(id: 'p1', accountId: 'a1', creditLineId: 'l1', name: 'ผ่อน iPhone 0%', principal: 45000, annualRate: 0,
          interestMethod: InterestMethod.reducing, termMonths: 10, startDate: ago(80), includedInStatement: true, createdAt: created),
      InstallmentPlan(id: 'p2', accountId: 'a2', creditLineId: 'l3', name: 'สินเชื่อ Express', principal: 60000, annualRate: 22,
          interestMethod: InterestMethod.reducing, termMonths: 24, startDate: ago(60), lockInMonths: 12, penaltyPercent: 3,
          paidBeforeTracking: 2, createdAt: created),
      InstallmentPlan(id: 'p3', accountId: 'a3', creditLineId: 'l4', name: 'สินเชื่อก้อน', principal: 50000, annualRate: 15,
          interestMethod: InterestMethod.flat, termMonths: 36, startDate: ago(130), paidBeforeTracking: 3, createdAt: created),
    ],
    payments: [
      Payment(id: 'x1', accountId: 'a2', creditLineId: 'l2', date: ago(5), amount: 840, type: PaymentType.minimum,
          lineBalanceApplied: 840, createdAt: ago(5)),
      Payment(id: 'x2', accountId: 'a3', planId: 'p3', date: ago(15), amount: 2013.89, type: PaymentType.installment, createdAt: ago(15)),
      Payment(id: 'x3', accountId: 'a3', planId: 'p3', date: ago(10), amount: 5000, type: PaymentType.extra,
          prepaymentMode: PrepaymentMode.reduceTerm, note: 'โปะจากเงินเหลือ', source: PaymentSource.sms, createdAt: ago(10)),
    ],
    spendings: spendings,
    recurring: recurring,
    today: today,
  );
}

/// pumpAndSettle that fails fast instead of hanging for 10 minutes.
Future<void> settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 10));

void main() {
  late PortfolioSummary portfolio;

  setUp(() => portfolio = samplePortfolio());

  Future<ProviderContainer> pump(WidgetTester tester, Widget screen,
      {PortfolioSummary? data, LedgerService? ledger, ThemeData? theme}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith((ref) async => data ?? portfolio),
      if (ledger != null) ledgerProvider.overrideWithValue(ledger),
      settingsRepositoryProvider.overrideWithValue(_MemorySettings()),
      notificationPrefsProvider.overrideWith((ref) async => const NotificationPrefs()),
      smsConfigProvider.overrideWith(
          (ref) async => SmsParserConfig.fromJsonString(File('assets/sms_patterns.json').readAsStringSync())),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        locale: const Locale('th'),
        supportedLocales: const [Locale('th'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // A fresh key per pump so a re-pumped screen gets a new State.
        home: KeyedSubtree(key: UniqueKey(), child: screen),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    return container;
  }

  testWidgets('dashboard with data, avalanche expanded', (tester) async {
    await pump(tester, const DashboardScreen());
    expect(find.text('ยอดหนี้รวมทั้งหมด'), findsOneWidget);
    // First Choice's loan installment is overdue: the alert says so.
    expect(find.text('เลยกำหนดจ่ายแล้ว: First Choice'), findsOneWidget);
    expect(find.text('นำเข้า SMS'), findsOneWidget);
    expect(find.text('เพิ่มบัตร'), findsOneWidget);
    await tester.tap(find.textContaining('ดูลำดับที่ควรโปะ'));
    await settle(tester);
    // Cards follow due dates, starting with the overdue First Choice.
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await settle(tester);
    final byName = {for (final a in portfolio.accounts) a.account.name: a};
    final shown = [for (final e in find.byType(Text).evaluate()) ?byName[(e.widget as Text).data]];
    expect(shown.first.account.name, 'First Choice');
    final dues = [for (final a in shown) a.nextDueDate!];
    expect(dues, [...dues]..sort());
    expect(find.text('ดอกแพงสุด'), findsOneWidget);
  });

  testWidgets('dashboard empty state', (tester) async {
    await pump(tester, const DashboardScreen(),
        data: PortfolioSummary(accounts: const [], today: DateTime.now()));
    expect(find.text('ยังไม่มีบัตรหรือสินเชื่อ'), findsOneWidget);
  });

  for (final id in ['a1', 'a2', 'a3']) {
    testWidgets('account detail $id', (tester) async {
      await pump(tester, AccountDetailScreen(accountId: id));
      // Each sample account has one plan; its details open and close.
      await tester.scrollUntilVisible(find.text('รายละเอียด'), 300, scrollable: find.byType(Scrollable).first);
      await settle(tester);
      await tester.tap(find.text('รายละเอียด'));
      await settle(tester);
      expect(find.text('ดอกที่จ่ายไปแล้ว'), findsOneWidget);
      await tester.ensureVisible(find.text('ซ่อน'));
      await settle(tester);
      await tester.tap(find.text('ซ่อน'));
      await settle(tester);
      expect(find.text('ดอกที่จ่ายไปแล้ว'), findsNothing);
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await settle(tester);
    });
  }

  testWidgets('card page leads with what to pay and by when', (tester) async {
    await pump(tester, const AccountDetailScreen(accountId: 'a1'));
    final due = portfolio.byId('a1')!.statementDueDate!;
    expect(find.text('ต้องจ่ายภายใน ${fmtDate(due)}'), findsOneWidget);
    expect(find.text('฿1,523.05'), findsOneWidget);
    expect(find.text('฿15,230.50'), findsOneWidget);
    expect(find.text('ดอกสูงสุด 16%/ปี'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.scrollUntilVisible(find.text('ไม่มีดอก'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('แอพบวกค่างวดเข้ายอดรูดบัตรให้ทุกวันตัดรอบ จ่ายพร้อมบิลบัตร ไม่ต้องจ่ายแยก'), findsOneWidget);
    // iPhone 0%: 3 of 10 on the card, 7 × 4,500 still to come.
    expect(find.text('บัตรแจ้งแล้ว 3/10 งวด · เหลืออีก 7 เดือน'), findsOneWidget);
    expect(find.text('ยังไม่ลงบัตร 7 งวด'), findsOneWidget);
    expect(find.text('ค่างวดที่บัตรยังไม่แจ้ง'), findsOneWidget);
    expect(find.textContaining('7 งวด รวมดอกแล้ว'), findsOneWidget);

    // A paid statement and an overdue installment.
    await pump(tester, const AccountDetailScreen(accountId: 'a2'));
    expect(find.text('บิลบัตร: จ่ายขั้นต่ำครบแล้ว'), findsOneWidget);
    await pump(tester, const AccountDetailScreen(accountId: 'a3'));
    expect(find.textContaining('เลยกำหนดจ่าย'), findsOneWidget);
    expect(find.text('ค่าผ่อน สินเชื่อก้อน'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ดอก flat 15%/ปี'), 300, scrollable: find.byType(Scrollable).first);
  });

  testWidgets('a cash card calls new spending a withdrawal', (tester) async {
    final ledger = _RecordingLedger();
    await pump(tester, const AccountDetailScreen(accountId: 'a3'), ledger: ledger);
    expect(find.text('เพิ่มยอดใช้จ่าย'), findsNothing);
    await tester.tap(find.text('เพิ่มยอดกดเงินสด'));
    await settle(tester);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('เพิ่มยอดกดเงินสด')), findsOneWidget);
    expect(find.text('วันที่กดเงินสด'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'ยอดที่กด'), '3,000');
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect((ledger.spending.single.creditLineId, ledger.spending.single.amount), ('l4', 3000.0));
    expect(find.text('เพิ่มยอดกดเงินสด ฿3,000.00 แล้ว · ยอดกดเงินสด ฿3,000.00'), findsOneWidget);

    final today = dateOnly(DateTime.now());
    await pump(tester, const AccountDetailScreen(accountId: 'a3'),
        data: samplePortfolio(spendings: [
          Spending(id: 's1', accountId: 'a3', creditLineId: 'l4', date: today, amount: 3000, lineBalanceApplied: 3000,
              createdAt: today),
        ]),
        ledger: ledger);
    await tester.scrollUntilVisible(find.text('฿3,000.00 · กดเงินสด'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('ประวัติการกดเงินสด (1)'), findsOneWidget);
  });

  testWidgets('add spending adds the amount to that sub-limit', (tester) async {
    final ledger = _RecordingLedger();
    await pump(tester, const AccountDetailScreen(accountId: 'a1'), ledger: ledger);
    await tester.tap(find.text('เพิ่มยอดใช้จ่าย'));
    await settle(tester);
    expect(find.textContaining('ยอดรูดบัตรตอนนี้ ฿12,000.00'), findsOneWidget);
    // One sub-limit: nothing to choose.
    expect(find.text('ใช้จากวงเงิน'), findsNothing);

    // Empty amount is rejected.
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect(find.text('กรุณากรอก'), findsOneWidget);
    expect(ledger.spending, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'ยอดที่ใช้'), '1,200');
    await tester.enterText(find.widgetWithText(TextFormField, 'รายละเอียด'), '  ค่าอาหาร ');
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    final s = ledger.spending.single;
    expect((s.accountId, s.creditLineId, s.amount, s.note), ('a1', 'l1', 1200.0, 'ค่าอาหาร'));
    expect(dateOnly(s.date), dateOnly(DateTime.now()));
    expect(find.text('เพิ่มยอดใช้จ่าย ฿1,200.00 แล้ว · ยอดรูดบัตร ฿13,200.00'), findsOneWidget);
    // The balance was never typed in, so nothing to ask.
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('spending on the day the balance was typed in asks whether it is already counted', (tester) async {
    final ledger = _RecordingLedger();
    final today = dateOnly(DateTime.now());
    await pump(tester, const AccountDetailScreen(accountId: 'a1'),
        data: samplePortfolio(ktcBalanceAsOf: today), ledger: ledger);
    await tester.scrollUntilVisible(find.textContaining('อัปเดตตามแอพธนาคารล่าสุด ${fmtDate(today)}'), 300,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await settle(tester);

    await tester.tap(find.text('เพิ่มยอดใช้จ่าย'));
    await settle(tester);
    // Same day could go either way: asked, and added unless switched on.
    expect(find.text('ยอดรูดบัตรที่แก้ไว้เมื่อ ${fmtDate(today)} รวมรายการนี้แล้ว'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    expect(find.text('ไม่บวกเพิ่ม — ยอดรูดบัตรยังเป็น ฿12,000.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'ยอดที่ใช้'), '1,500');
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect(ledger.alreadyInBalance.single, isTrue);
    expect(find.text('บันทึกยอดใช้จ่าย ฿1,500.00 แล้ว · ยอดรูดบัตรรวมรายการนี้อยู่แล้ว ไม่บวกซ้ำ'), findsOneWidget);
  });

  testWidgets('tapping spending on the card page edits it', (tester) async {
    final ledger = _RecordingLedger();
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    await pump(
      tester,
      const AccountDetailScreen(accountId: 'a1'),
      ledger: ledger,
      data: samplePortfolio(spendings: [
        Spending(id: 's1', accountId: 'a1', creditLineId: 'l1', date: yesterday, amount: 350, lineBalanceApplied: 350,
            note: 'ค่าอาหาร', createdAt: yesterday),
      ]),
    );
    await tester.scrollUntilVisible(find.text('฿350.00 · ค่าอาหาร'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('฿350.00 · ค่าอาหาร'));
    await settle(tester);

    expect(find.text('แก้ไขยอดใช้จ่าย'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '350'), findsOneWidget);
    // It was added, so the switch starts off; the preview shows the result.
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.text('ยอดรูดบัตร ฿12,000.00 → ฿12,000.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '350'), '500');
    await settle(tester);
    expect(find.text('ยอดรูดบัตร ฿12,000.00 → ฿12,150.00'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await settle(tester);
    expect(find.text('ยอดรูดบัตร ฿12,000.00 → ฿11,650.00'), findsOneWidget);

    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    final s = ledger.updated.single;
    expect((s.id, s.amount, s.note, s.date, s.createdAt), ('s1', 500.0, 'ค่าอาหาร', yesterday, yesterday));
    expect(ledger.alreadyInBalance.single, isTrue);
    expect(find.text('แก้ไขยอดใช้จ่ายแล้ว · ยอดรูดบัตร ฿11,650.00'), findsOneWidget);
  });

  testWidgets('the row menu edits too; the switch says "กรอกไว้" before any balance was typed in', (tester) async {
    final ledger = _RecordingLedger();
    final yesterday = dateOnly(DateTime.now()).subtract(const Duration(days: 1));
    await pump(
      tester,
      const AccountDetailScreen(accountId: 'a1'),
      ledger: ledger,
      data: samplePortfolio(spendings: [
        Spending(id: 's1', accountId: 'a1', creditLineId: 'l1', date: yesterday, amount: 350, lineBalanceApplied: 350,
            createdAt: yesterday),
      ]),
    );
    await tester.scrollUntilVisible(find.text('฿350.00 · ใช้จ่าย'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.byTooltip('แก้ไขหรือลบ'));
    await settle(tester);
    await tester.tap(find.text('แก้ไข'));
    await settle(tester);
    expect(find.text('ยอดรูดบัตรที่กรอกไว้รวมรายการนี้แล้ว'), findsOneWidget);
  });

  testWidgets('recurring charges are listed on the card page and added with a dialog', (tester) async {
    final ledger = _RecordingLedger();
    final today = dateOnly(DateTime.now());
    final next = today.add(const Duration(days: 5));
    await pump(
      tester,
      const AccountDetailScreen(accountId: 'a1'),
      ledger: ledger,
      data: samplePortfolio(recurring: [
        RecurringCharge(id: 'r1', accountId: 'a1', creditLineId: 'l1', name: 'Netflix', amount: 419, nextDate: next,
            anchorDay: next.day, createdAt: today),
      ]),
    );
    final header = find.widgetWithText(SectionHeader, 'รายการหักประจำ (1)');
    await tester.scrollUntilVisible(find.text('฿419.00 · Netflix'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(find.textContaining('ทุกเดือน วันที่ ${next.day}\nครั้งถัดไป ${fmtDate(next)}'), findsOneWidget);

    await tester.ensureVisible(find.descendant(of: header, matching: find.text('เพิ่ม')));
    await settle(tester);
    await tester.tap(find.descendant(of: header, matching: find.text('เพิ่ม')));
    await settle(tester);
    expect(find.text('เพิ่มรายการหักประจำ'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'ชื่อรายการ'), 'Spotify');
    await tester.enterText(find.widgetWithText(TextFormField, 'ยอดที่หักต่อรอบ'), '149');
    // No date yet: not saved.
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect(ledger.charges, isEmpty);

    await tester.tap(find.text('วันที่หัก'));
    await settle(tester);
    await tester.tap(find.text('ตกลง'));
    await settle(tester);
    // Today: the charge the card just took is recorded right away, and the
    // dialog asks whether the balance already has it.
    expect(find.textContaining('หักทุกเดือน วันที่ ${today.day} · บันทึกยอดของ ${fmtDate(today)}ให้เลย'), findsOneWidget);
    expect(find.textContaining('รวมรายการนี้แล้ว'), findsOneWidget);
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    final c = ledger.charges.single;
    expect((c.accountId, c.creditLineId, c.name, c.amount, c.nextDate, c.anchorDay, c.active),
        ('a1', 'l1', 'Spotify', 149.0, today, today.day, true));
    expect(ledger.recurringIncluded.single, isFalse);
    expect(find.text('เพิ่ม Spotify แล้ว · บันทึกยอด ${fmtDate(today)}แล้ว · ครั้งถัดไป ${fmtDate(c.following(today))}'),
        findsOneWidget);
  });

  testWidgets('spending that was not added to the balance says so', (tester) async {
    final today = dateOnly(DateTime.now());
    await pump(
      tester,
      const HistoryScreen(),
      data: samplePortfolio(spendings: [
        Spending(id: 's1', accountId: 'a1', creditLineId: 'l1', date: today, amount: 350, createdAt: today),
      ]),
    );
    expect(find.textContaining('ไม่ได้บวกยอด (รวมอยู่แล้ว)'), findsOneWidget);
  });

  testWidgets('add spending on a card with two sub-limits asks which one', (tester) async {
    final ledger = _RecordingLedger();
    await pump(tester, const AccountDetailScreen(accountId: 'a2'), ledger: ledger);
    await tester.tap(find.text('เพิ่มยอดใช้จ่าย'));
    await settle(tester);
    await tester.tap(find.text('วงเงินบัตรเครดิต').last);
    await settle(tester);
    await tester.tap(find.text('วงเงินสินเชื่อ').last);
    await settle(tester);
    expect(find.textContaining('ยอดรูดบัตรตอนนี้ ฿0.00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'ยอดที่ใช้'), '500');
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect((ledger.spending.single.creditLineId, ledger.spending.single.amount), ('l3', 500.0));
  });

  testWidgets('spending history shows the latest three, with notes, and expands', (tester) async {
    final today = dateOnly(DateTime.now());
    await pump(
      tester,
      const AccountDetailScreen(accountId: 'a2'),
      data: samplePortfolio(spendings: [
        for (var i = 1; i <= 4; i++)
          Spending(id: 's$i', accountId: 'a2', creditLineId: 'l2', date: today.subtract(Duration(days: i)),
              amount: 100.0 * i, lineBalanceApplied: 100.0 * i, note: i == 1 ? 'ค่าอาหาร' : null, createdAt: today),
      ]),
    );
    await tester.scrollUntilVisible(find.text('ประวัติการใช้จ่าย (4)'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    // Newest first; the account has two sub-limits, so each row names its own.
    expect(find.text('฿100.00 · ค่าอาหาร'), findsOneWidget);
    expect(find.textContaining('\nวงเงินบัตรเครดิต'), findsNWidgets(3));
    expect(find.text('฿400.00 · ใช้จ่าย'), findsNothing);
    await tester.tap(find.text('ดูทั้งหมด'));
    await settle(tester);
    expect(find.text('฿400.00 · ใช้จ่าย'), findsOneWidget);
  });

  testWidgets('history mixes payments and spending, and filters by kind', (tester) async {
    final today = dateOnly(DateTime.now());
    await pump(
      tester,
      const HistoryScreen(),
      data: samplePortfolio(spendings: [
        Spending(id: 's1', accountId: 'a1', creditLineId: 'l1', date: today, amount: 350, lineBalanceApplied: 350,
            note: 'ค่าอาหาร', createdAt: today),
      ]),
    );
    expect(find.text('฿350.00 · ค่าอาหาร'), findsOneWidget);
    expect(find.text('฿840.00 · จ่ายขั้นต่ำ'), findsOneWidget);
    // Two-line rows: the date, then the account and details.
    expect(find.textContaining('\nUOB Preferred Platinum · วงเงินบัตรเครดิต'), findsOneWidget);

    await tester.tap(find.text('การจ่าย'));
    await settle(tester);
    expect(find.text('฿350.00 · ค่าอาหาร'), findsNothing);
    expect(find.text('฿840.00 · จ่ายขั้นต่ำ'), findsOneWidget);

    await tester.tap(find.text('ยอดใช้จ่าย'));
    await settle(tester);
    expect(find.text('฿350.00 · ค่าอาหาร'), findsOneWidget);
    expect(find.text('฿840.00 · จ่ายขั้นต่ำ'), findsNothing);

    // Tapping a row opens its card.
    await tester.tap(find.text('฿350.00 · ค่าอาหาร'));
    await settle(tester);
    expect(find.byType(AccountDetailScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await settle(tester);

    await tester.tap(find.text('First Choice'));
    await settle(tester);
    expect(find.text('ยังไม่มียอดใช้จ่าย'), findsOneWidget);
  });

  testWidgets('account form: new and edit', (tester) async {
    await pump(tester, const AccountFormScreen());
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(tester);
    await pump(tester, AccountFormScreen(existing: portfolio.byId('a2')));
    expect(find.text('แก้ไข UOB Preferred Platinum'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('วงเงินสินเชื่อ'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
  });

  testWidgets('account form: the picked card color is saved', (tester) async {
    final ledger = _RecordingLedger();
    await pump(tester, AccountFormScreen(existing: portfolio.byId('a2')), ledger: ledger);
    await tester.tap(find.byTooltip('ม่วง'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('บันทึกการแก้ไข'), 500, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('บันทึกการแก้ไข'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(ledger.savedAccounts.single.color, 0xFF6A1B9A);
  });

  testWidgets('colored cards and the blue theme render', (tester) async {
    final colored = samplePortfolio(ktcColor: 0xFFF9A825);
    await pump(tester, const DashboardScreen(), data: colored, theme: AppTheme.blue());
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await settle(tester);
    final card = tester.widget<Card>(find.ancestor(of: find.text('KTC Visa Platinum'), matching: find.byType(Card)).first);
    expect(card.color ?? Theme.of(tester.element(find.text('KTC Visa Platinum'))).cardTheme.color, const Color(0xFFF9A825));
    // Yellow is light: its text goes dark.
    expect(Theme.of(tester.element(find.text('KTC Visa Platinum'))).colorScheme.onSurface, const Color(0xFF1B1B1B));
  });

  testWidgets('settings: picking a theme applies and saves it', (tester) async {
    final container = await pump(tester, const SettingsScreen());
    await tester.tap(find.text('น้ำเงิน'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(container.read(themeChoiceProvider), ThemeChoice.blue);
    expect(await tester.runAsync(() => container.read(settingsServiceProvider).themeChoice()), ThemeChoice.blue);
    expect(themeForCard(AppTheme.light(), const Color(0xFF212121)).colorScheme.onSurface, Colors.white);
  });

  testWidgets('plan form: principal from the installment, and a check of what counts as paid', (tester) async {
    await pump(tester, PlanFormScreen(account: portfolio.byId('a2')!));
    await tester.enterText(find.widgetWithText(TextFormField, 'ชื่อรายการ'), 'UOB Express');
    await tester.enterText(find.widgetWithText(TextFormField, 'ดอกเบี้ยต่อปี'), '25');
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนงวด'), '11');
    await tester.tap(find.text('ธนาคารกำหนดค่าผ่อนต่อเดือนมาแล้ว'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'ค่าผ่อนต่อเดือน'), '3000');
    await settle(tester);
    await tester.tap(find.text('ไม่รู้เงินต้น? คำนวณจากค่าผ่อนนี้'));
    await settle(tester);
    final principal = LoanMath.round2(LoanMath.principalForPayment(3000, 25, 11));
    expect(find.widgetWithText(TextFormField, amountToField(principal)), findsOneWidget);

    // Paid separately: the first due date is next month, so nothing is due yet.
    await tester.scrollUntilVisible(find.text('ค่างวดรวมอยู่ในยอดเรียกเก็บของบัตรแล้ว'), 300,
        scrollable: find.byType(Scrollable).first);
    // Clear of the snack bar the principal button showed.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(tester);
    await tester.tap(find.text('ค่างวดรวมอยู่ในยอดเรียกเก็บของบัตรแล้ว'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'จ่ายไปแล้วกี่งวด (ก่อนเริ่มใช้แอพ)'), '2');
    await settle(tester);
    expect(find.textContaining('นับว่าจ่ายแล้วเกินงวดที่ครบกำหนด 2 งวด'), findsOneWidget);
    await tester.tap(find.text('ใส่ 0'));
    await settle(tester);
    expect(find.textContaining('นับว่าจ่ายแล้วเกิน'), findsNothing);
  });

  testWidgets('payment form edits a recorded payment', (tester) async {
    final ledger = _RecordingLedger();
    final x2 = portfolio.byId('a3')!.payments.firstWhere((p) => p.id == 'x2');
    await pump(tester, PaymentFormScreen(existing: x2), ledger: ledger);
    expect(find.text('แก้ไขการจ่าย'), findsOneWidget);
    // Previewed against the plan without this payment: it is the next installment again.
    expect(find.textContaining('ครบกำหนด'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนเงิน'), '2100');
    await tester.scrollUntilVisible(find.text('บันทึก'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('บันทึก'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    final (saved, _) = ledger.updatedPayments.single;
    expect((saved.id, saved.planId, saved.type, saved.amount, saved.createdAt),
        ('x2', 'p3', PaymentType.installment, 2100, x2.createdAt));
  });

  testWidgets('editing a card payment previews from the balance before it', (tester) async {
    final a2 = portfolio.byId('a2')!;
    final x1 = a2.payments.firstWhere((p) => p.id == 'x1');
    final l2 = a2.lines.firstWhere((l) => l.id == 'l2');
    await pump(tester, PaymentFormScreen(existing: x1), ledger: _RecordingLedger());
    // Same amount: the balance comes back to what it is now, not 840 lower.
    expect(find.text('${fmtMoney(l2.balance + 840)} → ${fmtMoney(l2.balance)}'), findsOneWidget);
  });

  testWidgets('plan form: new, edit flat plan', (tester) async {
    await pump(tester, PlanFormScreen(account: portfolio.byId('a1')!));
    await tester.enterText(find.widgetWithText(TextFormField, 'เงินต้นตั้งต้น'), '100000');
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนงวด'), '12');
    await settle(tester);
    expect(find.text('สรุปค่าใช้จ่าย'), findsOneWidget);
    final a3 = portfolio.byId('a3')!;
    await pump(tester, PlanFormScreen(account: a3, existing: a3.plans.first.plan));
    expect(find.textContaining('flat แพงกว่า'), findsOneWidget);
  });

  testWidgets('a plan billed on a cash card asks how far the card shows it', (tester) async {
    final ledger = _RecordingLedger();
    final a3 = portfolio.byId('a3')!;
    await pump(tester, PlanFormScreen(account: a3), ledger: ledger);
    await tester.enterText(find.widgetWithText(TextFormField, 'ชื่อรายการ'), 'เงินยืม');
    await tester.enterText(find.widgetWithText(TextFormField, 'เงินต้นตั้งต้น'), '10000');
    await tester.enterText(find.widgetWithText(TextFormField, 'ดอกเบี้ยต่อปี'), '25');
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนงวด'), '6');
    await settle(tester);
    // On by default for a cash card; the card has no cutoff day yet.
    expect(find.text('วันครบกำหนดงวดแรก'), findsNothing);
    await tester.scrollUntilVisible(find.text('บัตรแจ้งถึงงวดที่'), 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.widgetWithText(TextFormField, 'บัตรแจ้งถึงงวดที่'), '3');
    await tester.tap(find.text('ไม่ระบุ'));
    await settle(tester);
    await tester.tap(find.text('วันที่ 5').last);
    await settle(tester);
    expect(find.textContaining('งวดถัดไปแอพจะบวกเข้ายอดกดเงินสดวันตัดรอบ'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('บันทึก'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('บันทึก'));
    await settle(tester);

    expect(ledger.billingDays, [('a3', 5)]);
    final p = ledger.savedPlans.single;
    expect((p.includedInStatement, p.paidBeforeTracking, p.postedThrough, p.anchorDay), (true, 3, 3, 5));
    expect(p.startDate, InstallmentPlan.firstCutoff(billingDay: 5, posted: 3, today: DateTime.now()));
  });

  testWidgets('payment form: default, installment, extra with preview', (tester) async {
    await pump(tester, const PaymentFormScreen());
    await pump(tester, const PaymentFormScreen(accountId: 'a2', planId: 'p2', type: PaymentType.installment));
    expect(find.text('ตัดดอกเบี้ย'), findsOneWidget);
    await pump(tester, const PaymentFormScreen(accountId: 'a3', planId: 'p3', type: PaymentType.extra, amount: 10000));
    expect(find.text('ประหยัดดอกเบี้ย'), findsOneWidget);
    await tester.tap(find.text(PrepaymentMode.reducePayment.label));
    await settle(tester);
  });

  testWidgets('calculator: from plan and manual', (tester) async {
    await pump(tester, const CalculatorScreen(initialPlanId: 'p2'));
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนเงินที่จะโปะเพิ่ม'), '20000');
    await settle(tester);
    await tester.scrollUntilVisible(find.text('ประหยัดดอกกว่า'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('ประหยัดดอกกว่า'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await settle(tester);

    await pump(tester, const CalculatorScreen());
    await tester.tap(find.text('กรอกเอง'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'เงินต้นคงเหลือ'), '100000');
    await tester.enterText(find.widgetWithText(TextFormField, 'ดอกเบี้ยต่อปี'), '12');
    await tester.enterText(find.widgetWithText(TextFormField, 'งวดคงเหลือ'), '24');
    await tester.enterText(find.widgetWithText(TextFormField, 'จำนวนเงินที่จะโปะเพิ่ม'), '200000');
    await settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await settle(tester);
    expect(find.text('ปิดยอดได้ทันที'), findsNWidgets(2));
  });

  testWidgets('schedule, history, settings, SMS screens', (tester) async {
    await pump(tester, const ScheduleScreen(accountId: 'a3', planId: 'p3'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(tester);
    await pump(tester, const HistoryScreen());
    expect(find.textContaining('โปะ'), findsWidgets);
    await pump(tester, const SettingsScreen());
    await pump(tester, const SmsPatternsScreen());
  });

  testWidgets('calendar: next month lists card bills still to come; a day shows only its own', (tester) async {
    await pump(tester, const CalendarScreen());
    expect(find.text('ปฏิทินครบกำหนด'), findsOneWidget);
    expect(find.text('ทั้งเดือน'), findsOneWidget);
    await tester.tap(find.byTooltip('เดือนถัดไป'));
    await settle(tester);
    // Next month's bills are not out yet: no amount.
    await tester.scrollUntilVisible(find.text('รอบิล').first, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('รอบิล'), findsWidgets);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await settle(tester);
    await tester.tap(find.text('5'));
    await settle(tester);
    expect(find.text('ดูทั้งเดือน'), findsOneWidget);
    final next = addMonths(DateTime.now(), 1);
    expect(find.text(fmtDate(DateTime(next.year, next.month, 5))), findsOneWidget);
    expect(find.text('KTC Visa Platinum'), findsOneWidget);
    expect(find.text('UOB Preferred Platinum'), findsNothing);
  });

  testWidgets('debt-free plan: a monthly extra brings the date closer and is remembered', (tester) async {
    final container = await pump(tester, const PayoffPlanScreen());
    expect(find.text('ปลดหนี้หมด'), findsOneWidget);
    String date() => tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains(RegExp(r'^\S+ 25\d\d$')))).data!;
    final before = date();
    await tester.tap(find.text('+฿2,000'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(date(), isNot(before));
    expect(find.text('ประหยัดดอกเบี้ย'), findsOneWidget);
    expect(find.textContaining('เร็วกว่าจ่ายแค่ขั้นต่ำ'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('โปะอันนี้ก่อน'), 300, scrollable: find.byType(Scrollable).first);
    // First Choice's 25.98% loan is the most expensive one that may be prepaid.
    expect(find.descendant(of: find.widgetWithText(ListTile, 'First Choice · สินเชื่อก้อน'), matching: find.textContaining('โปะอันนี้ก่อน')),
        findsOneWidget);
    expect(await tester.runAsync(() => container.read(settingsServiceProvider).payoffExtra()), 2000);
  });

  testWidgets('settings speak plainly, and the SMS tester reads a bank message', (tester) async {
    await pump(tester, const SettingsScreen());
    for (final jargon in ['regex', 'JSON', 'AES', 'CSV', 'server', 'cloud', 'พาร์ส']) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
    await pump(tester, const SmsPatternsScreen());
    await tester.enterText(find.widgetWithText(TextField, 'ข้อความ SMS'),
        'KTC: ยอดเรียกเก็บบัตร x1234 รอบ 10/10/69 จำนวน 15,230.50 บ. ขั้นต่ำ 1,523.05 บ. ครบกำหนดชำระ 25/10/69');
    await tester.tap(find.text('ลองอ่านยอด'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(find.textContaining('อ่านได้ ✓'), findsOneWidget);
    expect(find.textContaining('฿15,230.50'), findsOneWidget);
  });

  testWidgets('SMS import: pasted message → pending card → review sheet', (tester) async {
    final container = await pump(tester, const SmsImportScreen());
    await tester.runAsync(() => container.read(pendingImportsProvider.notifier).addPasted(
        'KTC: ยอดเรียกเก็บบัตร x1234 รอบ 10/10/69 จำนวน 15,230.50 บ. ขั้นต่ำ 1,523.05 บ. ครบกำหนดชำระ 25/10/69'));
    await settle(tester);
    expect(find.text('ตรวจสอบและบันทึก'), findsOneWidget);
    await tester.tap(find.text('ตรวจสอบและบันทึก'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(find.text('ตรวจสอบก่อนบันทึก'), findsOneWidget);
    // Matched by card digits to the KTC account.
    expect(find.text('KTC Visa Platinum •••• 1234'), findsOneWidget);
  });

  test('pasting the same SMS again neither queues nor imports it twice', () async {
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith((ref) async => samplePortfolio()),
      settingsRepositoryProvider.overrideWithValue(_MemorySettings()),
      smsConfigProvider.overrideWith(
          (ref) async => SmsParserConfig.fromJsonString(File('assets/sms_patterns.json').readAsStringSync())),
    ]);
    addTearDown(container.dispose);
    final pending = container.read(pendingImportsProvider.notifier);
    const sms = 'KTC: ได้รับชำระบัตร x1234 จำนวน 2,000.00 บ. วันที่ 30/10/69';

    expect(await pending.addPasted(sms), PasteResult.added);
    expect(await pending.addPasted(sms), PasteResult.alreadyPending);
    expect(container.read(pendingImportsProvider), hasLength(1));

    // A rejected paste can be pasted again.
    await pending.resolve(container.read(pendingImportsProvider).single, imported: false);
    expect(await pending.addPasted(sms), PasteResult.added);

    // An imported one needs an explicit "add again".
    await pending.resolve(container.read(pendingImportsProvider).single, imported: true);
    expect(await pending.addPasted(sms), PasteResult.alreadyImported);
    expect(container.read(pendingImportsProvider), isEmpty);
    expect(await pending.addPasted(sms, force: true), PasteResult.added);
  });
}
