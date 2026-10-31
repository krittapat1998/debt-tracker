import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/date_utils.dart';
import '../core/formatters.dart';
import '../domain/finance/portfolio.dart';

/// Pushes a small summary to the home-screen widgets
/// (Android: DebtWidgetProvider.kt, iOS: ios/DebtWidget).
class HomeWidgetService {
  static const appGroupId = 'group.com.krittapat.debtTracker';
  static const iOSName = 'DebtWidget';
  static const androidProvider = 'com.krittapat.debt_tracker.DebtWidgetProvider';

  Future<void> init() async {
    if (Platform.isIOS) {
      try {
        await HomeWidget.setAppGroupId(appGroupId);
      } catch (e) {
        debugPrint('Home widget app group unavailable: $e');
      }
    }
  }

  Future<void> update(PortfolioSummary s) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final next = s.nextDue;
      final data = <String, String>{
        'total_debt': fmtMoney(s.totalDebt),
        'due_month': fmtMoney(s.monthlyDue.remaining),
        'next_due_name': next?.account.name ?? 'ไม่มีรายการใกล้ครบกำหนด',
        'next_due_date': next?.nextDueDate == null ? '' : fmtDate(next!.nextDueDate!),
        // Widgets recompute "in N days" from this at render time.
        'next_due_iso': next?.nextDueDate == null ? '' : isoDate(next!.nextDueDate!),
        'next_due_days': next?.daysUntilDue == null ? '' : fmtRelativeDays(next!.daysUntilDue!),
        'next_due_amount': next == null || next.nextDueAmount <= 0 ? '' : fmtMoney(next.nextDueAmount),
        'updated_at': 'อัปเดต ${fmtDateShort(DateTime.now())}',
      };
      for (final e in data.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(iOSName: iOSName, qualifiedAndroidName: androidProvider);
    } catch (e) {
      // No widget added yet / extension not installed: nothing to update.
      debugPrint('Home widget update skipped: $e');
    }
  }
}
