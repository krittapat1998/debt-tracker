import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/db/app_database.dart';
import 'data/repositories/sqlite_repositories.dart';
import 'data/services/settings_service.dart';
import 'platform/home_widget_service.dart';
import 'platform/notification_service.dart';
import 'ui/app.dart';
import 'ui/providers.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Keeps the native launch screen (the app icon) up a second longer.
  binding.deferFirstFrame();
  try {
    await initializeDateFormatting('th');
    final db = await AppDatabase.open();
    final settings = SettingsService(SqliteSettingsRepository(db));
    final theme = await settings.themeChoice();
    final appLock = await settings.appLockEnabled();
    await NotificationService.instance.init();
    await HomeWidgetService().init();
    runApp(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialThemeChoiceProvider.overrideWithValue(theme),
        initialAppLockProvider.overrideWithValue(appLock),
      ],
      child: const DebtTrackerApp(),
    ));
  } catch (e) {
    // Say what went wrong instead of staying on the launch screen.
    runApp(MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('เปิดแอพไม่สำเร็จ ข้อมูลยังอยู่ในเครื่อง ลองปิดแล้วเปิดใหม่ หรือแจ้งผู้พัฒนา\n\n$e'),
          ),
        ),
      ),
    ));
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  binding.allowFirstFrame();
}
