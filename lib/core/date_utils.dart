/// Calendar helpers that work on date-only values (no time component).
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Builds a date, clamping [day] to the last day of the month
/// (e.g. day 31 in February becomes 28/29).
DateTime clampedDate(int year, int month, int day) {
  final normalized = DateTime(year, month, 1);
  final last = daysInMonth(normalized.year, normalized.month);
  return DateTime(normalized.year, normalized.month, day.clamp(1, last));
}

/// Adds calendar months keeping the day-of-month where possible.
/// [anchorDay] lets a schedule keep "day 31" even after passing a short month.
DateTime addMonths(DateTime d, int months, {int? anchorDay}) {
  return clampedDate(d.year, d.month + months, anchorDay ?? d.day);
}

/// Next date (inclusive of [from]) whose day-of-month is [day].
DateTime nextOccurrenceOfDay(int day, DateTime from) {
  final f = dateOnly(from);
  final thisMonth = clampedDate(f.year, f.month, day);
  if (!thisMonth.isBefore(f)) return thisMonth;
  return clampedDate(f.year, f.month + 1, day);
}

/// Most recent date (inclusive of [from]) whose day-of-month is [day].
DateTime previousOccurrenceOfDay(int day, DateTime from) {
  final f = dateOnly(from);
  final thisMonth = clampedDate(f.year, f.month, day);
  if (!thisMonth.isAfter(f)) return thisMonth;
  return clampedDate(f.year, f.month - 1, day);
}

/// First date strictly after [after] whose day-of-month is [day].
DateTime nextDayAfter(int day, DateTime after) {
  final a = dateOnly(after);
  final thisMonth = clampedDate(a.year, a.month, day);
  if (thisMonth.isAfter(a)) return thisMonth;
  return clampedDate(a.year, a.month + 1, day);
}

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseIsoDate(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
