import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../data/services/ledger_service.dart';
import '../../domain/finance/loan_math.dart';
import '../../domain/finance/loan_state.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/installment_plan.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({super.key, required this.account, this.existing});
  final AccountSummary account;
  final InstallmentPlan? existing;

  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  final _form = GlobalKey<FormState>();
  late final InstallmentPlan? _orig = widget.existing;
  late final _name = TextEditingController(text: _orig?.name ?? '');
  late final _principal = TextEditingController(text: amountToField(_orig?.principal));
  late final _rate = TextEditingController(text: _orig == null ? '' : '${_orig.annualRate}');
  late final _term = TextEditingController(text: _orig == null ? '' : '${_orig.termMonths}');
  late final _override = TextEditingController(text: amountToField(_orig?.monthlyPaymentOverride));
  late final _paidBefore = TextEditingController(text: '${_orig?.paidBeforeTracking ?? 0}');
  // Card-billed: installments on the card now (billed or waiting for the next bill).
  late final int _postedNow = _orig == null
      ? 0
      : widget.account.plans.where((s) => s.plan.id == _orig.id).firstOrNull?.paidInstallments ?? _orig.paidBeforeTracking;
  late final _posted = TextEditingController(text: '$_postedNow');
  late final _lockIn = TextEditingController(text: '${_orig?.lockInMonths ?? 0}');
  late final _penaltyPct = TextEditingController(text: _orig == null || _orig.penaltyPercent == 0 ? '' : '${_orig.penaltyPercent}');
  late final _penaltyFixed = TextEditingController(text: amountToField(_orig?.penaltyFixed == 0 ? null : _orig?.penaltyFixed));
  late final _note = TextEditingController(text: _orig?.note ?? '');
  late InterestMethod _method = _orig?.interestMethod ?? InterestMethod.reducing;
  late bool _useOverride = _orig?.monthlyPaymentOverride != null;
  late bool _included = _orig?.includedInStatement ??
      const {AccountType.creditCard, AccountType.cashCard}.contains(widget.account.account.type);
  // Asked for only when the card has no cutoff day yet.
  late int? _billingDay = widget.account.account.billingDay;
  late String? _lineId = _orig?.creditLineId ?? (widget.account.lines.isEmpty ? null : widget.account.lines.first.id);
  late DateTime _start = _orig?.startDate ?? _defaultStart();
  // Installments of this plan already logged as payments in the app.
  late final int _recorded = _orig == null
      ? 0
      : widget.account.payments
          .where((p) => p.planId == _orig.id && const {PaymentType.installment, PaymentType.minimum, PaymentType.other}.contains(p.type))
          .length;

  DateTime _defaultStart() {
    final dd = widget.account.account.dueDay;
    final today = dateOnly(DateTime.now());
    return dd == null ? addMonths(today, 1) : nextDayAfter(dd, today);
  }

  @override
  void dispose() {
    for (final c in [_name, _principal, _rate, _term, _override, _paidBefore, _posted, _lockIn, _penaltyPct, _penaltyFixed, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  InstallmentPlan? _draft() {
    final principal = parseAmount(_principal.text);
    final term = int.tryParse(_term.text);
    if (principal == null || principal <= 0 || term == null || term <= 0) return null;
    var start = _start;
    var paidBefore = int.tryParse(_paidBefore.text) ?? 0;
    int? anchorDay;
    int? postedThrough;
    final day = _billingDay;
    if (_included && day != null) {
      final posted = int.tryParse(_posted.text) ?? 0;
      final o = _orig;
      if (o != null && o.includedInStatement && o.postedThrough != null && posted == _postedNow) {
        (start, paidBefore, anchorDay, postedThrough) = (o.startDate, o.paidBeforeTracking, o.anchorDay, o.postedThrough);
      } else {
        // The next installment goes on the card at the next cutoff.
        start = InstallmentPlan.firstCutoff(billingDay: day, posted: posted, today: DateTime.now());
        (paidBefore, anchorDay, postedThrough) = (posted, day, posted);
      }
    }
    return InstallmentPlan(
      id: _orig?.id ?? newId(),
      accountId: widget.account.account.id,
      creditLineId: _lineId,
      name: _name.text.trim(),
      principal: principal,
      annualRate: parseAmount(_rate.text) ?? 0,
      interestMethod: _method,
      termMonths: term,
      monthlyPaymentOverride: _useOverride ? parseAmount(_override.text) : null,
      startDate: start,
      lockInMonths: int.tryParse(_lockIn.text) ?? 0,
      penaltyPercent: parseAmount(_penaltyPct.text) ?? 0,
      penaltyFixed: parseAmount(_penaltyFixed.text) ?? 0,
      includedInStatement: _included,
      paidBeforeTracking: paidBefore,
      anchorDay: anchorDay,
      postedThrough: postedThrough,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: _orig?.createdAt ?? DateTime.now(),
    );
  }

  /// Enough of a draft to lay out due dates while เงินต้น is still empty.
  InstallmentPlan? _draftDates() {
    final term = int.tryParse(_term.text);
    if (term == null || term <= 0) return null;
    return InstallmentPlan(
      id: '',
      accountId: widget.account.account.id,
      name: '',
      principal: 1,
      annualRate: 0,
      interestMethod: _method,
      termMonths: term,
      startDate: _start,
      paidBeforeTracking: int.tryParse(_paidBefore.text) ?? 0,
      createdAt: DateTime.now(),
    );
  }

  bool get _canFillPrincipal =>
      (parseAmount(_override.text) ?? 0) > 0 && parseAmount(_rate.text) != null && (int.tryParse(_term.text) ?? 0) > 0;

  /// Fills เงินต้นตั้งต้น from the bank's installment, rate and term.
  void _fillPrincipal() {
    final principal = LoanMath.round2(LoanMath.principalForPayment(
      parseAmount(_override.text)!,
      parseAmount(_rate.text)!,
      int.parse(_term.text),
      flat: _method == InterestMethod.flat,
    ));
    setState(() => _principal.text = amountToField(principal));
    showSnack(context, 'ใส่เงินต้นประมาณ ${fmtMoney(principal)} แล้ว ถ้ารู้ยอดที่ได้รับจริง แก้เป็นยอดนั้นได้');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final plan = _draft();
    if (plan == null) return;
    final ledger = ref.read(ledgerProvider);
    if (_included && widget.account.account.billingDay == null) {
      await ledger.setBillingDay(widget.account.account.id, _billingDay!);
    }
    await ledger.savePlan(plan);
    ref.refreshData();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.account.lines;
    return Scaffold(
      appBar: AppBar(title: Text(_orig == null ? 'เพิ่มรายการผ่อน' : 'แก้ไขรายการผ่อน')),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.account.account.name, style: Theme.of(context).textTheme.titleMedium),
            formGap,
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'ชื่อรายการ', hintText: 'เช่น ผ่อน iPhone, สินเชื่อก้อน 100,000'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
            ),
            formGap,
            if (lines.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                initialValue: _lineId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ใช้วงเงินย่อย', helperText: 'ยอดผ่อนคงเหลือจะนับเป็นวงเงินที่ใช้ไปของวงเงินนี้'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('ไม่ผูกกับวงเงิน')),
                  for (final l in lines) DropdownMenuItem(value: l.id, child: Text(l.name)),
                ],
                onChanged: (v) => setState(() => _lineId = v),
              ),
              formGap,
            ],
            AmountField(
              controller: _principal,
              label: 'เงินต้นตั้งต้น',
              helper: 'ยอดที่ได้ตอนเริ่มผ่อน ไม่รู้ก็ได้ ใส่ค่าผ่อนต่อเดือนด้านล่างแล้วให้แอพคำนวณ',
              required: true,
              allowZero: false,
            ),
            formGap,
            Row(
              children: [
                Expanded(child: AmountField(controller: _rate, label: 'ดอกเบี้ยต่อปี', suffix: '%', helper: 'ผ่อน 0% ใส่ 0')),
                const SizedBox(width: 12),
                Expanded(child: IntField(controller: _term, label: 'จำนวนงวด', suffix: 'เดือน', min: 1, max: 600)),
              ],
            ),
            formGap,
            SegmentedButton<InterestMethod>(
              segments: [for (final m in InterestMethod.values) ButtonSegment(value: m, label: Text(m.label))],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ธนาคารกำหนดค่าผ่อนต่อเดือนมาแล้ว'),
              subtitle: const Text('ถ้าปิดไว้ แอพจะคำนวณให้จากเงินต้น ดอกเบี้ย และจำนวนงวด'),
              value: _useOverride,
              onChanged: (v) => setState(() => _useOverride = v),
            ),
            if (_useOverride) ...[
              AmountField(controller: _override, label: 'ค่าผ่อนต่อเดือน', required: true, allowZero: false),
              if (_canFillPrincipal)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('ไม่รู้เงินต้น? คำนวณจากค่าผ่อนนี้'),
                    onPressed: _fillPrincipal,
                  ),
                ),
              formGap,
            ],
            _Preview(plan: _draft()),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ค่างวดรวมอยู่ในยอดเรียกเก็บของบัตรแล้ว'),
              subtitle: Text('เปิดสำหรับรายการผ่อนที่ขึ้นในยอดของบัตร: แอพบวกค่างวดเข้า'
                  '${widget.account.account.type.revolvingLabel}ทุกวันตัดรอบ และไม่นับซ้ำในยอดต้องจ่ายเดือนนี้'),
              value: _included,
              onChanged: (v) => setState(() => _included = v),
            ),
            if (_included) ...[
              if (widget.account.account.billingDay == null) ...[
                DayOfMonthField(
                  value: _billingDay,
                  label: 'วันตัดรอบบิลของบัตร',
                  helper: 'ค่างวดจะขึ้นในบัตรวันนี้ของทุกเดือน บันทึกไว้ที่บัตรด้วย',
                  validator: (v) => v == null ? 'กรุณาเลือกวันตัดรอบ' : null,
                  onChanged: (v) => setState(() => _billingDay = v),
                ),
                formGap,
              ],
              IntField(
                controller: _posted,
                label: 'บัตรแจ้งถึงงวดที่',
                helper: 'นับงวดที่ขึ้นในบัตรแล้ว ทั้งที่เรียกเก็บไปแล้วและที่รอเรียกเก็บ (ยังไม่มีใส่ 0)'
                    '${_billingDay == null ? '' : ' · งวดถัดไปแอพจะบวกเข้า${widget.account.account.type.revolvingLabel}'
                        'วันตัดรอบ ${fmtDate(nextDayAfter(_billingDay!, DateTime.now()))}'}',
                max: int.tryParse(_term.text) ?? 600,
              ),
            ] else ...[
              DateField(
                value: _start,
                label: 'วันครบกำหนดงวดแรก',
                onChanged: (d) => setState(() => _start = d ?? _start),
              ),
              formGap,
              IntField(
                controller: _paidBefore,
                label: 'จ่ายไปแล้วกี่งวด (ก่อนเริ่มใช้แอพ)',
                helper: 'งวดเหล่านี้จะถือว่าจ่ายครบตามตาราง ไม่ต้องนับงวดที่บันทึกการจ่ายในแอพแล้ว',
                max: 600,
              ),
              _PaidCheck(
                plan: _draft() ?? _draftDates(),
                recorded: _recorded,
                onUse: (n) => setState(() => _paidBefore.text = '$n'),
              ),
            ],
            SectionHeader('เงื่อนไขปิดก่อนกำหนด'),
            IntField(controller: _lockIn, label: 'ห้ามปิดก่อนกำหนด (lock-in)', suffix: 'เดือน', helper: '0 = ไม่มี', max: 600),
            formGap,
            Row(
              children: [
                Expanded(child: AmountField(controller: _penaltyPct, label: 'ค่าปรับ % ของเงินต้นคงเหลือ', suffix: '%')),
                const SizedBox(width: 12),
                Expanded(child: AmountField(controller: _penaltyFixed, label: 'ค่าปรับคงที่')),
              ],
            ),
            formGap,
            TextFormField(controller: _note, maxLines: 2, decoration: const InputDecoration(labelText: 'โน้ต')),
            const SizedBox(height: 24),
            FilledButton(onPressed: _save, child: const Text('บันทึก')),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Live cost preview, including what the same headline rate would cost
/// with the other interest method.
class _Preview extends StatelessWidget {
  const _Preview({required this.plan});
  final InstallmentPlan? plan;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    if (p == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final s = LoanState.initial(
      method: p.interestMethod,
      principal: p.principal,
      annualRate: p.annualRate,
      termMonths: p.termMonths,
      paymentOverride: p.monthlyPaymentOverride,
    );
    final interest = s.projectedInterest;
    final effective = p.interestMethod == InterestMethod.flat
        ? LoanMath.effectiveAnnualRate(p.principal, s.payment, p.termMonths)
        : (p.monthlyPaymentOverride != null
            ? LoanMath.effectiveAnnualRate(p.principal, s.payment, p.termMonths)
            : p.annualRate);
    final otherInterest = p.interestMethod == InterestMethod.flat
        ? LoanMath.reducingTotalInterest(p.principal, p.annualRate, p.termMonths)
        : LoanMath.flatTotalInterest(p.principal, p.annualRate, p.termMonths);
    return Card(
      margin: EdgeInsets.zero,
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('สรุปค่าใช้จ่าย', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            InfoRow('ค่าผ่อนต่อเดือน', fmtMoney(s.payment), bold: true),
            InfoRow('ดอกเบี้ยรวมทั้งสัญญา', fmtMoney(interest), valueColor: cs.error),
            InfoRow('ยอดชำระรวม', fmtMoney(p.principal + interest)),
            InfoRow('ดอกเบี้ยจริงต่อปี (เทียบแบบลดต้นลดดอก)', '${fmtPercent(effective)}/ปี', bold: true),
            if (p.annualRate > 0 && p.monthlyPaymentOverride == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  p.interestMethod == InterestMethod.flat
                      ? 'ถ้าอัตรา ${fmtPercent(p.annualRate)} เดียวกันเป็นแบบลดต้นลดดอก ดอกรวมจะเหลือ ${fmtMoney(otherInterest)} '
                          '(flat แพงกว่า ${fmtMoney(interest - otherInterest)})'
                      : 'ถ้าเป็นแบบ flat rate ที่อัตราเดียวกัน ดอกรวมจะเป็น ${fmtMoney(otherInterest)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Says which installments the app will count as paid, and warns when that
/// runs past what is due by today or misses installments already due.
class _PaidCheck extends StatelessWidget {
  const _PaidCheck({required this.plan, required this.recorded, required this.onUse});
  final InstallmentPlan? plan;

  /// Installments already logged as payments; they count after [plan]'s
  /// paid-before ones.
  final int recorded;
  final ValueChanged<int> onUse;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    if (p == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final before = math.min(p.paidBeforeTracking, p.termMonths);
    final total = math.min(before + recorded, p.termMonths);
    final due = p.dueCountBy(DateTime.now());
    final fix = math.max(0, due - recorded);
    final info = [
      if (before == 1) 'แอพจะติ๊กงวดที่ 1 ว่าจ่ายแล้ว (ครบกำหนด ${fmtDate(p.dueDateOf(1))})',
      if (before > 1) 'แอพจะติ๊กงวด 1–$before ว่าจ่ายแล้ว (งวดที่ $before ครบกำหนด ${fmtDate(p.dueDateOf(before))})',
      if (recorded > 0) 'บวกค่างวดที่บันทึกในแอพแล้ว $recorded ครั้ง รวมจ่ายแล้ว $total งวด',
      'ถึงวันนี้ครบกำหนดแล้ว $due งวด',
    ];
    final warning = total > due
        ? 'นับว่าจ่ายแล้วเกินงวดที่ครบกำหนด ${total - due} งวด'
            '${recorded > 0 ? ' ถ้าค่างวดที่บันทึกในแอพเป็นงวดเดียวกับที่ใส่ตรงนี้' : ' ถ้ายังไม่ได้จ่ายล่วงหน้า'} ให้ใส่ $fix'
        : total < due
            ? 'อีก ${due - total} งวดที่ครบกำหนดแล้วจะขึ้นว่าเลยกำหนด ถ้าจ่ายไปแล้วให้ใส่ $fix'
            : null;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.join('\n'), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (warning != null)
            Row(
              children: [
                Icon(Icons.warning_amber, size: 18, color: cs.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(warning, style: t.bodySmall?.copyWith(color: cs.warning))),
                if (fix != p.paidBeforeTracking) TextButton(onPressed: () => onUse(fix), child: Text('ใส่ $fix')),
              ],
            ),
        ],
      ),
    );
  }
}
