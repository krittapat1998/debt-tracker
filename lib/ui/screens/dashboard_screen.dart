import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/date_utils.dart';
import '../../domain/finance/payoff_plan.dart';
import '../../domain/finance/portfolio.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/card_colors.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';
import 'account_form_screen.dart';
import 'payment_form_screen.dart';
import 'payoff_plan_screen.dart';
import 'sms_import_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final pending = ref.watch(pendingImportsProvider);
    final hasAccounts = portfolio.value?.isEmpty == false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Tracker'),
        actions: [
          TextButton.icon(
            style: _compact,
            icon: Badge(
              isLabelVisible: pending.isNotEmpty,
              label: Text('${pending.length}'),
              child: const Icon(Icons.sms_outlined),
            ),
            label: const Text('นำเข้า SMS'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsImportScreen())),
          ),
          TextButton.icon(
            style: _compact,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('เพิ่มบัตร'),
            onPressed: () => openNewAccount(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: hasAccounts
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('บันทึกการจ่าย'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaymentFormScreen()),
              ),
            )
          : null,
      body: AsyncBody(
        value: portfolio,
        builder: (s) {
          if (s.isEmpty) {
            return EmptyState(
              icon: Icons.credit_card,
              title: 'ยังไม่มีบัตรหรือสินเชื่อ',
              message: 'เพิ่มบัตรเครดิต บัตรกดเงินสด หรือสินเชื่อ เพื่อเริ่มติดตามยอดหนี้ ดอกเบี้ย และวันครบกำหนด',
              action: FilledButton.icon(
                onPressed: () => openNewAccount(context),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มรายการแรก'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refreshData(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (pending.isNotEmpty) _PendingBanner(count: pending.length),
                _SummaryCard(s: s),
                if (s.nextDue != null) _NextDueCard(a: s.nextDue!),
                if (s.recommendedTarget != null) _AvalancheCard(s: s),
                const SectionHeader('บัตร/สินเชื่อ · เรียงตามวันครบกำหนด'),
                for (final a in s.byDueDate)
                  CardColorTheme(
                    color: a.account.color,
                    child: _AccountCard(a: a, isMostExpensive: identical(a, s.mostExpensive)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Narrow padding so both labeled buttons fit beside the title on a 390pt screen.
final _compact = TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8));

Future<void> openNewAccount(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen()));

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.mark_email_unread_outlined, color: cs.onTertiaryContainer),
        title: Text('มีข้อความจากธนาคารรอยืนยัน $count รายการ',
            style: TextStyle(color: cs.onTertiaryContainer)),
        subtitle: Text('ตรวจสอบก่อนบันทึก เพื่อกันการอ่านยอดผิด',
            style: TextStyle(color: cs.onTertiaryContainer)),
        trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsImportScreen())),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.s});
  final PortfolioSummary s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final due = s.monthlyDue;
    final debts = PayoffDebt.fromPortfolio(s);
    final budget = ref.watch(payoffBudgetProvider).value ?? 0;
    final dueNow = debts.isEmpty ? 0.0 : PayoffPlanner.dueNow(debts, start: s.today);
    final short = budget > 0 && budget < dueNow - 0.005;
    final debtFree = debts.isEmpty || short
        ? null
        : PayoffPlanner.plan(debts, start: s.today, extra: budget > dueNow ? budget - dueNow : 0).months;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ยอดหนี้รวมทั้งหมด', style: t.labelLarge?.copyWith(color: cs.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(fmtMoney(s.totalDebt),
                style: t.headlineMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
            Text(
              'ยอดรูดบัตร ${fmtMoney(s.totalRevolving)} · ยอดผ่อน ${fmtMoney(s.totalInstallment)}',
              style: t.bodySmall?.copyWith(color: cs.onPrimaryContainer),
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 28,
              runSpacing: 14,
              children: [
                StatTile(
                  label: 'ต้องจ่ายเดือนนี้',
                  value: fmtMoney(due.gross),
                  caption: due.remaining <= 0.005
                      ? 'จ่ายครบแล้ว'
                      : due.paid > 0.005
                          ? 'ยังเหลือ ${fmtMoney(due.remaining)}'
                          : 'ขั้นต่ำบัตร + ค่าผ่อน',
                ),
                StatTile(label: 'จ่ายไปแล้วเดือนนี้', value: fmtMoney(s.paidThisMonth), color: cs.positive),
                StatTile(
                  label: 'ดอกเบี้ยโดยประมาณ/เดือน',
                  value: fmtMoney(s.estimatedMonthlyInterest),
                  color: cs.error,
                ),
              ],
            ),
            if (debts.isNotEmpty) ...[
              const SizedBox(height: 10),
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoffPlanScreen())),
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: cs.onPrimaryContainer),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        short
                            ? 'จ่ายหนี้ได้เดือนละ ${fmtMoneyCompact(budget)} ยังไม่พอขั้นต่ำ ${fmtMoneyCompact(dueNow)} · ดูแผนปลดหนี้'
                            : debtFree == null
                                ? 'ตามที่จ่ายอยู่ หนี้ยังไม่หมด · ดูแผนปลดหนี้'
                                : 'ปลดหนี้หมดประมาณ ${fmtMonthYear(addMonths(s.today, debtFree))}'
                                    '${budget > 0 ? ' (จ่ายหนี้เดือนละ ${fmtMoneyCompact(budget)})' : ''}',
                        style: t.bodyMedium?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NextDueCard extends StatelessWidget {
  const _NextDueCard({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = a.daysUntilDue ?? 0;
    final overdue = days < 0;
    final color = overdue ? cs.error : (days <= 3 ? cs.warning : cs.primary);
    final textColor = overdue ? cs.onErrorContainer : null;
    return Card(
      color: overdue ? cs.errorContainer : null,
      child: ListTile(
        leading: Icon(overdue ? Icons.warning_amber : Icons.event_outlined, color: color),
        title: Text(
          '${overdue ? 'เลยกำหนดจ่ายแล้ว' : days <= 7 ? 'ใกล้ครบกำหนด' : 'ครบกำหนดถัดไป'}: ${a.account.name}',
          style: TextStyle(color: textColor, fontWeight: overdue ? FontWeight.w600 : null),
        ),
        subtitle: Text(
          [
            fmtDate(a.nextDueDate!),
            fmtRelativeDays(days),
            if (a.nextDueAmount > 0) fmtMoney(a.nextDueAmount),
          ].join(' · '),
          style: TextStyle(color: textColor),
        ),
        trailing: Icon(Icons.chevron_right, color: textColor),
        onTap: () => openAccount(context, a.account.id),
      ),
    );
  }
}

class _AvalancheCard extends StatefulWidget {
  const _AvalancheCard({required this.s});
  final PortfolioSummary s;

  @override
  State<_AvalancheCard> createState() => _AvalancheCardState();
}

class _AvalancheCardState extends State<_AvalancheCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final target = s.recommendedTarget!;
    final items = s.avalanche;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_down, color: cs.error),
                const SizedBox(width: 8),
                Expanded(child: Text('มีเงินเหลือ โปะอันนี้ก่อน (ดอกแพงสุด)', style: t.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${target.accountName} · ${target.label}', style: t.titleMedium),
            Text(
              'ดอก ${fmtRate(target.effectiveRate)}/ปี · ค้างอยู่ ${fmtMoney(target.balance)}\n'
              'เสียดอกราว ${fmtMoney(target.monthlyInterest)} ต่อเดือน',
              style: t.bodySmall,
            ),
            // avalanche builds fresh DebtItems on each call: compare by id.
            if (items.first.refId != target.refId && items.first.lockedOn(s.today))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${items.first.accountName} · ${items.first.label} ดอกสูงกว่า แต่ยังปิดก่อนกำหนดไม่ได้จนถึง ${fmtDate(items.first.lockedUntil!)}',
                  style: t.bodySmall?.copyWith(color: cs.warning),
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('วางแผนปลดหนี้'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoffPlanScreen())),
                ),
                if (items.length > 1)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? 'ซ่อนลำดับ' : 'ดูลำดับที่ควรโปะ (${items.length})'),
                  ),
              ],
            ),
            if (_expanded)
              for (final (i, d) in items.indexed)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: t.labelSmall)),
                  title: Text('${d.accountName} · ${d.label}'),
                  subtitle: Text([
                    fmtMoney(d.balance),
                    if (d.lockedOn(s.today)) 'ปิดก่อนได้ ${fmtDate(d.lockedUntil!)}',
                  ].join(' · ')),
                  trailing: RateBadge(rate: d.effectiveRate, highlight: i == 0),
                  onTap: () => openAccount(context, d.accountId),
                ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.a, required this.isMostExpensive});
  final AccountSummary a;
  final bool isMostExpensive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final due = a.monthlyDue;
    final days = a.daysUntilDue;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isMostExpensive ? BorderSide(color: cs.error, width: 1.5) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openAccount(context, a.account.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.account.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            a.account.type.label,
                            if (a.account.cardLast4 != null) '•••• ${a.account.cardLast4}',
                            if (a.lines.length > 1) '${a.lines.length} วงเงินย่อย',
                          ].join(' · '),
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  AccountRateBadge(a: a, highlight: isMostExpensive),
                ],
              ),
              if (isMostExpensive)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Pill('ดอกแพงสุด', color: cs.error, icon: Icons.local_fire_department),
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: StatTile(label: 'ยอดคงค้าง', value: fmtMoney(a.totalDebt))),
                  if (due.gross > 0)
                    StatTile(
                      label: 'ต้องจ่ายเดือนนี้',
                      value: due.remaining > 0.005 ? fmtMoney(due.remaining) : 'จ่ายครบแล้ว',
                      color: due.remaining > 0.005 ? null : cs.positive,
                    ),
                ],
              ),
              if (a.creditLimit > 0) ...[
                const SizedBox(height: 10),
                UsageBar(used: a.usedLimit, limit: a.creditLimit),
                const SizedBox(height: 4),
                Text('ใช้ไป ${fmtMoney(a.usedLimit)} จากวงเงิน ${fmtMoney(a.creditLimit)}', style: t.bodySmall),
              ],
              if (a.nextDueDate != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      days! < 0 ? Icons.warning_amber : Icons.event,
                      size: 16,
                      color: days < 0 ? cs.error : (days <= 3 ? cs.warning : cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${days < 0 ? 'เลยกำหนด' : 'ครบกำหนด'} ${fmtDate(a.nextDueDate!)} (${fmtRelativeDays(days)})',
                        style: t.bodySmall?.copyWith(
                          color: days < 0 ? cs.error : null,
                          fontWeight: days < 0 ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (a.activePlans.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.view_timeline_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(child: Text('ผ่อนอยู่ ${a.activePlans.length} รายการ', style: t.bodySmall)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
