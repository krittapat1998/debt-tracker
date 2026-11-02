import 'package:debt_tracker/data/repositories/repositories.dart';
import 'package:debt_tracker/data/services/settings_service.dart';
import 'package:debt_tracker/platform/app_lock_service.dart';
import 'package:debt_tracker/ui/providers.dart';
import 'package:debt_tracker/ui/screens/settings_screen.dart';
import 'package:debt_tracker/ui/theme.dart';
import 'package:debt_tracker/ui/widgets/app_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettings implements SettingsRepository {
  final m = <String, String>{};
  @override
  Future<String?> get(String key) async => m[key];
  @override
  Future<void> set(String key, String? value) async => value == null ? m.remove(key) : m[key] = value;
}

/// Answers Face ID prompts with [next] and counts them.
class _FakeLock implements AppLockService {
  bool next = false;
  bool available = true;
  int asked = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> unlock(String reason) async {
    asked++;
    return next;
  }
}

void main() {
  late _FakeLock lock;
  late _MemorySettings settings;

  setUp(() {
    lock = _FakeLock();
    settings = _MemorySettings();
  });

  Future<ProviderContainer> pump(WidgetTester tester, Widget home, {bool locked = false, Duration? relockAfter}) async {
    final container = ProviderContainer(overrides: [
      appLockServiceProvider.overrideWithValue(lock),
      initialAppLockProvider.overrideWithValue(locked),
      settingsRepositoryProvider.overrideWithValue(settings),
      notificationPrefsProvider.overrideWith((ref) async => const NotificationPrefs()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('th'),
        supportedLocales: const [Locale('th'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) =>
            AppLockGate(relockAfter: relockAfter ?? const Duration(minutes: 1), child: child!),
        home: home,
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  void goAway(WidgetTester tester) {
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  void comeBack(WidgetTester tester) {
    for (final s in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('a locked app asks for Face ID at start and stays covered until it passes', (tester) async {
    await pump(tester, const Scaffold(body: Text('ยอดหนี้รวม')), locked: true);
    expect(lock.asked, 1);
    expect(find.text('Debt Tracker ล็อกอยู่'), findsOneWidget);

    lock.next = true;
    await tester.tap(find.text('ปลดล็อก'));
    await tester.pumpAndSettle();
    expect(lock.asked, 2);
    expect(find.text('Debt Tracker ล็อกอยู่'), findsNothing);
    expect(find.text('ยอดหนี้รวม'), findsOneWidget);
  });

  testWidgets('it locks again after being away long enough, not after a short trip', (tester) async {
    lock.next = true;
    await pump(tester, const Scaffold(body: Text('ยอดหนี้รวม')), locked: true, relockAfter: const Duration(hours: 1));
    expect(find.text('Debt Tracker ล็อกอยู่'), findsNothing);

    goAway(tester);
    comeBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Debt Tracker ล็อกอยู่'), findsNothing);
    expect(lock.asked, 1);
  });

  testWidgets('away past the limit, it locks and asks again', (tester) async {
    lock.next = true;
    await pump(tester, const Scaffold(body: Text('ยอดหนี้รวม')), locked: true, relockAfter: Duration.zero);
    lock.next = false;
    goAway(tester);
    comeBack(tester);
    await tester.pumpAndSettle();
    expect(lock.asked, 2);
    expect(find.text('Debt Tracker ล็อกอยู่'), findsOneWidget);
  });

  testWidgets('an unlocked app never shows the lock screen', (tester) async {
    await pump(tester, const Scaffold(body: Text('ยอดหนี้รวม')), relockAfter: Duration.zero);
    goAway(tester);
    comeBack(tester);
    await tester.pumpAndSettle();
    expect(lock.asked, 0);
    expect(find.text('Debt Tracker ล็อกอยู่'), findsNothing);
  });

  testWidgets('turning the lock on in settings needs Face ID, and is remembered', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = await pump(tester, const SettingsScreen());
    final title = find.textContaining('ล็อกแอพด้วย');
    await tester.scrollUntilVisible(title, 300, scrollable: find.byType(Scrollable).first);

    // Face ID cancelled: still off.
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(container.read(appLockProvider), isFalse);

    lock.next = true;
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(container.read(appLockProvider), isTrue);
    expect(await SettingsService(settings).appLockEnabled(), isTrue);

    // A phone without Face ID or a passcode cannot turn it on.
    await tester.tap(title);
    await tester.pumpAndSettle();
    lock.available = false;
    final asked = lock.asked;
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(lock.asked, asked);
    expect(container.read(appLockProvider), isFalse);
  });
}
