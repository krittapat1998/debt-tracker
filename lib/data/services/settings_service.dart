import '../repositories/repositories.dart';

class NotificationPrefs {
  const NotificationPrefs({
    this.enabled = true,
    this.hour = 9,
    this.billingReminders = true,
  });

  final bool enabled;

  /// Hour of day (0-23) reminders fire at.
  final int hour;

  /// Also remind on each card's billing (statement) date.
  final bool billingReminders;
}

/// App look, picked in settings. [system] follows the phone's light/dark mode.
enum ThemeChoice {
  system('ตามระบบ'),
  light('สว่าง'),
  dark('มืด'),
  blue('น้ำเงิน');

  const ThemeChoice(this.label);
  final String label;

  static ThemeChoice fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => system);
}

/// Typed access to the key/value settings table.
class SettingsService {
  SettingsService(this._repo);
  final SettingsRepository _repo;

  static const _notifEnabled = 'notif_enabled';
  static const _notifHour = 'notif_hour';
  static const _notifBilling = 'notif_billing';
  static const _notifAsked = 'notif_asked';
  static const _smsLastScan = 'sms_last_scan';
  static const _smsListen = 'sms_listen';
  static const _smsCustomPatterns = 'sms_custom_patterns';
  static const _smsSeenKeys = 'sms_seen_keys';
  static const _theme = 'theme';
  static const _appLock = 'app_lock';

  Future<NotificationPrefs> notificationPrefs() async => NotificationPrefs(
        enabled: (await _repo.get(_notifEnabled)) != '0',
        hour: int.tryParse(await _repo.get(_notifHour) ?? '') ?? 9,
        billingReminders: (await _repo.get(_notifBilling)) != '0',
      );

  Future<void> saveNotificationPrefs(NotificationPrefs p) async {
    await _repo.set(_notifEnabled, p.enabled ? '1' : '0');
    await _repo.set(_notifHour, '${p.hour}');
    await _repo.set(_notifBilling, p.billingReminders ? '1' : '0');
  }

  /// Whether the app has asked for notification permission on its own.
  Future<bool> notificationPermissionAsked() async => (await _repo.get(_notifAsked)) == '1';

  Future<void> setNotificationPermissionAsked() => _repo.set(_notifAsked, '1');

  Future<ThemeChoice> themeChoice() async => ThemeChoice.fromName(await _repo.get(_theme));

  Future<void> setThemeChoice(ThemeChoice c) => _repo.set(_theme, c.name);

  /// Face ID (or the passcode) is needed to open the app.
  Future<bool> appLockEnabled() async => (await _repo.get(_appLock)) == '1';

  Future<void> setAppLockEnabled(bool v) => _repo.set(_appLock, v ? '1' : '0');

  Future<DateTime?> lastSmsScan() async =>
      DateTime.tryParse(await _repo.get(_smsLastScan) ?? '');

  Future<void> setLastSmsScan(DateTime t) => _repo.set(_smsLastScan, t.toIso8601String());

  Future<bool> smsListenEnabled() async => (await _repo.get(_smsListen)) == '1';

  Future<void> setSmsListenEnabled(bool v) => _repo.set(_smsListen, v ? '1' : '0');

  /// JSON list of user-defined SMS patterns (see BankSmsConfig).
  Future<String?> customSmsPatterns() => _repo.get(_smsCustomPatterns);

  Future<void> setCustomSmsPatterns(String? json) => _repo.set(_smsCustomPatterns, json);

  /// Keys of SMS already imported or dismissed, so a rescan skips them.
  Future<Set<String>> seenSmsKeys() async {
    final raw = await _repo.get(_smsSeenKeys);
    if (raw == null || raw.isEmpty) return {};
    return raw.split('\n').toSet();
  }

  Future<void> addSeenSmsKeys(Iterable<String> keys) async {
    final all = (await seenSmsKeys())..addAll(keys);
    // Keep the most recent entries only.
    final list = all.toList();
    final trimmed = list.length > 2000 ? list.sublist(list.length - 2000) : list;
    await _repo.set(_smsSeenKeys, trimmed.join('\n'));
  }
}
