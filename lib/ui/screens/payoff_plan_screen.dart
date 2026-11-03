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

/// "If I put X a month toward my debts, when am I debt-free?" — every
/// balance at once, money above what is due going to the most expensive
/// first. Two monthly totals can be compared: what is comfortable and the
/// most one can.
class PayoffPlanScreen extends ConsumerStatefulWidget {
  const PayoffPlanScreen({super.key});

  @override
  ConsumerState<PayoffPlanScreen> createState() => _PayoffPlanScreenState();
}

class _PayoffPlanScreenState extends ConsumerState<PayoffPlanScreen> {
  final _budget = TextEditingController();
  final _max = TextEditingController();
  bool _loaded = false;
  bool _loadedMax = false;

  @override
  void dispose() {
    _budget.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _setBudget(double v) async {
    setState(() {});
    await ref.read(settingsServiceProvider).setPayoffBudget(v);
    ref.invalidate(payoffBudgetProvider);
  }

  Future<void> _setMax(double v) async {
    setState(() {});
    await ref.read(settingsServiceProvider).setPayoffBudgetMax(v);
    ref.invalidate(payoffBudgetMaxProvider);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(payoffBudgetProvider).value;
    if (!_loaded && saved != null) {
      _loaded = true;
      if (saved > 0) _budget.text = amountToField(saved);
    }
    final savedMax = ref.watch(payoffBudgetMaxProvider).value;
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
          final budget = parseAmount(_budget.text) ?? 0;
          final most = parseAmount(_max.text) ?? 0;
          final base = PayoffPlanner.baseline(debts, start: s.today);
          final due = base.firstMonthPayment;
          // Nothing typed yet: keep paying what is due now.
          final plan = budget > 0
              ? PayoffPlanner.planWithin(debts, start: s.today, budget: budget)
              : PayoffPlanner.plan(debts, start: s.today, extra: 0);
          final showMost = most > 0.005 && most > budget + 0.005;
          final stretch = showMost ? PayoffPlanner.planWithin(debts, start: s.today, budget: most) : null;

          // The scenario the chart and the order follow: the comfortable one
          // when it covers what is due, else the all-out one, else minimums.
          final lead = plan ?? stretch ?? base;
          final leadLabel = plan != null
              ? (stretch != null ? 'แบบที่ไหว' : 'ตามแผน')
              : stretch != null
                  ? 'แบบเต็มที่'
                  : 'จ่ายแค่ขั้นต่ำและค่างวด';
          final leadExtra = identical(lead, plan)
              ? budget - due
              : identical(lead, stretch)
                  ? most - due
                  : 0.0;
          final second = plan != null ? stretch : null;
          // Same color as the card it follows.
          final leadColor = identical(lead, stretch) ? cs.tertiary : cs.primary;
          final order = [...debts]..sort((a, b) =>
              (lead.paidOff[a.id] ?? 1 << 20).compareTo(lead.paidOff[b.id] ?? 1 << 20));
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
                        controller: _budget,
                        label: 'จ่ายไหว/เดือน',
                        onChanged: (v) => _setBudget(parseAmount(v) ?? 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AmountField(
                        controller: _max,
                        label: 'เต็มที่/เดือน',
                        onChanged: (v) => _setMax(parseAmount(v) ?? 0),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 16, 0),
                child: Text(
                  'เงินทั้งหมดที่เอามาจ่ายหนี้ได้ต่อเดือน รวมขั้นต่ำบัตรและค่างวดแล้ว · '
                  'ใส่ช่องเต็มที่ไว้เทียบว่าถ้าจ่ายสุดตัวจะหมดเร็วขึ้นแค่ไหน',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: InfoRow('ขั้นต่ำบัตร + ค่างวด ประมาณ', '${fmtMoney(due)}/เดือน'),
              ),
              _ResultCard(
                title: showMost ? 'แบบที่ไหว' : null,
                today: s.today,
                budget: budget > 0 ? budget : due,
                due: due,
                plan: plan,
                base: base,
              ),
              if (showMost)
                _ResultCard(
                  title: 'แบบเต็มที่',
                  today: s.today,
                  budget: most,
                  due: due,
                  plan: stretch,
                  base: base,
                  comparedTo: plan,
                  allOut: true,
                ),
              const SectionHeader('ยอดหนี้รวมลดลงแบบนี้'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DebtChart(
                  plan: lead.balances,
                  baseline: base.balances,
                  stretch: second?.balances,
                  planColor: leadColor,
                  start: s.today,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 16,
                  children: [
                    _Legend(color: leadColor, label: leadLabel),
                    if (second != null) _Legend(color: cs.tertiary, label: 'แบบเต็มที่'),
                    if (!identical(lead, base)) _Legend(color: cs.outline, label: 'จ่ายแค่ขั้นต่ำและค่างวด'),
                  ],
                ),
              ),
              SectionHeader(identical(lead, plan) && second == null ? 'ลำดับที่จะหมด' : 'ลำดับที่จะหมด ($leadLabel)'),
              for (final (i, d) in order.indexed)
                ListTile(
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: t.labelMedium)),
                  title: Text(d.name),
                  subtitle: Text([
                    lead.paidOff[d.id] == null
                        ? 'ยังไม่หมด'
                        : 'หมด ${fmtMonthYear(addMonths(s.today, lead.paidOff[d.id]!))}',
                    'ดอก ${fmtRate(d.annualRate)}/ปี',
                    if (d.lockedUntil != null && s.today.isBefore(d.lockedUntil!))
                      'โปะได้ตั้งแต่ ${fmtDate(d.lockedUntil!)}',
                    if (leadExtra > 0.005 && identical(d, target)) 'โปะอันนี้ก่อน',
                  ].join(' · ')),
                  trailing: Text(fmtMoney(d.balance)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'เป็นการประมาณ: บัตรคิดขั้นต่ำตามสัดส่วนในบิลล่าสุด (ถ้าไม่มีใช้ 8% สำหรับบัตรเครดิต 5% สำหรับบัตรอื่น) '
                  'ยังไม่รวมการใช้จ่ายใหม่และค่าปรับปิดก่อนกำหนด เงินที่เกินขั้นต่ำจะไปลงหนี้ที่ดอกแพงสุดก่อน '
                  'พอหนี้ไหนหมด เงินที่เคยจ่ายก้อนนั้นจะไปโปะก้อนถัดไปต่อ '
                  'ขั้นต่ำต่อเดือนนับทุกบัตรและทุกค่างวดของเดือนปกติ จึงอาจไม่เท่ากับ "ต้องจ่ายเดือนนี้" ในหน้าภาพรวม '
                  'ที่นับเฉพาะบิลที่ครบกำหนดในเดือนนี้',
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
    required this.budget,
    required this.due,
    required this.plan,
    required this.base,
    this.comparedTo,
    this.allOut = false,
  });

  /// 'แบบที่ไหว' / 'แบบเต็มที่' when two cards are compared.
  final String? title;
  final DateTime today;

  /// Paid toward debts every month, all included.
  final double budget;

  /// Card minimums plus installments this month.
  final double due;

  /// Null when [budget] does not cover [due].
  final PayoffResult? plan;
  final PayoffResult base;

  /// The comfortable plan, when this card is the all-out one.
  final PayoffResult? comparedTo;
  final bool allOut;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final plan = this.plan;
    final bg = allOut ? cs.tertiaryContainer : cs.primaryContainer;
    final fg = allOut ? cs.onTertiaryContainer : cs.onPrimaryContainer;
    final heading = title == null ? '' : '$title · ';
    return Card(
      color: bg,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: plan == null ? _short(t, cs, fg, heading) : _done(t, cs, fg, heading, plan),
      ),
    );
  }

  Widget _short(TextTheme t, ColorScheme cs, Color fg, String heading) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$heading${fmtMoney(budget)}/เดือน', style: t.labelLarge?.copyWith(color: fg)),
          Text('ยังไม่พอจ่ายขั้นต่ำ',
              style: t.headlineSmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold)),
          Text(
            'ขั้นต่ำบัตรและค่างวดรวมประมาณ ${fmtMoney(due)}/เดือน ขาดอีก ${fmtMoney(due - budget)} '
            'ถ้าจ่ายไม่ถึงขั้นต่ำ จะโดนค่าปรับและดอกผิดนัด',
            style: t.bodyMedium?.copyWith(color: fg),
          ),
          if (base.months != null) ...[
            const Divider(height: 24),
            InfoRow('ถ้าจ่ายครบขั้นต่ำทุกเดือน', 'หมด ${fmtMonthYear(addMonths(today, base.months!))}'),
          ],
        ],
      );

  Widget _done(TextTheme t, ColorScheme cs, Color fg, String heading, PayoffResult plan) {
    final months = plan.months;
    final sooner = months != null && base.months != null ? base.months! - months : null;
    final other = comparedTo;
    final soonerThanEasy = other?.months != null && months != null ? other!.months! - months : null;
    final extra = budget - due;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$headingปลดหนี้หมด', style: t.labelLarge?.copyWith(color: fg)),
        Text(
          months == null ? 'ยังไม่หมด' : fmtMonthYear(addMonths(today, months)),
          style: t.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.bold),
        ),
        Text(
          months == null
              ? 'จ่ายเท่านี้ดอกเบี้ยกินหมด หนี้ไม่ลด ลองเพิ่มเงินที่จ่ายต่อเดือน'
              : [
                  'อีก ${fmtMonths(months)}',
                  if (other != null && soonerThanEasy != null && soonerThanEasy > 0)
                    'เร็วกว่าแบบที่ไหว ${fmtMonths(soonerThanEasy)}'
                  else if (other != null && soonerThanEasy == 0)
                    'หมดเดือนเดียวกับแบบที่ไหว แต่ดอกน้อยกว่า'
                  else if (sooner != null && sooner > 0)
                    'เร็วกว่าจ่ายแค่ขั้นต่ำ ${fmtMonths(sooner)}',
                  if (other == null && base.months == null) 'ถ้าจ่ายแค่ขั้นต่ำ หนี้จะไม่หมด',
                ].join(' · '),
          style: t.bodyMedium?.copyWith(color: fg),
        ),
        const Divider(height: 24),
        InfoRow('จ่ายทุกเดือน', fmtMoney(plan.firstMonthPayment), bold: true),
        Text(
          extra > 0.005
              ? 'ขั้นต่ำบัตรและค่างวด ${fmtMoney(due)} + โปะ ${fmtMoney(extra)} '
                  'หนี้ก้อนไหนหมด เงินก้อนนั้นไปโปะก้อนถัดไป'
              : 'ขั้นต่ำบัตรและค่างวดทุกรายการ หนี้ก้อนไหนหมด เงินก้อนนั้นไปโปะก้อนถัดไป',
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
