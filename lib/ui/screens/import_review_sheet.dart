import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../data/sources/statement_import_service.dart';
import '../../data/sources/statement_source_parser.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/enums.dart';
import '../providers.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

Future<void> showImportReviewSheet(BuildContext context, ParsedStatementEvent e) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(event: e),
    );

/// Lets the user correct every parsed field before it touches the ledger.
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.event});
  final ParsedStatementEvent event;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  final _form = GlobalKey<FormState>();
  late StatementEventKind _kind = widget.event.kind;
  late final _amount = TextEditingController(text: amountToField(widget.event.amount));
  late final _minimum = TextEditingController(text: amountToField(widget.event.minimumDue));
  late DateTime _date = dateOnly(widget.event.occurredAt);
  late DateTime? _due = widget.event.dueDate;
  String? _accountId;
  String? _target;
  PaymentType? _paymentType;
  bool _initialized = false;

  @override
  void dispose() {
    _amount.dispose();
    _minimum.dispose();
    super.dispose();
  }

  void _init(PortfolioSummary s, StatementImportService importer) {
    if (_initialized) return;
    _initialized = true;
    _accountId = importer.suggestAccount(widget.event, [for (final a in s.accounts) a.account]);
    _resetTarget(s);
    _paymentType = importer.suggestPaymentType(widget.event.amount, _accountId == null ? null : s.byId(_accountId!));
  }

  void _resetTarget(PortfolioSummary s) {
    final a = _accountId == null ? null : s.byId(_accountId!);
    _target = a == null || a.lines.isEmpty ? null : 'line:${a.lines.first.id}';
  }

  Future<void> _save(StatementImportService importer) async {
    if (!_form.currentState!.validate()) return;
    if (_accountId == null) {
      showSnack(context, 'กรุณาเลือกบัตร/สินเชื่อ');
      return;
    }
    final target = _target;
    await importer.commit(
      ImportDecision(
        event: widget.event,
        kind: _kind,
        accountId: _accountId!,
        amount: parseAmount(_amount.text)!,
        minimumDue: parseAmount(_minimum.text),
        dueDate: _due,
        date: _date,
        creditLineId: target != null && target.startsWith('line:') ? target.substring(5) : null,
        planId: target != null && target.startsWith('plan:') ? target.substring(5) : null,
        paymentType: _paymentType ?? PaymentType.other,
        note: 'นำเข้าจาก${widget.event.message.source.label}',
      ),
      ref.read(ledgerProvider),
    );
    await ref.read(pendingImportsProvider.notifier).resolve(widget.event, imported: true);
    ref.refreshData();
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, 'บันทึก${_kind.label} ${fmtMoney(parseAmount(_amount.text)!)} แล้ว');
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider).value;
    final importer = ref.watch(importServiceProvider).value;
    if (portfolio == null || importer == null) {
      return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    }
    _init(portfolio, importer);
    final a = _accountId == null ? null : portfolio.byId(_accountId!);
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ตรวจสอบก่อนบันทึก', style: t.titleLarge),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.event.message.body, style: t.bodySmall),
              ),
              formGap,
              SegmentedButton<StatementEventKind>(
                segments: [for (final k in StatementEventKind.values) ButtonSegment(value: k, label: Text(k.label))],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              formGap,
              DropdownButtonFormField<String?>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'บัตร/สินเชื่อ',
                  helperText: widget.event.cardLast4 == null ? null : 'SMS ระบุบัตรลงท้าย ${widget.event.cardLast4}',
                ),
                items: [
                  for (final x in portfolio.accounts)
                    DropdownMenuItem(
                      value: x.account.id,
                      child: Text([x.account.name, if (x.account.cardLast4 != null) '•••• ${x.account.cardLast4}'].join(' ')),
                    ),
                ],
                validator: (v) => v == null ? 'กรุณาเลือก' : null,
                onChanged: (v) => setState(() {
                  _accountId = v;
                  _resetTarget(portfolio);
                }),
              ),
              if (a != null && _kind != StatementEventKind.statement) ...[
                formGap,
                DropdownButtonFormField<String?>(
                  key: ValueKey('target-${a.account.id}'),
                  initialValue: _target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'วงเงิน/รายการ'),
                  items: [
                    for (final l in a.lines) DropdownMenuItem(value: 'line:${l.id}', child: Text(l.name)),
                    if (_kind == StatementEventKind.payment)
                      for (final p in a.activePlans)
                        DropdownMenuItem(value: 'plan:${p.plan.id}', child: Text('ผ่อน: ${p.plan.name}')),
                  ],
                  onChanged: (v) => setState(() => _target = v),
                ),
              ],
              formGap,
              AmountField(
                controller: _amount,
                label: switch (_kind) {
                  StatementEventKind.statement => 'ยอดเรียกเก็บ',
                  StatementEventKind.payment => 'จำนวนที่จ่าย',
                  StatementEventKind.spending => 'ยอดใช้จ่าย',
                },
                required: true,
                allowZero: false,
              ),
              if (_kind == StatementEventKind.statement) ...[
                formGap,
                AmountField(controller: _minimum, label: 'ยอดขั้นต่ำ'),
                formGap,
                DateField(value: _due, label: 'วันครบกำหนดชำระ', clearable: true, onChanged: (d) => setState(() => _due = d)),
              ],
              if (_kind == StatementEventKind.payment) ...[
                formGap,
                Wrap(
                  spacing: 8,
                  children: [
                    for (final pt in [PaymentType.minimum, PaymentType.full, PaymentType.extra, PaymentType.installment, PaymentType.other])
                      ChoiceChip(
                        label: Text(pt.label),
                        selected: _paymentType == pt,
                        onSelected: (_) => setState(() => _paymentType = pt),
                      ),
                  ],
                ),
              ],
              formGap,
              DateField(
                value: _date,
                label: _kind == StatementEventKind.statement ? 'วันที่ออกใบแจ้งยอด' : 'วันที่ทำรายการ',
                onChanged: (d) => setState(() => _date = d ?? _date),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => _save(importer), child: const Text('ยืนยันและบันทึก')),
            ],
          ),
        ),
      ),
    );
  }
}
