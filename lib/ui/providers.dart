import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_service.dart';
import '../data/db/app_database.dart';
import '../data/repositories/repositories.dart';
import '../data/repositories/sqlite_repositories.dart';
import '../data/services/ledger_service.dart';
import '../data/services/settings_service.dart';
import '../data/sources/email/email_parser_service.dart';
import '../data/sources/sms/sms_parser_config.dart';
import '../data/sources/sms/sms_parser_service.dart';
import '../data/sources/statement_import_service.dart';
import '../data/sources/statement_source_parser.dart';
import '../domain/finance/portfolio.dart';
import '../platform/home_widget_service.dart';
import '../platform/notification_service.dart';
import '../platform/sms_gateway.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

final accountRepositoryProvider =
    Provider<AccountRepository>((ref) => SqliteAccountRepository(ref.watch(databaseProvider)));
final creditLineRepositoryProvider =
    Provider<CreditLineRepository>((ref) => SqliteCreditLineRepository(ref.watch(databaseProvider)));
final installmentRepositoryProvider =
    Provider<InstallmentRepository>((ref) => SqliteInstallmentRepository(ref.watch(databaseProvider)));
final paymentRepositoryProvider =
    Provider<PaymentRepository>((ref) => SqlitePaymentRepository(ref.watch(databaseProvider)));
final spendingRepositoryProvider =
    Provider<SpendingRepository>((ref) => SqliteSpendingRepository(ref.watch(databaseProvider)));
final recurringChargeRepositoryProvider =
    Provider<RecurringChargeRepository>((ref) => SqliteRecurringChargeRepository(ref.watch(databaseProvider)));
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => SqliteSettingsRepository(ref.watch(databaseProvider)));

final settingsServiceProvider =
    Provider<SettingsService>((ref) => SettingsService(ref.watch(settingsRepositoryProvider)));

final ledgerProvider = Provider<LedgerService>((ref) => LedgerService(
      accounts: ref.watch(accountRepositoryProvider),
      lines: ref.watch(creditLineRepositoryProvider),
      plans: ref.watch(installmentRepositoryProvider),
      payments: ref.watch(paymentRepositoryProvider),
      spendings: ref.watch(spendingRepositoryProvider),
      recurring: ref.watch(recurringChargeRepositoryProvider),
    ));

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));
final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService.instance);
final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) => HomeWidgetService());
final smsGatewayProvider = Provider<SmsGateway>((ref) => SmsGateway());

/// Everything the screens read, recomputed after each write via
/// `ref.invalidate(portfolioProvider)`.
final portfolioProvider = FutureProvider<PortfolioSummary>((ref) async {
  // Charges that came due since the last look (app opened or resumed, or
  // any write) become spending before the numbers are read.
  await ref.watch(ledgerProvider).recordDueCharges();
  final accounts = await ref.watch(accountRepositoryProvider).getAll();
  final lines = await ref.watch(creditLineRepositoryProvider).getAll();
  final plans = await ref.watch(installmentRepositoryProvider).getAll();
  final payments = await ref.watch(paymentRepositoryProvider).getAll();
  final spendings = await ref.watch(spendingRepositoryProvider).getAll();
  final recurring = await ref.watch(recurringChargeRepositoryProvider).getAll();
  return PortfolioSummary.build(
    accounts: accounts,
    lines: lines,
    plans: plans,
    payments: payments,
    spendings: spendings,
    recurring: recurring,
    today: DateTime.now(),
  );
});

final notificationPrefsProvider =
    FutureProvider<NotificationPrefs>((ref) => ref.watch(settingsServiceProvider).notificationPrefs());

/// Bundled SMS rules + the user's own patterns.
final smsConfigProvider = FutureProvider<SmsParserConfig>((ref) async {
  final bundled = SmsParserConfig.fromJsonString(await rootBundle.loadString('assets/sms_patterns.json'));
  final custom = await ref.watch(settingsServiceProvider).customSmsPatterns();
  if (custom == null || custom.trim().isEmpty) return bundled;
  try {
    return bundled.merge(SmsParserConfig.fromJsonString(custom));
  } catch (_) {
    return bundled;
  }
});

/// Every statement source parser. Add `EmailParserService` implementations
/// here when e-mail import is built; nothing else needs to change.
final statementParsersProvider = FutureProvider<List<StatementSourceParser>>((ref) async => [
      SmsParserService(await ref.watch(smsConfigProvider.future)),
      const EmailParserService(),
    ]);

final importServiceProvider = FutureProvider<StatementImportService>(
    (ref) async => StatementImportService(await ref.watch(statementParsersProvider.future)));

/// Keywords the Android background receiver uses to decide which incoming
/// SMS are worth keeping for review (plus every bank sender id).
const smsCaptureKeywords = [
  'ยอดเรียกเก็บ', 'ขั้นต่ำ', 'ครบกำหนด', 'ชำระ', 'ใช้จ่าย', 'บัตร',
  'statement', 'payment', 'minimum', 'spent',
];

/// Parsed bank messages waiting for the user to confirm or dismiss.
enum PasteResult { added, unreadable, alreadyPending, alreadyImported }

class PendingImportsNotifier extends Notifier<List<ParsedStatementEvent>> {
  StreamSubscription<RawStatementMessage>? _sub;

  @override
  List<ParsedStatementEvent> build() {
    ref.onDispose(() => _sub?.cancel());
    return const [];
  }

  Future<int> _add(Iterable<RawStatementMessage> messages) async {
    final importer = await ref.read(importServiceProvider.future);
    final seen = await ref.read(settingsServiceProvider).seenSmsKeys();
    final have = {for (final e in state) e.message.dedupKey};
    final fresh = <ParsedStatementEvent>[];
    for (final m in messages) {
      if (seen.contains(m.dedupKey) || have.contains(m.dedupKey)) continue;
      final e = importer.parse(m);
      if (e == null) continue;
      have.add(m.dedupKey);
      fresh.add(e);
    }
    if (fresh.isNotEmpty) {
      state = [...state, ...fresh]..sort((a, b) => b.message.receivedAt.compareTo(a.message.receivedAt));
    }
    return fresh.length;
  }

  /// Parses text the user pasted (works on both iOS and Android).
  /// Text imported before is only added again with [force], so a payment
  /// SMS pasted twice is not recorded twice by accident.
  Future<PasteResult> addPasted(String text, {bool force = false}) async {
    final m = RawStatementMessage(
      source: StatementSourceType.pasted,
      sender: '',
      body: text,
      receivedAt: DateTime.now(),
    );
    if (state.any((e) => e.message.dedupKey == m.dedupKey)) return PasteResult.alreadyPending;
    if (!force && (await ref.read(settingsServiceProvider).seenSmsKeys()).contains(m.dedupKey)) {
      return PasteResult.alreadyImported;
    }
    final e = (await ref.read(importServiceProvider.future)).parse(m);
    if (e == null) return PasteResult.unreadable;
    state = [e, ...state];
    return PasteResult.added;
  }

  Future<int> scanInbox({int days = 45}) async {
    final gw = ref.read(smsGatewayProvider);
    final settings = ref.read(settingsServiceProvider);
    final since = DateTime.now().subtract(Duration(days: days));
    final added = await _add(await gw.readInbox(since: since));
    await settings.setLastSmsScan(DateTime.now());
    return added;
  }

  /// Picks up SMS captured while the app was closed.
  Future<int> pullBackground() async {
    final gw = ref.read(smsGatewayProvider);
    if (!await gw.hasPermission()) return 0;
    return _add(await gw.takePending());
  }

  /// Keeps the Android receiver config in sync and listens while running.
  Future<void> syncListening() async {
    final gw = ref.read(smsGatewayProvider);
    if (!gw.isSupported) return;
    final enabled = await ref.read(settingsServiceProvider).smsListenEnabled() && await gw.hasPermission();
    final config = await ref.read(smsConfigProvider.future);
    await gw.configureBackgroundCapture(
      enabled: enabled,
      senders: config.allSenderIds,
      keywords: smsCaptureKeywords,
    );
    await _sub?.cancel();
    _sub = null;
    if (enabled) {
      _sub = gw.incoming().listen((m) => _add([m]));
    }
  }

  Future<void> resolve(ParsedStatementEvent e, {required bool imported}) async {
    state = state.where((x) => x.message.dedupKey != e.message.dedupKey).toList();
    // Inbox SMS are remembered either way so a rescan skips them; pasted
    // text only once imported, so a wrongly rejected paste can come back.
    if (imported || e.message.source != StatementSourceType.pasted) {
      await ref.read(settingsServiceProvider).addSeenSmsKeys([e.message.dedupKey]);
    }
  }
}

final pendingImportsProvider =
    NotifierProvider<PendingImportsNotifier, List<ParsedStatementEvent>>(PendingImportsNotifier.new);

extension DataRefresh on WidgetRef {
  void refreshData() => invalidate(portfolioProvider);
}
