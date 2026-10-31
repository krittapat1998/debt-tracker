import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/portfolio.dart';
import '../providers.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';

Future<void> showStatementSheet(BuildContext context, AccountSummary a) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StatementSheet(a: a),
    );

class _StatementSheet extends ConsumerStatefulWidget {
  const _StatementSheet({required this.a});
  final AccountSummary a;

  @override
  ConsumerState<_StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends ConsumerState<_StatementSheet> {
  final _form = GlobalKey<FormState>();
  late final _balance = TextEditingController(text: amountToField(widget.a.account.statementBalance));
  late final _minimum = TextEditingController(text: amountToField(widget.a.account.minimumPayment));
  late DateTime _statementDate;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final acc = widget.a.account;
    final today = dateOnly(DateTime.now());
    _statementDate = acc.billingDay != null ? previousOccurrenceOfDay(acc.billingDay!, today) : today;
    _dueDate = acc.dueDay != null ? nextDayAfter(acc.dueDay!, _statementDate) : null;
  }

  @override
  void dispose() {
    _balance.dispose();
    _minimum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await ref.read(ledgerProvider).applyStatement(
          accountId: widget.a.account.id,
          statementBalance: parseAmount(_balance.text) ?? 0,
          minimumPayment: parseAmount(_minimum.text) ?? 0,
          statementDate: _statementDate,
          dueDate: _dueDate,
        );
    ref.refreshData();
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, 'อัปเดตยอดเรียกเก็บแล้ว');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ยอดเรียกเก็บ: ${widget.a.account.name}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('กรอกจากใบแจ้งยอด/SMS ของงวดล่าสุด การจ่ายตั้งแต่วันที่ออกใบแจ้งยอดจะถูกนับหักจากยอดนี้'),
              formGap,
              AmountField(controller: _balance, label: 'ยอดเรียกเก็บ (เต็มยอด)', required: true),
              formGap,
              AmountField(controller: _minimum, label: 'ยอดขั้นต่ำ'),
              formGap,
              DateField(
                value: _statementDate,
                label: 'วันที่ออกใบแจ้งยอด (ตัดรอบ)',
                onChanged: (d) => setState(() => _statementDate = d ?? _statementDate),
              ),
              formGap,
              DateField(
                value: _dueDate,
                label: 'วันครบกำหนดชำระ',
                clearable: true,
                onChanged: (d) => setState(() => _dueDate = d),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('บันทึก')),
            ],
          ),
        ),
      ),
    );
  }
}
