import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/installment_engine.dart';
import '../../domain/finance/loan_math.dart';
import '../../domain/finance/loan_state.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/finance/prepayment.dart';
import '../../domain/models/enums.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'payment_form_screen.dart';
import 'payoff_plan_screen.dart';
import '../widgets/app_icons.dart';

/// "If I prepay X, how much interest do I save?" — reduce the installment
/// vs keep it and finish sooner.
class CalculatorScreen extends ConsumerStatefulWidget {
  const CalculatorScreen({super.key, this.initialPlanId});
  final String? initialPlanId;

  @override
  ConsumerState<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends ConsumerState<CalculatorScreen> {
  late bool _fromPlan = true;
  String? _planId;
  final _extra = TextEditingController();
  final _balance = TextEditingController();
  final _rate = TextEditingController();
  final _months = TextEditingController();
  final _payment = TextEditingController();
  InterestMethod _method = InterestMethod.reducing;

  @override
  void initState() {
    super.initState();
    _planId = widget.initialPlanId;
  }

  @override
  void dispose() {
    for (final c in [_extra, _balance, _rate, _months, _payment]) {
      c.dispose();
    }
    super.dispose();
  }

  List<(AccountSummary, InstallmentState)> _plans(PortfolioSummary s) => [
        for (final a in s.accounts)
          for (final p in a.activePlans) (a, p),
      ];

  LoanState? _manualState() {
    final b = parseAmount(_balance.text);
    final n = int.tryParse(_months.text);
    final r = parseAmount(_rate.text) ?? 0;
    if (b == null || b <= 0 || n == null || n <= 0) return null;
    final pay = parseAmount(_payment.text);
    return LoanState.initial(
      method: _method,
      principal: b,
      annualRate: r,
      termMonths: n,
      paymentOverride: pay != null && pay > 0 ? pay : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    final isPushed = Navigator.canPop(context);
    return Scaffold(
      appBar: AppBar(title: const Text('คำนวณผลการโปะ'), automaticallyImplyLeading: isPushed),
      body: AsyncBody(
        value: portfolio,
        builder: (s) {
          final plans = _plans(s);
          if (plans.isEmpty) _fromPlan = false;
          if (_fromPlan && (_planId == null || !plans.any((e) => e.$2.plan.id == _planId))) {
            _planId = plans.first.$2.plan.id;
          }
          final selected = _fromPlan ? plans.firstWhere((e) => e.$2.plan.id == _planId) : null;
          final state = selected?.$2.current ?? _manualState();
          final typed = parseAmount(_extra.text) ?? 0;
          // More than is owed only pays it off; the rest is not needed.
          final over = state != null && typed > state.balance + 0.005;
          final extra = over ? LoanMath.round2(state.balance) : typed;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const GlyphIcon(Glyph.debtFree),
                  title: const Text('แผนปลดหนี้ทั้งหมด'),
                  subtitle: const Text('จ่ายหนี้ได้เดือนละเท่าไร หนี้ทุกก้อนจะหมดเมื่อไร'),
                  trailing: const GlyphIcon(Glyph.next),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoffPlanScreen())),
                ),
              ),
              formGap,
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: const Text('จากรายการผ่อน'), enabled: plans.isNotEmpty),
                  const ButtonSegment(value: false, label: Text('กรอกเอง')),
                ],
                selected: {_fromPlan},
                onSelectionChanged: (v) => setState(() => _fromPlan = v.first),
              ),
              formGap,
              if (_fromPlan)
                DropdownButtonFormField<String>(
                  initialValue: _planId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'รายการผ่อน'),
                  items: [
                    for (final (a, p) in plans)
                      DropdownMenuItem(value: p.plan.id, child: Text('${a.account.name} · ${p.plan.name}')),
                  ],
                  onChanged: (v) => setState(() => _planId = v),
                )
              else
                ..._manualFields(),
              // Always one slot, so fields below keep their element (and
              // focus) when the card appears while typing.
              Padding(
                padding: EdgeInsets.only(top: state == null ? 0 : 14),
                child: state == null ? const SizedBox.shrink() : _CurrentCard(state: state, plan: selected?.$2),
              ),
              formGap,
              AmountField(
                controller: _extra,
                label: 'จำนวนเงินที่จะโปะเพิ่ม',
                onChanged: (_) => setState(() {}),
              ),
              if (over)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'เงินต้นคงเหลือแค่ ${fmtMoney(state.balance)} โปะเท่านี้ก็ปิดยอดได้ ส่วนที่เกินไม่ต้องจ่าย',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.warning),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (label, v) in _quickAmounts(state))
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() => _extra.text = amountToField(v)),
                    ),
                ],
              ),
              if (state != null && extra > 0) ...[
                formGap,
                _Results(
                  comparison: PrepaymentComparison.compute(
                    state,
                    extra,
                    penalty: _penalty(selected?.$2, state, extra),
                  ),
                  plan: selected?.$2,
                  accountId: selected?.$1.account.id,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Round amounts under what is owed (the three largest), then paying it
  /// all off, so a ฿7,000 loan never offers ฿20,000.
  List<(String, double)> _quickAmounts(LoanState? s) {
    const steps = [1000.0, 2000.0, 5000.0, 10000.0, 20000.0, 50000.0, 100000.0];
    if (s == null || s.isClosed) return [for (final v in const [5000.0, 10000.0, 20000.0]) (fmtMoneyCompact(v), v)];
    final below = steps.where((v) => v < s.balance - 0.005).toList();
    return [
      for (final v in below.skip(math.max(0, below.length - 3))) (fmtMoneyCompact(v), v),
      ('ปิดยอด ${fmtMoney(s.balance)}', LoanMath.round2(s.balance)),
    ];
  }

  /// Penalty only applies when the prepayment closes the plan early.
  double _penalty(InstallmentState? p, LoanState state, double extra) {
    if (p == null || extra < state.balance - 0.005) return 0;
    return p.earlyClosurePenalty;
  }

  List<Widget> _manualFields() => [
        AmountField(controller: _balance, label: 'เงินต้นคงเหลือ', onChanged: (_) => setState(() {})),
        formGap,
        Row(
          children: [
            Expanded(
              child: AmountField(controller: _rate, label: 'ดอกเบี้ยต่อปี', suffix: '%', onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: IntField(controller: _months, label: 'งวดคงเหลือ', suffix: 'เดือน', min: 1, max: 600,
                  onChanged: (_) => setState(() {})),
            ),
          ],
        ),
        formGap,
        SegmentedButton<InterestMethod>(
          segments: [for (final m in InterestMethod.values) ButtonSegment(value: m, label: Text(m.label))],
          selected: {_method},
          onSelectionChanged: (v) => setState(() => _method = v.first),
        ),
        formGap,
        AmountField(
          controller: _payment,
          label: 'ค่าผ่อนต่อเดือน (ถ้าทราบ)',
          helper: 'เว้นว่างให้แอพคำนวณจากสูตร amortization',
          onChanged: (_) => setState(() {}),
        ),
      ];
}

class _CurrentCard extends StatelessWidget {
  const _CurrentCard({required this.state, this.plan});
  final LoanState state;
  final InstallmentState? plan;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = plan;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ถ้าไม่โปะ', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            InfoRow('เงินต้นคงเหลือ', fmtMoney(state.balance), bold: true),
            InfoRow('ค่าผ่อน/เดือน', fmtMoney(state.payment)),
            InfoRow('งวดคงเหลือ', fmtMonths(p?.remainingInstallments ?? state.projectedMonths)),
            InfoRow('ดอกเบี้ยที่ต้องจ่ายอีก', fmtMoney(p?.projectedRemainingInterest ?? state.projectedInterest),
                valueColor: cs.error),
            if (state.method == InterestMethod.flat)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'ดอกเบี้ยแบบ flat: หลังโปะแอพจะคิดดอกใหม่จากเงินต้นคงเหลือ ซึ่งเป็นการประมาณ — เงื่อนไขจริงขึ้นกับธนาคาร',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.warning),
                ),
              ),
            if (p != null && p.isLockedOn(DateTime.now()))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'ติด lock-in ถึง ${fmtDate(p.earliestClosureDate!)} — อาจโปะ/ปิดก่อนกำหนดไม่ได้',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.comparison, this.plan, this.accountId});
  final PrepaymentComparison comparison;
  final InstallmentState? plan;
  final String? accountId;

  @override
  Widget build(BuildContext context) {
    final c = comparison;
    final best = c.bestForInterest.mode;
    final options = [c.reducePayment, c.reduceTerm];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 560;
      final cards = [
        for (final o in options)
          _OutcomeCard(
            outcome: o,
            comparison: c,
            isBest: o.mode == best,
            plan: plan,
            onRecord: plan == null || accountId == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentFormScreen(
                          accountId: accountId,
                          planId: plan!.plan.id,
                          type: PaymentType.extra,
                          amount: c.extra,
                          prepaymentMode: o.mode,
                        ),
                      ),
                    ),
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.penalty > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('รวมค่าปรับปิดก่อนกำหนด ${fmtMoney(c.penalty)} แล้ว'),
            ),
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final card in cards) Expanded(child: card)],
              ),
            )
          else
            ...cards,
        ],
      );
    });
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome, required this.comparison, required this.isBest, this.plan, this.onRecord});
  final PrepaymentOutcome outcome;
  final PrepaymentComparison comparison;
  final bool isBest;
  final InstallmentState? plan;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final o = outcome;
    DateTime? payoff;
    final p = plan;
    if (p != null && o.months > 0) {
      payoff = p.plan.dueDateOf(p.paidInstallments + o.months);
    } else if (o.months > 0) {
      payoff = addMonths(dateOnly(DateTime.now()), o.months);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isBest ? BorderSide(color: cs.positive, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(o.mode.label, style: t.titleSmall)),
                if (isBest) Pill('ประหยัดดอกกว่า', color: cs.positive, icon: Glyph.best),
              ],
            ),
            const SizedBox(height: 8),
            Text('ประหยัดดอกเบี้ย', style: t.labelMedium),
            Text(fmtMoney(o.interestSaved), style: t.headlineSmall?.copyWith(color: cs.positive, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (o.after.isClosed)
              const InfoRow('สถานะ', 'ปิดยอดได้ทันที', bold: true)
            else ...[
              InfoRow('ค่าผ่อนใหม่/เดือน', fmtMoney(o.newPayment), bold: true),
              InfoRow('งวดคงเหลือ', '${o.months} (เร็วขึ้น ${o.monthsSaved})'),
              if (payoff != null) InfoRow('ปิดยอดประมาณ', fmtDate(payoff)),
            ],
            InfoRow('ดอกเบี้ยที่เหลือ', fmtMoney(o.remainingInterest)),
            InfoRow('จ่ายรวมทั้งหมดต่อจากนี้', fmtMoney(o.totalOutlay)),
            if (comparison.before.method == InterestMethod.reducing && o.mode == PrepaymentMode.reducePayment && !o.after.isClosed)
              Text(
                'ค่าผ่อนลดลง ${fmtMoney(comparison.before.payment - o.newPayment)}/เดือน',
                style: t.bodySmall,
              ),
            if (onRecord != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRecord, child: const Text('บันทึกการโปะแบบนี้')),
              ),
          ],
        ),
      ),
    );
  }
}
