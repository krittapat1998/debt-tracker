import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../data/sources/statement_source_parser.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'import_review_sheet.dart';
import 'sms_patterns_screen.dart';

/// Bank-notice import. Android: read inbox / listen for new SMS (with
/// permission). iOS (no SMS API): paste the text; both platforms share the
/// same parser and review step.
class SmsImportScreen extends ConsumerStatefulWidget {
  const SmsImportScreen({super.key});

  @override
  ConsumerState<SmsImportScreen> createState() => _SmsImportScreenState();
}

class _SmsImportScreenState extends ConsumerState<SmsImportScreen> with WidgetsBindingObserver {
  final _paste = TextEditingController();
  bool _hasPermission = false;
  bool _listen = false;
  bool _busy = false;
  bool _clipboardHasText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paste.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final gw = ref.read(smsGatewayProvider);
    final perm = await gw.hasPermission();
    final listen = await ref.read(settingsServiceProvider).smsListenEnabled();
    // hasStrings() does not trigger the iOS paste prompt.
    final clip = await Clipboard.hasStrings();
    if (mounted) {
      setState(() {
        _hasPermission = perm;
        _listen = listen;
        _clipboardHasText = clip;
      });
    }
  }

  Future<void> _requestPermission() async {
    final gw = ref.read(smsGatewayProvider);
    final ok = await confirmDialog(
      context,
      title: 'อนุญาตให้อ่าน SMS?',
      message: 'แอพจะอ่านเฉพาะเพื่อหา SMS แจ้งยอดบัตร/การชำระจากธนาคาร '
          'แอพอ่านข้อความในเครื่องนี้เท่านั้น ไม่ส่ง SMS ออกจากเครื่องไปที่ไหน '
          'และทุกรายการต้องให้คุณยืนยันก่อนบันทึก',
      confirmLabel: 'ดำเนินการต่อ',
    );
    if (!ok) return;
    if (await gw.isPermanentlyDenied()) {
      await gw.openSettings();
      return;
    }
    final granted = await gw.requestPermission();
    await _refreshStatus();
    if (granted) {
      await ref.read(pendingImportsProvider.notifier).syncListening();
      await _scan();
    } else if (mounted) {
      showSnack(context, 'ไม่ได้รับสิทธิ์ — ยังใช้วิธีวางข้อความได้ตามปกติ');
    }
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final added = await ref.read(pendingImportsProvider.notifier).scanInbox();
      if (mounted) showSnack(context, added == 0 ? 'ไม่พบ SMS แจ้งยอดใหม่' : 'พบ $added รายการ รอตรวจสอบ');
    } catch (e) {
      if (mounted) showSnack(context, 'อ่าน SMS ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleListen(bool v) async {
    await ref.read(settingsServiceProvider).setSmsListenEnabled(v);
    await ref.read(pendingImportsProvider.notifier).syncListening();
    setState(() => _listen = v);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _paste.text = data!.text!);
  }

  Future<void> _parsePasted() async {
    final text = _paste.text.trim();
    if (text.isEmpty) return;
    // Several SMS pasted together: split on blank lines.
    final chunks = text.split(RegExp(r'\n\s*\n')).where((c) => c.trim().isNotEmpty).toList();
    final notifier = ref.read(pendingImportsProvider.notifier);
    var found = 0;
    var known = 0;
    final imported = <String>[];
    for (final c in chunks) {
      switch (await notifier.addPasted(c)) {
        case PasteResult.added:
          found++;
        case PasteResult.alreadyPending:
          known++;
        case PasteResult.alreadyImported:
          imported.add(c);
        case PasteResult.unreadable:
          break;
      }
    }
    if (imported.isNotEmpty && mounted) {
      final again = await confirmDialog(
        context,
        title: 'เคยบันทึกข้อความนี้แล้ว',
        message: '${imported.length == 1 ? 'SMS นี้' : 'SMS ${imported.length} ข้อความนี้'}ถูกบันทึกไปแล้ว '
            'ถ้าเพิ่มอีกครั้ง ยอดอาจถูกนับซ้ำ',
        confirmLabel: 'เพิ่มอีกครั้ง',
      );
      if (again) {
        for (final c in imported) {
          if (await notifier.addPasted(c, force: true) == PasteResult.added) found++;
        }
      } else {
        known += imported.length;
      }
    }
    if (!mounted) return;
    if (found > 0) {
      _paste.clear();
      showSnack(context, 'อ่านได้ $found รายการ ตรวจสอบด้านล่างก่อนบันทึก');
    } else if (known > 0) {
      _paste.clear();
      showSnack(context, 'ไม่มีรายการใหม่ — ข้อความนี้อยู่ในรายการรอตรวจสอบหรือบันทึกไปแล้ว');
    } else {
      showSnack(context, 'อ่านยอดจากข้อความนี้ไม่ได้ — ลองกรอกเอง หรือเพิ่มรูปแบบ SMS ในตั้งค่า');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingImportsProvider);
    final gw = ref.watch(smsGatewayProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('นำเข้ายอดจาก SMS'),
        actions: [
          IconButton(
            tooltip: 'รูปแบบ SMS ธนาคาร',
            icon: const Icon(Icons.rule),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsPatternsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (gw.isSupported) _androidCard(t) else _iosInfoCard(t),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('วางข้อความ SMS', style: t.titleSmall),
                  const SizedBox(height: 4),
                  Text('คัดลอก SMS จากแอพข้อความแล้ววางที่นี่ (วางหลายข้อความได้ คั่นด้วยบรรทัดว่าง)', style: t.bodySmall),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _paste,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(hintText: 'เช่น ยอดเรียกเก็บบัตร x1234 จำนวน 15,230.50 บ. ขั้นต่ำ ...'),
                  ),
                  const SizedBox(height: 10),
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.content_paste),
                        label: Text(_clipboardHasText ? 'วางจากคลิปบอร์ด •' : 'วางจากคลิปบอร์ด'),
                        onPressed: _pasteFromClipboard,
                      ),
                      FilledButton(onPressed: _parsePasted, child: const Text('อ่านยอด')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SectionHeader('รอตรวจสอบ (${pending.length})'),
          if (pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('ไม่มีรายการรอตรวจสอบ'),
            ),
          for (final e in pending) _PendingCard(event: e),
        ],
      ),
    );
  }

  Widget _androidCard(TextTheme t) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('อ่าน SMS ธนาคารอัตโนมัติ (Android)', style: t.titleSmall),
            const SizedBox(height: 4),
            Text(
              'แอพอ่านข้อความในเครื่องนี้เท่านั้น ไม่ส่งไปที่ไหน และไม่บันทึกอะไรจนกว่าคุณจะยืนยัน',
              style: t.bodySmall,
            ),
            const SizedBox(height: 10),
            if (!_hasPermission)
              FilledButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text('อนุญาตอ่าน SMS'),
                onPressed: _requestPermission,
              )
            else ...[
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.manage_search),
                label: const Text('สแกน SMS 45 วันล่าสุด'),
                onPressed: _busy ? null : _scan,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('รับ SMS ใหม่อัตโนมัติ'),
                subtitle: const Text('เมื่อมี SMS แจ้งยอด/รับชำระเข้ามา แอพจะแจ้งเตือนให้ตรวจสอบ แม้ปิดแอพอยู่'),
                value: _listen,
                onChanged: _toggleListen,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _iosInfoCard(TextTheme t) {
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.info_outline),
        title: const Text('บน iPhone ใช้วิธีวางข้อความ'),
        subtitle: Text(Platform.isIOS ? 'iOS ไม่อนุญาตให้แอพอ่าน SMS ได้โดยตรง' : 'อุปกรณ์นี้อ่าน SMS ไม่ได้', style: t.bodySmall),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'วิธีที่เร็วที่สุด:\n'
            '1. กดค้างที่ SMS ของธนาคาร → คัดลอก\n'
            '2. เปิดหน้านี้ → "วางจากคลิปบอร์ด" → "อ่านยอด"\n\n'
            'ทำให้อัตโนมัติขึ้นด้วยแอพคำสั่งลัด (Shortcuts):\n'
            'ระบบอัตโนมัติ → ข้อความ → ผู้ส่งเป็นธนาคาร หรือมีคำว่า "ยอดเรียกเก็บ" → '
            'การทำงาน "คัดลอกไปยังคลิปบอร์ด" (ตัวข้อความ) + "เปิดแอพ Debt Tracker" '
            'แล้วกดปุ่มวางในหน้านี้ได้ทันที',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.event});
  final ParsedStatementEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill(e.kind.label, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(e.bankName ?? e.message.sender, style: t.labelLarge)),
                Text(fmtDateShort(e.message.receivedAt), style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(fmtMoney(e.amount), style: t.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              [
                if (e.minimumDue != null) 'ขั้นต่ำ ${fmtMoney(e.minimumDue!)}',
                if (e.dueDate != null) 'ครบกำหนด ${fmtDate(e.dueDate!)}',
                if (e.cardLast4 != null) 'บัตร •••• ${e.cardLast4}',
              ].join(' · '),
              style: t.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(e.message.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref.read(pendingImportsProvider.notifier).resolve(e, imported: false),
                  child: const Text('ไม่ใช้'),
                ),
                FilledButton.tonal(
                  onPressed: () => showImportReviewSheet(context, e),
                  child: const Text('ตรวจสอบและบันทึก'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
