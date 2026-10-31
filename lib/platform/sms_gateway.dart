import 'dart:io';

import 'package:flutter/services.dart';

import '../data/sources/statement_source_parser.dart';

/// Android-only bridge to the SMS inbox (see MainActivity.kt / SmsBridge.kt).
/// iOS has no public API to read SMS, so there the app relies on pasting.
class SmsGateway {
  static const _method = MethodChannel('debt_tracker/sms');
  static const _events = EventChannel('debt_tracker/sms_events');

  bool get isSupported => Platform.isAndroid;

  /// "granted", "denied" or "permanentlyDenied".
  Future<String> _status() async =>
      await _method.invokeMethod<String>('permissionStatus') ?? 'denied';

  Future<bool> hasPermission() async => isSupported && await _status() == 'granted';

  Future<bool> isPermanentlyDenied() async => isSupported && await _status() == 'permanentlyDenied';

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    return await _method.invokeMethod<bool>('requestPermission') ?? false;
  }

  Future<void> openSettings() async {
    if (isSupported) await _method.invokeMethod('openSettings');
  }

  static RawStatementMessage _fromMap(Map<Object?, Object?> m) => RawStatementMessage(
        source: StatementSourceType.sms,
        sender: (m['sender'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        receivedAt: DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as num).toInt()),
        externalId: m['id']?.toString(),
      );

  Future<List<RawStatementMessage>> readInbox({required DateTime since, int limit = 500}) async {
    if (!await hasPermission()) return const [];
    final list = await _method.invokeListMethod<Map<Object?, Object?>>('readInbox', {
      'sinceMillis': since.millisecondsSinceEpoch,
      'limit': limit,
    });
    return (list ?? const []).map(_fromMap).toList();
  }

  /// New SMS while the app is running.
  Stream<RawStatementMessage> incoming() => _events
      .receiveBroadcastStream()
      .map((e) => _fromMap((e as Map).cast<Object?, Object?>()));

  /// Lets the background receiver keep SMS that look like bank notices
  /// (sender or keyword match) while the app is closed, and post a
  /// "review it" notification. Nothing else is stored.
  Future<void> configureBackgroundCapture({
    required bool enabled,
    required List<String> senders,
    required List<String> keywords,
  }) async {
    if (!isSupported) return;
    await _method.invokeMethod('configure', {
      'enabled': enabled,
      'senders': senders,
      'keywords': keywords,
    });
  }

  /// SMS captured by the background receiver since the last call.
  Future<List<RawStatementMessage>> takePending() async {
    if (!isSupported) return const [];
    final list = await _method.invokeListMethod<Map<Object?, Object?>>('takePending');
    return (list ?? const []).map(_fromMap).toList();
  }
}
