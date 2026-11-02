import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/date_utils.dart';
import '../../data/backup/backup_service.dart';
import '../../data/services/settings_service.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'sms_import_screen.dart';
import 'sms_patterns_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider).value ?? const NotificationPrefs();
    final settings = ref.read(settingsServiceProvider);
    final theme = ref.watch(themeChoiceProvider);

    Future<void> savePrefs(NotificationPrefs p) async {
      await settings.saveNotificationPrefs(p);
      ref.invalidate(notificationPrefsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader('ธีม'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in ThemeChoice.values)
                  ChoiceChip(
                    avatar: _ThemeSwatch(c),
                    label: Text(c.label),
                    selected: theme == c,
                    showCheckmark: false,
                    onSelected: (_) => ref.read(themeChoiceProvider.notifier).set(c),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('ตามระบบ = สว่างหรือมืดตามการตั้งค่าของเครื่อง'),
          ),
          const SectionHeader('การแจ้งเตือน'),
          SwitchListTile(
            title: const Text('เตือนวันครบกำหนดชำระ'),
            subtitle: const Text('ตามจำนวนวันล่วงหน้าที่ตั้งไว้ในแต่ละบัตร และในวันครบกำหนด'),
            value: prefs.enabled,
            onChanged: (v) async {
              if (v) await ref.read(notificationServiceProvider).requestPermission();
              await savePrefs(NotificationPrefs(enabled: v, hour: prefs.hour, billingReminders: prefs.billingReminders));
            },
          ),
          SwitchListTile(
            title: const Text('เตือนวันตัดรอบบิล'),
            subtitle: const Text('ให้อัปเดตยอดเรียกเก็บเมื่อได้รับใบแจ้งยอด'),
            value: prefs.billingReminders,
            onChanged: prefs.enabled
                ? (v) => savePrefs(NotificationPrefs(enabled: prefs.enabled, hour: prefs.hour, billingReminders: v))
                : null,
          ),
          ListTile(
            enabled: prefs.enabled,
            title: const Text('เวลาแจ้งเตือน'),
            trailing: Text('${prefs.hour.toString().padLeft(2, '0')}:00'),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: prefs.hour, minute: 0));
              if (picked != null) {
                await savePrefs(NotificationPrefs(enabled: prefs.enabled, hour: picked.hour, billingReminders: prefs.billingReminders));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('ทดสอบการแจ้งเตือน'),
            subtitle: const Text('ขอสิทธิ์ (ถ้ายังไม่ได้ให้) แล้วส่งการแจ้งเตือนตัวอย่างทันที'),
            onTap: () async {
              final notifications = ref.read(notificationServiceProvider);
              final ok = await notifications.requestPermission();
              if (ok) {
                await notifications.showTest();
                // Reminders scheduled before permission was granted never fire.
                ref.refreshData();
              } else if (context.mounted) {
                showSnack(context, 'ยังไม่ได้รับอนุญาต — เปิดได้ในการตั้งค่าของเครื่อง');
              }
            },
          ),
          const SectionHeader('SMS ธนาคาร'),
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: const Text('นำเข้ายอดจาก SMS'),
            subtitle: Text(Platform.isAndroid ? 'อ่าน SMS อัตโนมัติ หรือวางข้อความ' : 'วางข้อความ SMS ให้แอพอ่านยอด'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsImportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.rule),
            title: const Text('รูปแบบ SMS ธนาคาร'),
            subtitle: const Text('เพิ่ม/ทดสอบ regex สำหรับธนาคารของคุณ'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsPatternsScreen())),
          ),
          const SectionHeader('สำรองข้อมูล'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('ส่งออกไฟล์สำรอง (JSON)'),
            subtitle: const Text('แนะนำให้ตั้งรหัสผ่าน (เข้ารหัส AES-256) ก่อนฝากไว้บน cloud'),
            onTap: () => _exportJson(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('ส่งออก CSV'),
            subtitle: const Text('เปิดใน Excel / Google Sheets (ไม่เข้ารหัส)'),
            onTap: () => _exportCsv(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('กู้คืนจากไฟล์สำรอง'),
            subtitle: const Text('แทนที่ข้อมูลทั้งหมดในเครื่องนี้'),
            onTap: () => _restore(context, ref),
          ),
          const SectionHeader('ความเป็นส่วนตัว'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'ข้อมูลทั้งหมดเก็บในฐานข้อมูลบนเครื่องนี้เท่านั้น ไม่มี server และไม่มีการส่งข้อมูลออก '
              'SMS ถูกพาร์สในเครื่อง ไม่ส่งข้อความดิบไปที่ใด ไฟล์สำรองที่ไม่ได้ตั้งรหัสผ่านเป็นข้อความธรรมดา '
              'ควรตั้งรหัสผ่านทุกครั้งก่อนเก็บไว้นอกเครื่อง',
            ),
          ),
        ],
      ),
    );
  }

  Rect? _shareOrigin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    final password = await _askPassword(context, confirm: true);
    if (password == null || !context.mounted) return;
    final origin = _shareOrigin(context);
    showSnack(context, 'กำลังเตรียมไฟล์…');
    final content = await ref.read(backupServiceProvider).exportJson(password: password.isEmpty ? null : password);
    final dir = await getTemporaryDirectory();
    final stamp = isoDate(DateTime.now());
    final file = File(p.join(dir.path, 'debt_tracker_backup_$stamp${password.isEmpty ? '' : '_encrypted'}.json'));
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'Debt Tracker backup $stamp',
      sharePositionOrigin: origin,
    ));
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final origin = _shareOrigin(context);
    final files = await ref.read(backupServiceProvider).exportCsv();
    final dir = await Directory(p.join((await getTemporaryDirectory()).path, 'csv_${DateTime.now().millisecondsSinceEpoch}')).create();
    final xfiles = <XFile>[];
    for (final e in files.entries) {
      final f = File(p.join(dir.path, e.key));
      await f.writeAsString(e.value);
      xfiles.add(XFile(f.path, mimeType: 'text/csv'));
    }
    await SharePlus.instance.share(ShareParams(files: xfiles, subject: 'Debt Tracker CSV', sharePositionOrigin: origin));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (picked.isEmpty || !context.mounted) return;
    final content = await picked.first.xFile.readAsString();
    if (!context.mounted) return;
    String? password;
    if (BackupService.isEncrypted(content)) {
      password = await _askPassword(context, confirm: false);
      if (password == null || !context.mounted) return;
    }
    final ok = await confirmDialog(
      context,
      title: 'กู้คืนข้อมูล?',
      message: 'ข้อมูลปัจจุบันทั้งหมดในเครื่องจะถูกแทนที่ด้วยไฟล์สำรอง',
      confirmLabel: 'กู้คืน',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      final counts = await ref.read(backupServiceProvider).importJson(content, password: password);
      ref.invalidate(smsConfigProvider);
      ref.invalidate(notificationPrefsProvider);
      ref.refreshData();
      if (context.mounted) {
        showSnack(context, 'กู้คืนแล้ว: ${counts['accounts'] ?? 0} บัตร, ${counts['payments'] ?? 0} รายการจ่าย');
      }
    } on BackupException catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  /// Returns null on cancel, '' for "no password".
  Future<String?> _askPassword(BuildContext context, {required bool confirm}) {
    final pw = TextEditingController();
    final pw2 = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirm ? 'ตั้งรหัสผ่านไฟล์สำรอง' : 'รหัสผ่านไฟล์สำรอง'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: pw,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(labelText: 'รหัสผ่าน', helperText: confirm ? 'เว้นว่าง = ไม่เข้ารหัส' : null),
                validator: (v) => !confirm && (v == null || v.isEmpty) ? 'กรุณากรอก' : null,
              ),
              if (confirm) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: pw2,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่าน'),
                  validator: (v) => v != pw.text ? 'รหัสผ่านไม่ตรงกัน' : null,
                ),
                const SizedBox(height: 8),
                const Text('ถ้าลืมรหัสผ่าน จะเปิดไฟล์นี้ไม่ได้อีก', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, pw.text);
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }
}

/// Small preview dot of a theme's background.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch(this.choice);
  final ThemeChoice choice;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: Theme.of(context).colorScheme.outline);
    return switch (choice) {
      ThemeChoice.system => const Icon(Icons.brightness_auto, size: 18),
      ThemeChoice.light => Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: border)),
      ThemeChoice.dark => Container(decoration: BoxDecoration(color: const Color(0xFF111418), shape: BoxShape.circle, border: border)),
      ThemeChoice.blue => Container(decoration: BoxDecoration(color: const Color(0xFF1150C8), shape: BoxShape.circle, border: border)),
    };
  }
}
