import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../data/services/ledger_service.dart';
import '../../domain/finance/installment_engine.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/finance/prepayment.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import '../widgets/app_icons.dart';

/// Quick payment entry: date / account / target / amount / type. With
/// [existing] it corrects a recorded payment instead.
class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({
    super.key,
    this.accountId,
    this.planId,
    this.type,
    this.amount,
    this.prepaymentMode,
    this.existing,
  });

  final Payment? existing;
  final String? accountId;
  final String? planId;
  final PaymentType? type;
  final double? amount;
  final PrepaymentMode? prepaymentMode;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = dateOnly(DateTime.now());
  String? _accountId;

  /// `line:{id}` or `plan:{id}`.
  String? _target;
  PaymentType _type = PaymentType.minimum;
  PrepaymentMode _mode = PrepaymentMode.reduceTerm;
  bool _amountTouched = false;

  /// Whether the typed-in balance already has this (backdated) payment;
  /// null = guess from the dates.
  bool? _included;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _init(PortfolioSummary s) {
    if (_initialized) return;
    _initialized = true;
    final e = widget.existing;
    if (e != null) {
      _accountId = e.accountId;
      _target = e.planId != null
          ? 'plan:${e.planId}'
          : e.creditLineId != null
              ? 'line:${e.creditLineId}'
              : null;
      _type = e.type;
      _mode = e.prepaymentMode ?? PrepaymentMode.reduceTerm;
      _date = e.date;
      _amount.text = amountToField(e.amount);
      _amountTouched = true;
      _note.text = e.note ?? '';
      // Nothing was taken off the balance when it was recorded.
      if (e.planId == null && e.creditLineId != null) _included = e.lineBalanceApplied < 0.005;
      return;
    }
    final a = (widget.accountId != null ? s.byId(widget.accountId!) : null) ?? s.nextDue ?? s.accounts.first;
    _accountId = a.account.id;
    _target = widget.planId != null ? 'plan:${widget.planId}' : _defaultTarget(a);
    _mode = widget.prepaymentMode ?? PrepaymentMode.reduceTerm;
    _type = widget.type ?? _allowedTypes(a).first;
    if (widget.amount != null) {
      _amount.text = amountToField(widget.amount);
      _amountTouched = true;
    } else {
      _suggestAmount(a);
    }
  }

  /// [a] as it was before the edited payment: its amount is back on the
  /// balance and off the statement, so the preview does not count it twice.
  AccountSummary _withoutEdited(AccountSummary a) {
    final e = widget.existing;
    if (e == null || e.accountId != a.account.id) return a;
    return AccountSummary(
      account: a.account,
      lines: [
        for (final l in a.lines)
          l.id == e.creditLineId && e.planId == null ? l.copyWith(balance: l.balance + e.lineBalanceApplied) : l,
      ],
      plans: a.plans,
      payments: [for (final p in a.payments) if (p.id != e.id) p],
      spendings: a.spendings,
      recurring: a.recurring,
      today: a.today,
    );
  }

  String? _defaultTarget(AccountSummary a) {
    if (a.lines.isNotEmpty) return 'line:${a.lines.first.id}';
    final plans = a.activePlans;
    return plans.isEmpty ? null : 'plan:${plans.first.plan.id}';
  }

  InstallmentState? _plan(AccountSummary a) {
    if (_target == null || !_target!.startsWith('plan:')) return null;
    final id = _target!.substring(5);
    final e = widget.existing;
    for (final p in a.plans) {
      if (p.plan.id != id) continue;
      // The preview of an edited payment is against the plan without it.
      return e == null || e.planId != id
          ? p
          : InstallmentEngine.replay(p.plan, [for (final x in a.payments) if (x.id != e.id) x], asOf: DateTime.now());
    }
    return null;
  }

  /// A backdated payment may already be in a balance copied from the bank
  /// app, so ask.
  bool _askBalance(CreditLine? line) =>
      line != null && (line.mayCount(_date) || _date.isBefore(dateOnly(DateTime.now())));

  /// The balance already has this payment, so it should not be taken off again.
  bool _skipBalance(CreditLine? line) => _askBalance(line) && (_included ?? line!.alreadyCounts(_date));

  CreditLine? _line(AccountSummary a) {
    if (_target == null || !_target!.startsWith('line:')) return null;
    final id = _target!.substring(5);
    for (final l in a.lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  List<PaymentType> _allowedTypes(AccountSummary a) {
    final plan = _plan(a);
    if (plan == null) {
      return [PaymentType.minimum, PaymentType.full, PaymentType.extra, PaymentType.other];
    }
    return [
      if (!plan.plan.includedInStatement) PaymentType.installment,
      PaymentType.extra,
      PaymentType.full,
    ];
  }

  void _suggestAmount(AccountSummary a) {
    if (_amountTouched) return;
    final plan = _plan(a);
    final line = _line(a);
    double? v;
    switch (_type) {
      case PaymentType.minimum:
        v = a.minimumOutstanding > 0 ? a.minimumOutstanding : null;
      case PaymentType.full:
        v = plan != null
            ? plan.payoffAmount
            : (a.statementOutstanding > 0 ? a.statementOutstanding : line?.balance);
      case PaymentType.installment:
        v = plan?.nextRow?.payment;
      case PaymentType.extra:
      case PaymentType.other:
        v = null;
    }
    _amount.text = v == null || v <= 0 ? '' : amountToField(double.parse(v.toStringAsFixed(2)));
  }

  Future<void> _save(AccountSummary a) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final plan = _plan(a);
    final line = _line(a);
    final skip = _skipBalance(line);
    final e = widget.existing;
    final payment = Payment(
      id: e?.id ?? newId(),
      accountId: a.account.id,
      creditLineId: line?.id ?? plan?.plan.creditLineId,
      planId: plan?.plan.id,
      date: _date,
      amount: parseAmount(_amount.text)!,
      type: _type,
      prepaymentMode: _type == PaymentType.extra && plan != null ? _mode : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      source: e?.source ?? PaymentSource.manual,
      createdAt: e?.createdAt ?? DateTime.now(),
    );
    final ledger = ref.read(ledgerProvider);
    if (e == null) {
      await ledger.recordPayment(payment, alreadyInBalance: skip);
    } else {
      await ledger.updatePayment(payment, alreadyInBalance: skip);
    }
    ref.refreshData();
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(
      context,
      '${e == null ? 'บันทึกการจ่าย' : 'แก้ไขการจ่าย'} ${fmtMoney(payment.amount)} แล้ว'
      '${skip ? ' · ${a.account.type.revolvingLabel}หักการจ่ายนี้อยู่แล้ว ไม่หักซ้ำ' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'บันทึกการจ่ายเงิน' : 'แก้ไขการจ่าย')),
      body: AsyncBody(
        value: portfolio,
        builder: (s) {
          if (s.isEmpty) return const EmptyState(icon: Glyph.noCards, title: 'ยังไม่มีบัตร/สินเชื่อ');
          _init(s);
          final a = _withoutEdited(s.byId(_accountId!) ?? s.accounts.first);
          // An edited payment keeps its type even where it is no longer offered.
          final types = {..._allowedTypes(a), if (_type == widget.existing?.type) _type}.toList();
          if (!types.contains(_type)) _type = types.first;
          final plan = _plan(a);
          final line = _line(a);
          final amount = parseAmount(_amount.text) ?? 0;
          return Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DateField(
                  value: _date,
                  label: 'วันที่จ่าย',
                  onChanged: (d) => setState(() {
                    _date = d ?? _date;
                    _included = null;
                  }),
                ),
                formGap,
                DropdownButtonFormField<String>(
                  initialValue: a.account.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'จ่ายให้บัตร/สินเชื่อ'),
                  items: [
                    for (final x in s.accounts) DropdownMenuItem(value: x.account.id, child: Text(x.account.name)),
                  ],
                  onChanged: (v) => setState(() {
                    _accountId = v;
                    final next = s.byId(v!)!;
                    _target = _defaultTarget(next);
                    _type = _allowedTypes(next).first;
                    _included = null;
                    _amountTouched = false;
                    _suggestAmount(next);
                  }),
                ),
                formGap,
                DropdownButtonFormField<String?>(
                  key: ValueKey('target-${a.account.id}'),
                  initialValue: _target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'จ่ายเข้า'),
                  items: [
                    for (final l in a.lines)
                      DropdownMenuItem(value: 'line:${l.id}', child: Text('${l.name} (คงค้าง ${fmtMoney(l.balance)})')),
                    for (final p in a.plans)
                      if (!p.isClosed || 'plan:${p.plan.id}' == _target)
                        DropdownMenuItem(value: 'plan:${p.plan.id}', child: Text('ผ่อน: ${p.plan.name}')),
                  ],
                  onChanged: (v) => setState(() {
                    _target = v;
                    _type = _allowedTypes(a).first;
                    _included = null;
                    _amountTouched = false;
                    _suggestAmount(a);
                  }),
                ),
                if (line != null && _askBalance(line))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _skipBalance(line),
                    onChanged: (v) => setState(() => _included = v),
                    title: Text(line.balanceAsOf == null
                        ? '${a.account.type.revolvingLabel}ที่กรอกไว้หักการจ่ายนี้แล้ว'
                        : '${a.account.type.revolvingLabel}ที่แก้ไว้เมื่อ ${fmtDate(line.balanceAsOf!)} หักการจ่ายนี้แล้ว'),
                    subtitle: const Text('เปิดไว้ = นับเข้าบิลอย่างเดียว ไม่หักยอดซ้ำ'),
                  ),
                formGap,
                Text('ประเภท', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in types)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() {
                          _type = t;
                          _amountTouched = false;
                          _suggestAmount(a);
                        }),
                      ),
                  ],
                ),
                if (plan != null && plan.plan.includedInStatement)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'ค่างวดของรายการนี้รวมอยู่ในยอดบัตรแล้ว — จ่ายค่างวดปกติให้บันทึกที่วงเงินบัตรแทน',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                formGap,
                AmountField(
                  controller: _amount,
                  label: 'จำนวนเงิน',
                  required: true,
                  allowZero: false,
                  onChanged: (_) => setState(() => _amountTouched = true),
                ),
                if (_type == PaymentType.extra && plan != null) ...[
                  formGap,
                  Text('หลังโปะ ต้องการให้', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<PrepaymentMode>(
                    segments: [
                      for (final m in PrepaymentMode.values) ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (v) => setState(() => _mode = v.first),
                  ),
                ],
                formGap,
                _ImpactPreview(
                  account: a,
                  plan: plan,
                  line: line,
                  type: _type,
                  amount: amount,
                  mode: _mode,
                  date: _date,
                  balanceUnchanged: _skipBalance(line),
                ),
                formGap,
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'โน้ต',
                    hintText: 'เช่น โปะจากเงินเหลือก้อน UOB Express',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(a),
                  icon: const GlyphIcon(Glyph.done),
                  label: const Text('บันทึก'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ImpactPreview extends StatelessWidget {
  const _ImpactPreview({
    required this.account,
    required this.plan,
    required this.line,
    required this.type,
    required this.amount,
    required this.mode,
    required this.date,
    this.balanceUnchanged = false,
  });

  final AccountSummary account;
  final InstallmentState? plan;
  final CreditLine? line;
  final PaymentType type;
  final double amount;
  final PrepaymentMode mode;
  final DateTime date;

  /// The typed-in balance already has this payment.
  final bool balanceUnchanged;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    final p = plan;
    if (p != null) {
      if (type == PaymentType.extra || type == PaymentType.full) {
        if (p.isLockedOn(date)) {
          rows.add(Text('ยังอยู่ในช่วง lock-in ถึง ${fmtDate(p.earliestClosureDate!)} — ตรวจสอบเงื่อนไขกับธนาคารก่อนโปะ',
              style: TextStyle(color: cs.warning)));
        }
        final c = PrepaymentComparison.compute(p.current, amount);
        final o = mode == PrepaymentMode.reduceTerm || type == PaymentType.full ? c.reduceTerm : c.reducePayment;
        rows.addAll([
          InfoRow('เงินต้นคงเหลือ', '${fmtMoney(p.remainingPrincipal)} → ${fmtMoney(o.after.balance)}'),
          if (!o.after.isClosed) ...[
            InfoRow('ค่าผ่อน/เดือน', '${fmtMoney(p.currentPayment)} → ${fmtMoney(o.newPayment)}'),
            InfoRow('งวดคงเหลือ', '${p.remainingInstallments} → ${o.months}'),
          ],
          InfoRow('ประหยัดดอกเบี้ย', fmtMoney(o.interestSaved), valueColor: cs.positive, bold: true),
        ]);
      } else {
        final next = p.nextRow;
        if (next != null) {
          final due = next.dueDate;
          rows.addAll([
            InfoRow('งวดที่', due == null ? '${next.number}' : '${next.number} · ครบกำหนด ${fmtDate(due)}'),
            InfoRow('ตัดดอกเบี้ย', fmtMoney(next.interest)),
            InfoRow('ตัดเงินต้น', fmtMoney(amount - next.interest)),
          ]);
          // Paying an installment months ahead usually means it was already
          // counted in the plan's "จ่ายไปแล้ว".
          if (type == PaymentType.installment && due != null && due.isAfter(date.add(const Duration(days: 31)))) {
            rows.add(Text(
              'งวดที่ ${next.number} ยังไม่ถึงกำหนดอีกนาน ถ้าเงินนี้คืองวดที่นับไว้ใน "จ่ายไปแล้ว" ของรายการผ่อน จะนับซ้ำ',
              style: TextStyle(color: cs.warning),
            ));
          }
        }
      }
    } else if (line != null) {
      final after = balanceUnchanged ? line!.balance : (line!.balance - amount).clamp(0.0, double.infinity);
      rows.add(InfoRow(
        'ยอดคงค้าง ${line!.name}',
        balanceUnchanged ? '${fmtMoney(after)} (ไม่เปลี่ยน)' : '${fmtMoney(line!.balance)} → ${fmtMoney(after)}',
      ));
      if (account.account.minimumPayment > 0) {
        rows.add(InfoRow('ขั้นต่ำคงเหลือหลังจ่าย',
            fmtMoney((account.minimumOutstanding - amount).clamp(0.0, double.infinity))));
      }
      if (line!.annualRate > 0 && !balanceUnchanged) {
        rows.add(InfoRow('ดอกเบี้ยที่ลดลงต่อเดือน (ประมาณ)',
            fmtMoney((line!.balance - after) * line!.annualRate / 1200), valueColor: cs.positive));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ผลหลังบันทึก', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            ...rows,
          ],
        ),
      ),
    );
  }
}
