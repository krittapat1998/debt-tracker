import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/settings_service.dart';
import '../domain/finance/portfolio.dart';
import 'providers.dart';
import 'screens/calculator_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/keyboard_dismiss.dart';
import 'widgets/app_icons.dart';

class DebtTrackerApp extends ConsumerWidget {
  const DebtTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeChoiceProvider);
    return MaterialApp(
      title: 'Debt Tracker',
      debugShowCheckedModeBanner: false,
      theme: choice == ThemeChoice.blue ? AppTheme.blue() : AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (choice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.light || ThemeChoice.blue => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      },
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => TapOutsideClosesKeyboard(child: AppLockGate(child: child!)),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  bool _permissionChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onForeground());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onForeground();
      // Dates roll over ("due in 2 days" → "tomorrow") while backgrounded.
      ref.refreshData();
    }
  }

  Future<void> _onForeground() async {
    final pending = ref.read(pendingImportsProvider.notifier);
    try {
      await pending.syncListening();
      await pending.pullBackground();
    } catch (e) {
      debugPrint('SMS sync skipped: $e');
    }
  }

  Future<void> _syncSideEffects(PortfolioSummary s) async {
    final settings = ref.read(settingsServiceProvider);
    final notifications = ref.read(notificationServiceProvider);
    final prefs = await settings.notificationPrefs();
    // Reminders are on by default, so ask for permission once, as soon as
    // there is something to remind about. Without it nothing is shown.
    if (prefs.enabled && s.accounts.isNotEmpty && !_permissionChecked) {
      _permissionChecked = true;
      if (!await settings.notificationPermissionAsked()) {
        await settings.setNotificationPermissionAsked();
        await notifications.requestPermission();
      }
    }
    await notifications.reschedule(s, prefs);
    await ref.read(homeWidgetServiceProvider).update(s);
  }

  @override
  Widget build(BuildContext context) {
    // Every data change refreshes reminders and the home-screen widget.
    ref.listen<AsyncValue<PortfolioSummary>>(portfolioProvider, (_, next) {
      next.whenData(_syncSideEffects);
    });
    ref.listen(notificationPrefsProvider, (_, next) {
      final s = ref.read(portfolioProvider).value;
      if (s != null) _syncSideEffects(s);
    });

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          DashboardScreen(),
          CalendarScreen(),
          HistoryScreen(),
          CalculatorScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: GlyphIcon(Glyph.home), selectedIcon: GlyphIcon(Glyph.home, filled: true), label: 'ภาพรวม'),
          NavigationDestination(icon: GlyphIcon(Glyph.calendar), selectedIcon: GlyphIcon(Glyph.calendar, filled: true), label: 'ปฏิทิน'),
          NavigationDestination(icon: GlyphIcon(Glyph.historyTab), selectedIcon: GlyphIcon(Glyph.historyTab, filled: true), label: 'ประวัติ'),
          NavigationDestination(icon: GlyphIcon(Glyph.calculatorTab), selectedIcon: GlyphIcon(Glyph.calculatorTab, filled: true), label: 'คำนวณโปะ'),
          NavigationDestination(icon: GlyphIcon(Glyph.settings), selectedIcon: GlyphIcon(Glyph.settings, filled: true), label: 'ตั้งค่า'),
        ],
      ),
    );
  }
}
