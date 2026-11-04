import 'package:flutter/material.dart';

import '../widgets/app_icons.dart';
import '../widgets/links.dart';

/// The privacy policy, inside the app so it reads the same offline.
/// docs/privacy/index.html is the web copy: change both together.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const updated = '5 พฤศจิกายน 2569';
  static const updatedEnglish = '5 November 2026';

  static const summary = 'Debt Tracker ไม่เก็บ ไม่ส่ง และไม่ขายข้อมูลของคุณ ทุกอย่างที่บันทึกอยู่ในเครื่องนี้เท่านั้น '
      'ไม่มีบัญชีผู้ใช้ และไม่มีเซิร์ฟเวอร์';

  static const thai = [
    ('ข้อมูลที่คุณบันทึก',
        'ชื่อบัตร ยอดหนี้ วงเงิน ดอกเบี้ย รายการผ่อน การจ่าย และยอดใช้จ่ายที่คุณกรอก เก็บในฐานข้อมูลของแอพบนเครื่องนี้ '
            'แอพไม่ส่งข้อมูลเหล่านี้ออกทางอินเทอร์เน็ต และผู้พัฒนาไม่เห็นข้อมูลของคุณ'),
    ('SMS ธนาคาร',
        'บน iPhone แอพอ่านเฉพาะข้อความที่คุณวางเอง บน Android ถ้าคุณอนุญาต แอพจะอ่าน SMS จากธนาคารเพื่อดึงยอด '
            'ทั้งหมดอ่านในเครื่อง ไม่เก็บรหัส OTP ไม่ส่งข้อความออกจากเครื่อง และทุกรายการต้องให้คุณยืนยันก่อนบันทึก'),
    ('Face ID และสแกนนิ้ว',
        'การล็อกแอพใช้ระบบยืนยันตัวตนของเครื่อง แอพรู้แค่ว่ายืนยันผ่านหรือไม่ ไม่เห็นและไม่เก็บข้อมูลใบหน้าหรือลายนิ้วมือ'),
    ('การแจ้งเตือนและวิดเจ็ต',
        'การแจ้งเตือนตั้งเวลาไว้ในเครื่อง วิดเจ็ตบนหน้าจอโฮมอ่านยอดสรุปจากพื้นที่ที่แชร์กันภายในเครื่องเดียวกัน'),
    ('สำรองข้อมูล',
        'ไฟล์สำรองสร้างเมื่อคุณกดเองเท่านั้น และไปอยู่ที่ที่คุณเลือก ตั้งรหัสผ่านเพื่อเข้ารหัสไฟล์ได้ '
            'ส่วนไฟล์สำหรับเปิดใน Excel ไม่เข้ารหัส ข้อมูลในแอพอาจรวมอยู่ในการสำรองทั้งเครื่องของ iPhone '
            '(iCloud หรือคอมพิวเตอร์) ตามการตั้งค่าเครื่องของคุณ'),
    ('โฆษณาและการติดตาม',
        'แอพไม่มีโฆษณา ไม่มีระบบเก็บสถิติการใช้งาน และไม่ติดตามคุณข้ามแอพหรือเว็บไซต์ '
            'ถ้าคุณเปิดแชร์ข้อมูลวิเคราะห์กับนักพัฒนาไว้ในการตั้งค่าเครื่อง Apple อาจส่งรายงานแอพค้างแบบไม่ระบุตัวตนให้ผู้พัฒนา'),
    ('ลบข้อมูล',
        'ลบบัตรหรือรายการในแอพได้ทุกเมื่อ ถ้าลบแอพ ข้อมูลทั้งหมดในเครื่องจะหายไปด้วย ยกเว้นไฟล์สำรองที่คุณส่งออกไว้เอง'),
    ('การเปลี่ยนแปลงและติดต่อ', 'ถ้านโยบายนี้เปลี่ยน จะแจ้งในหน้านี้พร้อมวันที่ปรับปรุง สอบถามได้ที่ kritdev.com'),
  ];

  static const englishSummary = 'Debt Tracker does not collect, send or sell your data. Everything you record stays '
      'on this device. There are no accounts and no servers.';

  static const english = [
    ('What you record',
        'Card names, balances, limits, interest rates, installment plans, payments and spending you enter are stored '
            'in the app\'s database on this device. The app does not send them over the internet, and the developer '
            'cannot see them.'),
    ('Bank SMS',
        'On iPhone the app only reads text you paste in. On Android, if you allow it, the app reads bank SMS to pick up '
            'amounts. Messages are read on the device, OTP codes are never stored, nothing leaves the device, and every '
            'entry waits for your confirmation.'),
    ('Face ID and fingerprint',
        'App lock uses the device\'s own authentication. The app only learns whether it succeeded; it never sees or '
            'stores face or fingerprint data.'),
    ('Notifications and widget',
        'Reminders are scheduled on the device. The home screen widget reads a summary from storage shared on the same '
            'device.'),
    ('Backups',
        'Backup files are created only when you ask, and go where you choose. You can protect them with a password '
            '(AES-256 encryption). Spreadsheet (CSV) exports are not encrypted. App data may be included in your '
            'iPhone\'s own device backup (iCloud or computer), depending on your settings.'),
    ('Ads and tracking',
        'No ads, no analytics, no tracking across apps or websites. If you share analytics with developers in your '
            'device settings, Apple may pass on anonymous crash reports.'),
    ('Deleting data',
        'Delete any card or entry in the app at any time. Deleting the app removes all of its data from the device, '
            'except backup files you exported yourself.'),
    ('Changes and contact', 'Changes to this policy will appear here with a new date. Contact: kritdev.com'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    List<Widget> section(String title, String body) => [
          Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: t.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 16),
        ];
    Widget summaryCard(String text) => Card(
          color: cs.primaryContainer,
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlyphIcon(Glyph.privacy, color: cs.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(text,
                        style: t.bodyLarge?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('นโยบายความเป็นส่วนตัว')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          summaryCard(summary),
          const SizedBox(height: 8),
          Text('ปรับปรุงล่าสุด $updated', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          for (final (title, body) in thai) ...section(title, body),
          const Divider(height: 32),
          Text('Privacy policy (English)', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          summaryCard(englishSummary),
          const SizedBox(height: 8),
          Text('Last updated $updatedEnglish', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          for (final (title, body) in english) ...section(title, body),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openLink(context, AppLinks.developer),
              icon: const GlyphIcon(Glyph.external, size: 18),
              label: const Text('kritdev.com'),
            ),
          ),
        ],
      ),
    );
  }
}
