import 'dart:io';

import 'package:debt_tracker/core/date_utils.dart';
import 'package:debt_tracker/data/repositories/repositories.dart';
import 'package:debt_tracker/data/services/ledger_service.dart';
import 'package:debt_tracker/data/services/settings_service.dart';
import 'package:debt_tracker/data/sources/sms/sms_parser_config.dart';
import 'package:debt_tracker/domain/finance/portfolio.dart';
import 'package:debt_tracker/domain/models/account.dart';
import 'package:debt_tracker/domain/models/credit_line.dart';
import 'package:debt_tracker/domain/models/enums.dart';
import 'package:debt_tracker/domain/models/installment_plan.dart';
import 'package:debt_tracker/domain/models/payment.dart';
import 'package:debt_tracker/ui/providers.dart';
import 'package:debt_tracker/ui/screens/account_detail_screen.dart';
import 'package:debt_tracker/ui/screens/account_form_screen.dart';
import 'package:debt_tracker/ui/screens/calculator_screen.dart';
import 'package:debt_tracker/ui/screens/dashboard_screen.dart';
import 'package:debt_tracker/ui/screens/history_screen.dart';
import 'package:debt_tracker/ui/screens/payment_form_screen.dart';
import 'package:debt_tracker/ui/screens/plan_form_screen.dart';
import 'package:debt_tracker/ui/screens/schedule_screen.dart';
import 'package:debt_tracker/ui/screens/settings_screen.dart';
import 'package:debt_tracker/ui/screens/sms_import_screen.dart';
import 'package:debt_tracker/ui/screens/sms_patterns_screen.dart';
import 'package:debt_tracker/ui/theme.dart';
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
  final spending = <(String, double)>[];
  @override
  Future<void> addSpending(String lineId, double amount) async => spending.add((lineId, amount));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sample data shaped like real use: a card with a 0% installment billed
/// on the statement, a card with two sub-limits and a locked-in loan, and a
/// flat-rate cash-card loan with a prepayment.
PortfolioSummary samplePortfolio() {
  final today = dateOnly(DateTime.now());
  final created = today.subtract(const Duration(days: 120));
  DateTime ago(int days) => today.subtract(Duration(days: days));
  return PortfolioSummary.build(
    accounts: [
      Account(id: 'a1', name: 'KTC Visa Platinum', type: AccountType.creditCard, issuer: 'ktc', cardLast4: '1234',
          billingDay: 20, dueDay: 5, statementBalance: 15230.5, minimumPayment: 1523.05, statementDate: ago(10), createdAt: created),
      Account(id: 'a2', name: 'UOB Preferred Platinum', type: AccountType.creditCard, issuer: 'uob',
          billingDay: 10, dueDay: 28, statementBalance: 8400, minimumPayment: 840, statementDate: ago(20), createdAt: created),
      Account(id: 'a3', name: 'First Choice', type: AccountType.cashCard, dueDay: 15, createdAt: created),
    ],
    lines: const [
      CreditLine(id: 'l1', accountId: 'a1', name: 'วงเงินบัตรเครดิต', creditLimit: 80000, balance: 12000, annualRate: 16),
      CreditLine(id: 'l2', accountId: 'a2', name: 'วงเงินบัตรเครดิต', creditLimit: 100000, balance: 8400, annualRate: 16),
      CreditLine(id: 'l3', accountId: 'a2', name: 'วงเงินสินเชื่อ', creditLimit: 60000, annualRate: 22, sortOrder: 1),
      CreditLine(id: 'l4', accountId: 'a3', name: 'วงเงินกดเงินสด', creditLimit: 50000, annualRate: 25),
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
      {PortfolioSummary? data, LedgerService? ledger}) async {
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
        theme: AppTheme.light(),
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
    expect(find.text('ดอกแพงสุด'), findsOneWidget);
    await tester.tap(find.textContaining('ดูลำดับทั้งหมด'));
    await settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await settle(tester);
  });

  testWidgets('dashboard empty state', (tester) async {
    await pump(tester, const DashboardScreen(),
        data: PortfolioSummary(accounts: const [], today: DateTime.now()));
    expect(find.text('ยังไม่มีบัตรหรือสินเชื่อ'), findsOneWidget);
  });

  for (final id in ['a1', 'a2', 'a3']) {
    testWidgets('account detail $id', (tester) async {
      await pump(tester, AccountDetailScreen(accountId: id));
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await settle(tester);
    });
  }

  testWidgets('add spending adds the amount to that sub-limit', (tester) async {
    final ledger = _RecordingLedger();
    await pump(tester, const AccountDetailScreen(accountId: 'a1'), ledger: ledger);
    await tester.scrollUntilVisible(find.text('เพิ่มยอดใช้จ่าย'), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('เพิ่มยอดใช้จ่าย'));
    await settle(tester);
    expect(find.textContaining('ยอดคงค้างตอนนี้ ฿12,000.00'), findsOneWidget);

    // Empty amount is rejected.
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect(find.text('กรุณากรอก'), findsOneWidget);
    expect(ledger.spending, isEmpty);

    await tester.enterText(find.byType(TextFormField), '1,200');
    await tester.tap(find.text('บันทึก'));
    await settle(tester);
    expect(ledger.spending, [('l1', 1200.0)]);
    expect(find.text('เพิ่มยอดใช้จ่าย ฿1,200.00 แล้ว · ยอดคงค้าง ฿13,200.00'), findsOneWidget);
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
