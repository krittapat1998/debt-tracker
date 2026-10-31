import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/db/app_database.dart';
import 'platform/home_widget_service.dart';
import 'platform/notification_service.dart';
import 'ui/app.dart';
import 'ui/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('th');
  final db = await AppDatabase.open();
  await NotificationService.instance.init();
  await HomeWidgetService().init();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const DebtTrackerApp(),
  ));
}
