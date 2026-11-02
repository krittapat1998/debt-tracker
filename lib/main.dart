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
  await initializeDateFormatting('th');
  final db = await AppDatabase.open();
  final theme = await SettingsService(SqliteSettingsRepository(db)).themeChoice();
  await NotificationService.instance.init();
  await HomeWidgetService().init();
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      initialThemeChoiceProvider.overrideWithValue(theme),
    ],
    child: const DebtTrackerApp(),
  ));
  await Future<void>.delayed(const Duration(seconds: 1));
  binding.allowFirstFrame();
}
