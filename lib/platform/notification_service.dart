import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/date_utils.dart';
import '../core/formatters.dart';
import '../data/services/settings_service.dart';
import '../domain/finance/portfolio.dart';

class ScheduledReminder {
  ScheduledReminder(this.at, this.title, this.body);
  final DateTime at;
  final String title;
  final String body;
}

/// Local reminders for due dates, billing dates and separately-billed
/// installments. Everything is rebuilt from the current data on each
/// change, so a paid statement stops its reminders automatically.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// iOS allows 64 pending notifications per app.
  static const _maxPending = 60;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'due_reminders',
      'แจ้งเตือนครบกำหนดชำระ',
      channelDescription: 'เตือนก่อนวันครบกำหนดชำระและวันตัดรอบบิล',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_debt'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Returns how many reminders were scheduled.
  Future<int> reschedule(PortfolioSummary s, NotificationPrefs prefs, {DateTime? now}) async {
    try {
      await init();
      await _plugin.cancelAllPendingNotifications();
      if (!prefs.enabled) return 0;
      final reminders = buildReminders(s, prefs, now: now ?? DateTime.now());
      for (var i = 0; i < reminders.length; i++) {
        final r = reminders[i];
        await _plugin.zonedSchedule(
          id: 1000 + i,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
        );
      }
      return reminders.length;
    } catch (e, st) {
      debugPrint('Notification scheduling failed: $e\n$st');
      return 0;
    }
  }

  static DateTime _at(DateTime day, int hour) => DateTime(day.year, day.month, day.day, hour);

  @visibleForTesting
  static List<ScheduledReminder> buildReminders(PortfolioSummary s, NotificationPrefs prefs, {required DateTime now}) {
    final today = dateOnly(now);
    final out = <ScheduledReminder>[];

    void dueReminders(DateTime due, int daysBefore, String name, String detail) {
      if (daysBefore > 0) {
        out.add(ScheduledReminder(
          _at(due.subtract(Duration(days: daysBefore)), prefs.hour),
          'อีก $daysBefore วันครบกำหนด: $name',
          'ครบกำหนด ${fmtDate(due)} · $detail',
        ));
      }
      out.add(ScheduledReminder(_at(due, prefs.hour), 'วันนี้ครบกำหนดชำระ: $name', detail));
    }

    for (final a in s.accounts) {
      final acc = a.account;
      final days = acc.reminderDaysBefore;
      final hasSomethingToPay = a.totalDebt > 0.005 || acc.minimumPayment > 0;

      // Card statement due dates (this cycle + next).
      if (hasSomethingToPay) {
        final stmtDue = a.statementDueDate;
        DateTime? first;
        if (stmtDue != null && !a.isStatementPaid) {
          if (stmtDue.isBefore(today)) {
            out.add(ScheduledReminder(
              _at(today.add(const Duration(days: 1)), prefs.hour),
              'เลยกำหนดชำระ: ${acc.name}',
              'ครบกำหนด ${fmtDate(stmtDue)} · ขั้นต่ำคงเหลือ ${fmtMoney(a.minimumOutstanding)}',
            ));
          } else {
            first = stmtDue;
          }
        }
        if (first == null && acc.dueDay != null) {
          first = stmtDue != null && a.isStatementPaid && !stmtDue.isBefore(today)
              ? nextDayAfter(acc.dueDay!, stmtDue)
              : nextOccurrenceOfDay(acc.dueDay!, today);
        }
        if (first != null) {
          final unpaidNow = !a.isStatementPaid && first == stmtDue;
          dueReminders(
            first,
            days,
            acc.name,
            unpaidNow
                ? 'ขั้นต่ำ ${fmtMoney(a.minimumOutstanding)} · เต็มยอด ${fmtMoney(a.statementOutstanding)}'
                : 'ตรวจสอบยอดเรียกเก็บและชำระให้ทันกำหนด',
          );
          if (acc.dueDay != null) {
            dueReminders(nextDayAfter(acc.dueDay!, first), days, acc.name,
                'ตรวจสอบยอดเรียกเก็บและชำระให้ทันกำหนด');
          }
        }
      }

      // Billing (statement cut-off) dates.
      if (prefs.billingReminders && acc.billingDay != null && hasSomethingToPay) {
        final b1 = nextOccurrenceOfDay(acc.billingDay!, today);
        for (final b in [b1, nextDayAfter(acc.billingDay!, b1)]) {
          out.add(ScheduledReminder(
            _at(b, prefs.hour),
            'วันนี้ตัดรอบบิล: ${acc.name}',
            'เมื่อได้รับ SMS/ใบแจ้งยอด อย่าลืมอัปเดตยอดเรียกเก็บในแอพ',
          ));
        }
      }

      // Installments paid separately from the card (e.g. personal loans).
      for (final p in a.activePlans) {
        if (p.plan.includedInStatement) continue;
        for (final row in p.projection.take(2)) {
          if (row.dueDate == null) continue;
          dueReminders(row.dueDate!, days, '${acc.name} · ${p.plan.name}',
              'งวดที่ ${row.number} · ${fmtMoney(row.payment)}');
        }
      }
    }

    out.removeWhere((r) => !r.at.isAfter(now));
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.take(_maxPending).toList();
  }
}
