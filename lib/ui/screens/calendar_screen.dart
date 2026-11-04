import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/due_calendar.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';
import '../widgets/app_icons.dart';

/// Every card and loan on one month: when bills and installments are due,
/// cutoffs, and recurring charges. Tap a day to see just that day.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _month = startOfMonth(DateTime.now());
  DateTime? _selected;

  static const _weekdays = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

  void _shift(int months) => setState(() {
        _month = startOfMonth(addMonths(_month, months, anchorDay: 1));
        _selected = null;
      });

  Color _color(BuildContext context, DueEvent e) {
    final cs = Theme.of(context).colorScheme;
    if (e.paid) return cs.positive;
    return switch (e.kind) {
      DueEventKind.cardDue || DueEventKind.installment => cs.error,
      DueEventKind.cutoff => cs.primary,
      DueEventKind.recurring => cs.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ปฏิทินครบกำหนด')),
      body: AsyncBody(
        value: ref.watch(portfolioProvider),
        builder: (s) {
          final first = _month;
          final last = endOfMonth(first);
          final events = dueEvents(s, first, last);
          final byDay = <int, List<DueEvent>>{};
          for (final e in events) {
            byDay.putIfAbsent(e.date.day, () => []).add(e);
          }
          final toPay = events
              .where((e) => e.kind.isPayment && !e.paid && e.amount != null)
              .fold(0.0, (sum, e) => sum + e.amount!);
          final billsPending = events.where((e) => e.kind == DueEventKind.cardDue && e.amount == null).length;
          final shown = _selected == null ? events : byDay[_selected!.day] ?? const <DueEvent>[];
          final blanks = first.weekday % 7; // Weeks start on Sunday.

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(icon: const GlyphIcon(Glyph.previous), tooltip: 'เดือนก่อน', onPressed: () => _shift(-1)),
                    Expanded(child: Text(fmtMonthYear(first), textAlign: TextAlign.center, style: t.titleMedium)),
                    IconButton(icon: const GlyphIcon(Glyph.next), tooltip: 'เดือนถัดไป', onPressed: () => _shift(1)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final w in _weekdays)
                          Expanded(
                            child: Text(w,
                                textAlign: TextAlign.center,
                                style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GridView.count(
                      crossAxisCount: 7,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 0.9,
                      children: [
                        for (var i = 0; i < blanks; i++) const SizedBox.shrink(),
                        for (var day = 1; day <= last.day; day++)
                          _DayCell(
                            day: day,
                            isToday: s.today == DateTime(first.year, first.month, day),
                            selected: _selected?.day == day,
                            dots: [for (final e in byDay[day] ?? const <DueEvent>[]) _color(context, e)],
                            onTap: () => setState(() {
                              final d = DateTime(first.year, first.month, day);
                              _selected = _selected == d ? null : d;
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _Legend(color: cs.error, label: 'ต้องจ่าย'),
                    _Legend(color: cs.positive, label: 'จ่ายแล้ว'),
                    _Legend(color: cs.primary, label: 'ตัดรอบ/ค่างวดลงบัตร'),
                    _Legend(color: cs.warning, label: 'หักประจำ'),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoRow('ยังต้องจ่ายเดือนนี้ (ที่รู้ยอดแล้ว)', fmtMoney(toPay), bold: true),
                      if (billsPending > 0)
                        Text('อีก $billsPending บิลบัตรยังไม่ออก จะรู้ยอดหลังวันตัดรอบ',
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              SectionHeader(
                _selected == null ? 'ทั้งเดือน' : fmtDate(_selected!),
                icon: Glyph.dueDate,
                trailing: _selected == null
                    ? null
                    : TextButton(onPressed: () => setState(() => _selected = null), child: const Text('ดูทั้งเดือน')),
              ),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('ไม่มีรายการ', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ),
              for (final e in shown)
                ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: _color(context, e).withValues(alpha: 0.15),
                    child: GlyphIcon(Glyph.forDueEvent(e.kind), size: 18, color: _color(context, e)),
                  ),
                  title: Text(e.title),
                  subtitle: Text([
                    fmtDate(e.date),
                    e.kind.label,
                    if (e.paid) 'จ่ายแล้ว',
                  ].join(' · ')),
                  trailing: Text(
                    e.amount == null ? 'รอบิล' : fmtMoney(e.amount!),
                    style: t.bodyMedium?.copyWith(
                      fontWeight: e.kind.isPayment && !e.paid ? FontWeight.w600 : null,
                      color: e.amount == null ? cs.onSurfaceVariant : null,
                    ),
                  ),
                  onTap: () => openAccount(context, e.accountId),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.dots,
    required this.onTap,
  });
  final int day;
  final bool isToday;
  final bool selected;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: t.bodyMedium?.copyWith(
                  fontWeight: isToday || dots.isNotEmpty ? FontWeight.w600 : null,
                  color: selected ? cs.onPrimaryContainer : null,
                )),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final c in dots.take(3))
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
