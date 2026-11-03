import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/payoff_plan.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/debt_chart.dart';
import '../widgets/form_fields.dart';

/// "If I put X more toward my debts each month, when am I debt-free?" —
/// every balance at once, extra money going to the most expensive first.
/// Two amounts can be compared: what is comfortable and the most one can.
class PayoffPlanScreen extends ConsumerStatefulWidget {
  const PayoffPlanScreen({super.key});

  @override
  ConsumerState<PayoffPlanScreen> createState() => _PayoffPlanScreenState();
}

class _PayoffPlanScreenState extends ConsumerState<PayoffPlanScreen> {
  final _extra = TextEditingController();
  final _max = TextEditingController();
  bool _loaded = false;
  bool _loadedMax = false;

  static const _quick = [1000.0, 2000.0, 5000.0];

  @override
  void dispose() {
    _extra.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _setExtra(double v, {bool fillField = false}) async {
    if (fillField) _extra.text = v == 0 ? '' : amountToField(v);
    setState(() {});
    await ref.read(settingsServiceProvider).setPayoffExtra(v);
    ref.invalidate(payoffExtraProvider);
  }

  Future<void> _setMax(double v) async {
    setState(() {});
    await ref.read(settingsServiceProvider).setPayoffMax(v);
    ref.invalidate(payoffMaxProvider);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(payoffExtraProvider).value;
    if (!_loaded && saved != null) {
      _loaded = true;
      if (saved > 0) _extra.text = amountToField(saved);
    }
    final savedMax = ref.watch(payoffMaxProvider).value;
    if (!_loadedMax && savedMax != null) {
      _loadedMax = true;
      if (savedMax > 0) _max.text = amountToField(savedMax);
    }
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('แผนปลดหนี้')),
      body: AsyncBody(
        value: ref.watch(portfolioProvider),
        builder: (s) {
          final debts = PayoffDebt.fromPortfolio(s);
          if (debts.isEmpty) {
            return const EmptyState(icon: Icons.celebration_outlined, title: 'ไม่มีหนี้ค้างแล้ว');
          }
          final extra = parseAmount(_extra.text) ?? 0;
          final most = parseAmount(_max.text) ?? 0;
          final base = PayoffPlanner.baseline(debts, start: s.today);
          final plan = PayoffPlanner.plan(debts, start: s.today, extra: extra);
          // The all-out plan, when it differs from the comfortable one.
          final stretch = most > extra + 0.005 ? PayoffPlanner.plan(debts, start: s.today, extra: most) : null;
          final order = [...debts]..sort((a, b) =>
              (plan.paidOff[a.id] ?? 1 << 20).compareTo(plan.paidOff[b.id] ?? 1 << 20));
          // Where the extra goes first: the most expensive balance not in lock-in.
          final open = [
            for (final d in debts)
              if (d.lockedUntil == null || !s.today.isBefore(d.lockedUntil!)) d,
          ]..sort((a, b) {
              final c = b.annualRate.compareTo(a.annualRate);
              return c != 0 ? c : a.balance.compareTo(b.balance);
            });
          final target = open.isEmpty ? null : open.first;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AmountField(
                        controller: _extra,
                        label: 'โปะที่ไหว/เดือน',
                        onChanged: (v) => _setExtra(parseAmount(v) ?? 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AmountField(
                        controller: _max,
                        label: 'โปะเต็มที่/เดือน',
                        onChanged: (v) => _setMax(parseAmount(v) ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 16, 0),
                child: Text(
                  'นอกจากขั้นต่ำบัตรและค่างวดที่จ่ายอยู่แล้ว · ใส่ช่องเต็มที่ไว้เทียบว่าถ้าโปะสุดตัวจะหมดเร็วขึ้นแค่ไหน',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final q in _quick)
                      ActionChip(label: Text('+${fmtMoneyCompact(q)}'), onPressed: () => _setExtra(q, fillField: true)),
                  ],
                ),
              ),
              _ResultCard(
                title: stretch == null ? 'ปลดหนี้หมด' : 'แบบที่ไหว · ปลดหนี้หมด',
                today: s.today,
                extra: extra,
                plan: plan,
                base: base,
              ),
              if (stretch != null)
                _ResultCard(
                  title: 'แบบเต็มที่ · ปลดหนี้หมด',
                  today: s.today,
                  extra: most,
                  plan: stretch,
                  base: base,
                  comparedTo: plan,
                ),
              const SectionHeader('ยอดหนี้รวมลดลงแบบนี้'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DebtChart(plan: plan.balances, baseline: base.balances, stretch: stretch?.balances, start: s.today),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 16,
                  children: [
                    _Legend(color: cs.primary, label: stretch == null ? 'ตามแผน' : 'แบบที่ไหว'),
                    if (stretch != null) _Legend(color: cs.tertiary, label: 'แบบเต็มที่'),
                    _Legend(color: cs.outline, label: 'จ่ายแค่ขั้นต่ำและค่างวด'),
                  ],
                ),
              ),
              SectionHeader(stretch == null ? 'ลำดับที่จะหมด' : 'ลำดับที่จะหมด (แบบที่ไหว)'),
              for (final (i, d) in order.indexed)
                ListTile(
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: t.labelMedium)),
                  title: Text(d.name),
                  subtitle: Text([
                    plan.paidOff[d.id] == null
                        ? 'ยังไม่หมด'
                        : 'หมด ${fmtMonthYear(addMonths(s.today, plan.paidOff[d.id]!))}',
                    'ดอก ${fmtRate(d.annualRate)}/ปี',
                    if (d.lockedUntil != null && s.today.isBefore(d.lockedUntil!))
                      'โปะได้ตั้งแต่ ${fmtDate(d.lockedUntil!)}',
                    if (extra > 0 && identical(d, target)) 'โปะอันนี้ก่อน',
                  ].join(' · ')),
                  trailing: Text(fmtMoney(d.balance)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'เป็นการประมาณ: บัตรคิดขั้นต่ำตามสัดส่วนในบิลล่าสุด (ถ้าไม่มีใช้ 8% สำหรับบัตรเครดิต 5% สำหรับบัตรอื่น) '
                  'ยังไม่รวมการใช้จ่ายใหม่และค่าปรับปิดก่อนกำหนด เงินที่โปะจะไปลงหนี้ที่ดอกแพงสุดก่อน '
                  'พอหนี้ไหนหมด เงินที่เคยจ่ายก้อนนั้นจะไปโปะก้อนถัดไปต่อ',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.today,
    required this.extra,
    required this.plan,
    required this.base,
    this.comparedTo,
  });
  final String title;
  final DateTime today;
  final double extra;
  final PayoffResult plan;
  final PayoffResult base;

  /// The comfortable plan, when this card is the all-out one.
  final PayoffResult? comparedTo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final months = plan.months;
    final sooner = months != null && base.months != null ? base.months! - months : null;
    final other = comparedTo;
    final soonerThanEasy = other?.months != null && months != null ? other!.months! - months : null;
    final bg = other == null ? cs.primaryContainer : cs.tertiaryContainer;
    final fg = other == null ? cs.onPrimaryContainer : cs.onTertiaryContainer;
    return Card(
      color: bg,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.labelLarge?.copyWith(color: fg)),
            Text(
              months == null ? 'ยังไม่หมด' : fmtMonthYear(addMonths(today, months)),
              style: t.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold),
            ),
            Text(
              months == null
                  ? 'จ่ายเท่านี้ดอกเบี้ยกินหมด หนี้ไม่ลด ลองเพิ่มเงินโปะ'
                  : [
                      'อีก ${fmtMonths(months)}',
                      if (other != null && soonerThanEasy != null && soonerThanEasy > 0)
                        'เร็วกว่าแบบที่ไหว ${fmtMonths(soonerThanEasy)}'
                      else if (other != null && soonerThanEasy == 0)
                        'หมดเดือนเดียวกับแบบที่ไหว แต่ดอกน้อยกว่า'
                      else if (other == null && sooner != null && sooner > 0)
                        'เร็วกว่าจ่ายแค่ขั้นต่ำ ${fmtMonths(sooner)}',
                      if (other == null && base.months == null) 'ถ้าจ่ายแค่ขั้นต่ำ หนี้จะไม่หมด',
                    ].join(' · '),
              style: t.bodyMedium?.copyWith(color: fg),
            ),
            const Divider(height: 24),
            InfoRow('จ่ายทุกเดือน', fmtMoney(plan.firstMonthPayment), bold: true),
            Text(
              'ขั้นต่ำบัตร ค่างวดทุกรายการ${extra > 0 ? ' และเงินโปะ ${fmtMoney(extra)}' : ''} '
              'หนี้ก้อนไหนหมด เงินก้อนนั้นไปโปะก้อนถัดไป',
              style: t.bodySmall?.copyWith(color: fg),
            ),
            const SizedBox(height: 6),
            InfoRow('ดอกเบี้ยรวมจากนี้ไป', fmtMoney(plan.totalInterest), valueColor: cs.error),
            if (base.totalInterest - plan.totalInterest > 1)
              InfoRow('ประหยัดดอกเบี้ย', fmtMoney(base.totalInterest - plan.totalInterest),
                  valueColor: cs.positive, bold: true),
            if (other != null && other.totalInterest - plan.totalInterest > 1)
              InfoRow('ประหยัดกว่าแบบที่ไหว', fmtMoney(other.totalInterest - plan.totalInterest), valueColor: cs.positive),
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
          Container(width: 16, height: 3, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
