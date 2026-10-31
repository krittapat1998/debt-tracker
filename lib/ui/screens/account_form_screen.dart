import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/services/ledger_service.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/account.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/enums.dart';
import '../providers.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'plan_form_screen.dart';

class _LineDraft {
  _LineDraft({
    String? id,
    String name = '',
    double? limit,
    double? balance,
    double? rate,
    this.method = InterestMethod.reducing,
  })  : id = id ?? newId(),
        name = TextEditingController(text: name),
        limit = TextEditingController(text: amountToField(limit)),
        balance = TextEditingController(text: amountToField(balance)),
        rate = TextEditingController(text: rate == null ? '' : _rateText(rate));

  factory _LineDraft.fromLine(CreditLine l) => _LineDraft(
        id: l.id,
        name: l.name,
        limit: l.creditLimit,
        balance: l.balance,
        rate: l.annualRate,
        method: l.interestMethod,
      );

  final String id;
  final TextEditingController name;
  final TextEditingController limit;
  final TextEditingController balance;
  final TextEditingController rate;
  InterestMethod method;

  void dispose() {
    name.dispose();
    limit.dispose();
    balance.dispose();
    rate.dispose();
  }
}

String _rateText(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : '$r';

/// Default sub-limit name and rate per account type (Thai market norms:
/// credit cards are capped at 16%, cash cards/personal loans at 25%).
(String, double) _defaultLine(AccountType t) => switch (t) {
      AccountType.creditCard => ('วงเงินบัตรเครดิต', 16),
      AccountType.cashCard => ('วงเงินกดเงินสด', 25),
      AccountType.personalLoan => ('วงเงินสินเชื่อ', 25),
      AccountType.other => ('วงเงินหลัก', 0),
    };

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.existing});
  final AccountSummary? existing;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Account? _orig = widget.existing?.account;
  late final _name = TextEditingController(text: _orig?.name ?? '');
  late final _last4 = TextEditingController(text: _orig?.cardLast4 ?? '');
  late final _statement = TextEditingController(text: amountToField(_orig?.statementBalance));
  late final _minimum = TextEditingController(text: amountToField(_orig?.minimumPayment));
  late final _sharedLimit = TextEditingController(text: amountToField(_orig?.sharedLimit));
  late final _note = TextEditingController(text: _orig?.note ?? '');
  late AccountType _type = _orig?.type ?? AccountType.creditCard;
  late String? _issuer = _orig?.issuer;
  late int? _billingDay = _orig?.billingDay;
  late int? _dueDay = _orig?.dueDay;
  late int _reminderDays = _orig?.reminderDaysBefore ?? 3;
  late DateTime? _statementDate = _orig?.statementDate;
  late final List<_LineDraft> _lines;
  bool _saving = false;

  bool get _isNew => _orig == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing?.lines ?? const [];
    if (existing.isNotEmpty) {
      _lines = existing.map(_LineDraft.fromLine).toList();
    } else {
      final (n, r) = _defaultLine(_type);
      _lines = [_LineDraft(name: n, rate: r)];
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _last4, _statement, _minimum, _sharedLimit, _note]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _onTypeChanged(AccountType t) {
    setState(() {
      final (oldName, oldRate) = _defaultLine(_type);
      _type = t;
      // Only retouch the first line if the user has not edited it.
      if (_isNew && _lines.length == 1 && _lines.first.name.text == oldName &&
          parseAmount(_lines.first.rate.text) == oldRate) {
        final (n, r) = _defaultLine(t);
        _lines.first.name.text = n;
        _lines.first.rate.text = _rateText(r);
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final account = Account(
      id: _orig?.id ?? newId(),
      name: _name.text.trim(),
      type: _type,
      issuer: _issuer,
      cardLast4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
      billingDay: _billingDay,
      dueDay: _dueDay,
      statementBalance: parseAmount(_statement.text) ?? 0,
      minimumPayment: parseAmount(_minimum.text) ?? 0,
      statementDate: _statementDate,
      statementDueDate: _statementDate == _orig?.statementDate ? _orig?.statementDueDate : null,
      sharedLimit: parseAmount(_sharedLimit.text),
      reminderDaysBefore: _reminderDays,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      createdAt: _orig?.createdAt ?? DateTime.now(),
    );
    final lines = [
      for (final (i, l) in _lines.indexed)
        CreditLine(
          id: l.id,
          accountId: account.id,
          name: l.name.text.trim(),
          creditLimit: parseAmount(l.limit.text) ?? 0,
          balance: parseAmount(l.balance.text) ?? 0,
          annualRate: parseAmount(l.rate.text) ?? 0,
          interestMethod: l.method,
          sortOrder: i,
        ),
    ];
    await ref.read(ledgerProvider).saveAccount(account, lines);
    ref.refreshData();
    if (!mounted) return;

    if (_isNew && _type == AccountType.personalLoan) {
      final addPlan = await confirmDialog(
        context,
        title: 'เพิ่มรายละเอียดการผ่อน?',
        message: 'สินเชื่อส่วนบุคคลมักผ่อนเป็นงวด เพิ่มเงินต้น ดอกเบี้ย และจำนวนงวด เพื่อให้แอพคำนวณยอดคงเหลือและดอกเบี้ยให้',
        confirmLabel: 'เพิ่มเลย',
      );
      if (!mounted) return;
      if (addPlan) {
        final s = await ref.read(portfolioProvider.future);
        final summary = s.byId(account.id);
        if (!mounted || summary == null) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PlanFormScreen(account: summary)),
        );
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(smsConfigProvider).value?.banks ?? const [];
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'เพิ่มบัตร/สินเชื่อ' : 'แก้ไข ${_orig!.name}')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'ชื่อบัตร/สินเชื่อ', hintText: 'เช่น First Choice, UOB Preferred Platinum'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
            ),
            formGap,
            DropdownButtonFormField<AccountType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ประเภท'),
              items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (v) => _onTypeChanged(v!),
            ),
            formGap,
            DropdownButtonFormField<String?>(
              initialValue: banks.any((b) => b.id == _issuer) ? _issuer : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'ธนาคาร/ผู้ออกบัตร',
                helperText: 'ใช้จับคู่ SMS แจ้งยอดกับบัตรนี้',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
                for (final b in banks) DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _issuer = v),
            ),
            formGap,
            TextFormField(
              controller: _last4,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'เลขท้ายบัตร 4 หลัก (ถ้ามี)', counterText: ''),
              validator: (v) => (v != null && v.isNotEmpty && v.length != 4) ? 'ต้องเป็นตัวเลข 4 หลัก' : null,
            ),
            formGap,
            Row(
              children: [
                Expanded(
                  child: DayOfMonthField(
                    value: _billingDay,
                    label: 'วันตัดรอบบิล',
                    onChanged: (v) => setState(() => _billingDay = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DayOfMonthField(
                    value: _dueDay,
                    label: 'วันครบกำหนดชำระ',
                    onChanged: (v) => setState(() => _dueDay = v),
                  ),
                ),
              ],
            ),
            formGap,
            DropdownButtonFormField<int>(
              initialValue: _reminderDays,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'แจ้งเตือนล่วงหน้า'),
              items: [
                for (final d in [0, 1, 2, 3, 5, 7, 10])
                  DropdownMenuItem(value: d, child: Text(d == 0 ? 'เฉพาะวันครบกำหนด' : '$d วันก่อนครบกำหนด')),
              ],
              onChanged: (v) => setState(() => _reminderDays = v ?? 3),
            ),
            SectionHeader('วงเงินย่อย'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'บัตรใบเดียวอาจมีหลายวงเงิน เช่น วงเงินบัตรเครดิต 16% กับวงเงินสินเชื่อ 25% ในบัตรเดียวกัน '
                'ใส่ยอดคงค้างแบบหมุนเวียน (ไม่รวมรายการที่จะบันทึกเป็นรายการผ่อน)',
                style: t.bodySmall,
              ),
            ),
            for (final (i, l) in _lines.indexed) _lineEditor(i, l),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มวงเงินย่อย'),
              onPressed: () => setState(() => _lines.add(_LineDraft(name: 'วงเงินสินเชื่อ', rate: 25))),
            ),
            if (_lines.length > 1) ...[
              formGap,
              AmountField(
                controller: _sharedLimit,
                label: 'วงเงินรวม (ถ้าวงเงินย่อยใช้วงเงินร่วมกัน)',
                helper: 'เว้นว่าง = รวมวงเงินย่อยทุกอัน',
              ),
            ],
            SectionHeader('ยอดเรียกเก็บงวดล่าสุด (ถ้ามี)'),
            AmountField(controller: _statement, label: 'ยอดเรียกเก็บ'),
            formGap,
            AmountField(controller: _minimum, label: 'ยอดขั้นต่ำ'),
            formGap,
            DateField(
              value: _statementDate,
              label: 'วันที่ออกใบแจ้งยอด',
              clearable: true,
              onChanged: (d) => setState(() => _statementDate = d),
            ),
            formGap,
            TextFormField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'โน้ต'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_isNew ? 'บันทึก' : 'บันทึกการแก้ไข'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _lineEditor(int index, _LineDraft l) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: l.name,
                    decoration: const InputDecoration(labelText: 'ชื่อวงเงิน'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอก' : null,
                  ),
                ),
                if (_lines.length > 1)
                  IconButton(
                    tooltip: 'ลบวงเงินนี้',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lines.removeAt(index).dispose()),
                  ),
              ],
            ),
            formGap,
            Row(
              children: [
                Expanded(child: AmountField(controller: l.limit, label: 'วงเงิน')),
                const SizedBox(width: 12),
                Expanded(child: AmountField(controller: l.balance, label: 'ยอดคงค้าง')),
              ],
            ),
            formGap,
            AmountField(controller: l.rate, label: 'ดอกเบี้ยต่อปี', suffix: '%', required: true),
            formGap,
            SegmentedButton<InterestMethod>(
              segments: [
                for (final m in InterestMethod.values) ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {l.method},
              onSelectionChanged: (s) => setState(() => l.method = s.first),
            ),
          ],
        ),
      ),
    );
  }
}
