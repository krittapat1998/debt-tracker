import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/sources/sms/sms_parser_config.dart';
import '../../data/sources/sms/sms_parser_service.dart';
import '../../data/sources/statement_source_parser.dart';
import '../providers.dart';
import '../widgets/common.dart';

const _template = '''{
  "banks": [
    {"id": "mybank", "name": "ธนาคารของฉัน", "senderIds": ["MYBANK"], "keywords": ["MyBank"]}
  ],
  "patterns": [
    {
      "id": "mybank-statement",
      "bankId": "mybank",
      "kind": "statement",
      "trigger": "ยอดเรียกเก็บ",
      "amount": "ยอดเรียกเก็บ[^0-9]{0,20}{AMOUNT}",
      "minimum": "ขั้นต่ำ[^0-9]{0,20}{AMOUNT}",
      "dueDate": "ภายใน[^0-9]{0,10}{DATE}",
      "card": "x{CARD}"
    }
  ]
}''';

/// Shows the bundled bank senders and lets the user add their own regex
/// patterns (stored locally), with a live tester.
class SmsPatternsScreen extends ConsumerStatefulWidget {
  const SmsPatternsScreen({super.key});

  @override
  ConsumerState<SmsPatternsScreen> createState() => _SmsPatternsScreenState();
}

class _SmsPatternsScreenState extends ConsumerState<SmsPatternsScreen> {
  final _json = TextEditingController();
  final _sample = TextEditingController();
  final _sender = TextEditingController();
  String? _error;
  String? _result;

  @override
  void initState() {
    super.initState();
    ref.read(settingsServiceProvider).customSmsPatterns().then((v) {
      if (mounted) setState(() => _json.text = v ?? '');
    });
  }

  @override
  void dispose() {
    _json.dispose();
    _sample.dispose();
    _sender.dispose();
    super.dispose();
  }

  SmsParserConfig? _custom() {
    final text = _json.text.trim();
    if (text.isEmpty) return null;
    return SmsParserConfig.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  }

  Future<void> _save() async {
    try {
      _custom();
    } catch (e) {
      setState(() => _error = 'JSON/regex ไม่ถูกต้อง: $e');
      return;
    }
    await ref.read(settingsServiceProvider).setCustomSmsPatterns(_json.text.trim().isEmpty ? null : _json.text.trim());
    ref.invalidate(smsConfigProvider);
    await ref.read(pendingImportsProvider.notifier).syncListening();
    setState(() => _error = null);
    if (mounted) showSnack(context, 'บันทึกรูปแบบแล้ว');
  }

  Future<void> _test() async {
    try {
      final bundled = await ref.read(smsConfigProvider.future);
      final custom = _custom();
      final parser = SmsParserService(custom == null ? bundled : bundled.merge(custom));
      final e = parser.parse(RawStatementMessage(
        source: _sender.text.trim().isEmpty ? StatementSourceType.pasted : StatementSourceType.sms,
        sender: _sender.text.trim(),
        body: _sample.text,
        receivedAt: DateTime.now(),
      ));
      setState(() {
        _error = null;
        _result = e == null
            ? 'ไม่ตรงกับรูปแบบใด'
            : [
                'รูปแบบ: ${e.patternId}',
                'ประเภท: ${e.kind.label}',
                'ธนาคาร: ${e.bankName ?? '-'}',
                'ยอด: ${fmtMoney(e.amount)}',
                if (e.minimumDue != null) 'ขั้นต่ำ: ${fmtMoney(e.minimumDue!)}',
                if (e.dueDate != null) 'ครบกำหนด: ${fmtDate(e.dueDate!)}',
                if (e.cardLast4 != null) 'บัตร: ${e.cardLast4}',
                'วันที่: ${fmtDate(e.occurredAt)}',
              ].join('\n');
      });
    } catch (e) {
      setState(() => _error = 'JSON/regex ไม่ถูกต้อง: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(smsConfigProvider).value;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('รูปแบบ SMS ธนาคาร')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'แอพมีรูปแบบทั่วไปที่จับคำว่า "ยอดเรียกเก็บ / ขั้นต่ำ / ได้รับชำระ / ใช้จ่าย" ได้แล้ว '
            'ถ้า SMS ธนาคารของคุณอ่านไม่ออก เพิ่มรูปแบบเฉพาะได้ด้านล่าง (เก็บในเครื่องเท่านั้น)',
            style: t.bodyMedium,
          ),
          const SectionHeader('ผู้ส่งที่รู้จัก'),
          if (config != null)
            for (final b in config.banks)
              ListTile(
                dense: true,
                title: Text(b.name),
                subtitle: Text('ผู้ส่ง: ${b.senderIds.join(', ')}'),
              ),
          const SectionHeader('รูปแบบเพิ่มเติม (JSON)'),
          Text(
            'มาโคร: {AMOUNT} ตัวเลข, {MONEY} ตัวเลขที่มีคอมมาหรือทศนิยม, {DATE} วันที่, {CARD} เลข 4 หลัก · '
            'kind: statement / payment / spending · ใช้ id ซ้ำกับของเดิมเพื่อแทนที่',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _json,
            minLines: 6,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(hintText: 'ว่าง = ใช้รูปแบบมาตรฐาน'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _json.text = _template),
                child: const Text('ใส่ตัวอย่าง'),
              ),
              FilledButton(onPressed: _save, child: const Text('บันทึกรูปแบบ')),
            ],
          ),
          const SectionHeader('ทดสอบ'),
          TextField(controller: _sender, decoration: const InputDecoration(labelText: 'ผู้ส่ง (เว้นว่างได้)')),
          const SizedBox(height: 8),
          TextField(
            controller: _sample,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'ข้อความ SMS ตัวอย่าง'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(onPressed: _test, child: const Text('ทดสอบอ่านยอด')),
          ),
          if (_result != null)
            Card(margin: const EdgeInsets.only(top: 8), child: Padding(padding: const EdgeInsets.all(12), child: Text(_result!))),
        ],
      ),
    );
  }
}
