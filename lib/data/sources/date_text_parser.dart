/// Parses dates the way Thai banks write them: "25/10/69", "25/10/2569",
/// "25-10-2026", "25 ต.ค. 69", "25 Oct 2026", or without a year.
library;

const _thaiDigits = '๐๑๒๓๔๕๖๗๘๙';

String normalizeDigits(String s) {
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = _thaiDigits.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}

final Map<String, int> _months = () {
  final m = <String, int>{};
  const thaiAbbr = ['มค', 'กพ', 'มีค', 'เมย', 'พค', 'มิย', 'กค', 'สค', 'กย', 'ตค', 'พย', 'ธค'];
  const thaiFull = [
    'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
    'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
  ];
  const en = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  for (var i = 0; i < 12; i++) {
    m[thaiAbbr[i]] = i + 1;
    m[thaiFull[i]] = i + 1;
    m[en[i]] = i + 1;
  }
  return m;
}();

int? _monthOf(String token) {
  final t = token.replaceAll('.', '').replaceAll(' ', '').toLowerCase();
  if (_months.containsKey(t)) return _months[t];
  if (t.length >= 3 && _months.containsKey(t.substring(0, 3))) return _months[t.substring(0, 3)];
  return null;
}

/// Buddhist-era and two-digit years → Gregorian.
/// Two-digit years ≥ 50 are read as BE (69 → 2569 → 2026), smaller ones as
/// CE (26 → 2026); the two ranges do not overlap for the next decades.
int normalizeYear(int y) {
  if (y >= 2400) return y - 543;
  if (y >= 1900) return y;
  if (y >= 50) return 2500 + y - 543;
  return 2000 + y;
}

/// [reference] resolves dates written without a year: the result is the
/// closest such date not more than ~2 months before the reference.
DateTime? parseDateText(String input, {required DateTime reference}) {
  final s = normalizeDigits(input).trim();
  int? day;
  int? month;
  int? year;

  final numeric = RegExp(r'^(\d{1,2})\s*[/\-.]\s*(\d{1,2})(?:\s*[/\-.]\s*(\d{2,4}))?$').firstMatch(s);
  if (numeric != null) {
    day = int.parse(numeric.group(1)!);
    month = int.parse(numeric.group(2)!);
    year = numeric.group(3) == null ? null : int.parse(numeric.group(3)!);
  } else {
    final textual = RegExp(r'^(\d{1,2})\s*([^\d\s][^\d]*?)\s*(\d{2,4})?$', unicode: true).firstMatch(s);
    if (textual == null) return null;
    day = int.parse(textual.group(1)!);
    month = _monthOf(textual.group(2)!);
    year = textual.group(3) == null ? null : int.parse(textual.group(3)!);
  }
  if (month == null || month < 1 || month > 12 || day < 1 || day > 31) return null;

  if (year != null) {
    final y = normalizeYear(year);
    final d = DateTime(y, month, day);
    return d.month == month ? d : null;
  }
  final ref = DateTime(reference.year, reference.month, reference.day);
  var d = DateTime(ref.year, month, day);
  if (d.isBefore(ref.subtract(const Duration(days: 62)))) d = DateTime(ref.year + 1, month, day);
  return d.month == month ? d : null;
}

double? parseAmountText(String s) =>
    double.tryParse(normalizeDigits(s).replaceAll(',', '').trim());
