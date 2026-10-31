import 'package:intl/intl.dart';

const thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

const thaiMonthsLong = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

final _money = NumberFormat('#,##0.00', 'en_US');
final _moneyNoDecimal = NumberFormat('#,##0', 'en_US');

String fmtMoney(double v, {bool symbol = true}) {
  final s = _money.format(v.abs() < 0.005 ? 0 : v);
  return symbol ? '฿$s' : s;
}

String fmtMoneyCompact(double v) => '฿${_moneyNoDecimal.format(v.round())}';

String fmtPercent(double v, {int digits = 2}) => '${v.toStringAsFixed(digits)}%';

/// Thai-style date with Buddhist-era year, e.g. "5 พ.ย. 2569".
String fmtDate(DateTime d) =>
    '${d.day} ${thaiMonthsShort[d.month - 1]} ${d.year + 543}';

/// Short form, e.g. "5 พ.ย. 69".
String fmtDateShort(DateTime d) =>
    '${d.day} ${thaiMonthsShort[d.month - 1]} ${(d.year + 543) % 100}';

String fmtMonthYear(DateTime d) =>
    '${thaiMonthsLong[d.month - 1]} ${d.year + 543}';

String fmtMonths(int months) {
  if (months < 12) return '$months เดือน';
  final y = months ~/ 12;
  final m = months % 12;
  return m == 0 ? '$months เดือน ($y ปี)' : '$months เดือน ($y ปี $m เดือน)';
}

String fmtRelativeDays(int days) {
  if (days == 0) return 'วันนี้';
  if (days == 1) return 'พรุ่งนี้';
  if (days < 0) return 'เลยมา ${-days} วัน';
  return 'อีก $days วัน';
}

/// Parses user-typed amounts such as "1,234.50".
double? parseAmount(String? s) {
  if (s == null) return null;
  final cleaned = s.replaceAll(',', '').replaceAll('฿', '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Formats a number for an editable text field (no symbol, no trailing .00).
String amountToField(double? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return _moneyNoDecimal.format(v);
  return _money.format(v);
}
