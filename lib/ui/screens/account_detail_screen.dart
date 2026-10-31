import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../domain/finance/installment_engine.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_fields.dart';
import 'account_form_screen.dart';
import 'calculator_screen.dart';
import 'payment_form_screen.dart';
import 'plan_form_screen.dart';
import 'schedule_screen.dart';
import 'statement_sheet.dart';

void openAccount(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: id)));

class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    final a = portfolio.value?.byId(accountId);
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.account.name ?? ''),
        actions: [
          if (a != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: a)));
                } else if (v == 'delete') {
                  final ok = await confirmDialog(
                    context,
                    title: 'ลบ ${a.account.name}?',
                    message: 'วงเงินย่อย รายการผ่อน และประวัติการจ่ายของบัญชีนี้จะถูกลบทั้งหมด',
                    confirmLabel: 'ลบ',
                    destructive: true,
                  );
                  if (!ok) return;
                  await ref.read(ledgerProvider).deleteAccount(a.account.id);
                  ref.refreshData();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('แก้ไขข้อมูลบัตร')),
                PopupMenuItem(value: 'delete', child: Text('ลบบัตร/สินเชื่อนี้')),
              ],
            ),
        ],
      ),
      floatingActionButton: a == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('บันทึกการจ่าย'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PaymentFormScreen(accountId: a.account.id)),
              ),
            ),
      body: AsyncBody(
        value: portfolio,
        builder: (_) {
          if (a == null) return const EmptyState(icon: Icons.search_off, title: 'ไม่พบข้อมูล');
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _OverviewCard(a: a),
              _StatementCard(a: a),
              SectionHeader('วงเงินย่อย (${a.lines.length})'),
              for (final l in a.lines) _LineTile(a: a, line: l),
              SectionHeader(
                'รายการผ่อน',
                trailing: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่ม'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PlanFormScreen(account: a)),
                  ),
                ),
              ),
              if (a.plans.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text('ยังไม่มีรายการผ่อน — เพิ่มได้ทั้งของที่ผ่อน 0% และสินเชื่อก้อนที่ผ่อนเป็นงวด'),
                ),
              for (final p in a.plans) _PlanCard(a: a, p: p),
              SectionHeader('ประวัติการจ่าย (${a.payments.length})'),
              if (a.payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text('ยังไม่มีการบันทึกการจ่าย'),
                ),
              for (final p in a.payments) PaymentTile(payment: p, summary: a),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(label: 'ยอดคงค้างทั้งหมด', value: fmtMoney(a.totalDebt)),
                ),
                RateBadge(rate: a.topRate),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                StatTile(label: 'หมุนเวียน', value: fmtMoney(a.revolvingBalance)),
                StatTile(label: 'ผ่อนชำระ', value: fmtMoney(a.installmentBalance)),
                StatTile(label: 'ดอกราว/เดือน', value: fmtMoney(a.estimatedMonthlyInterest), color: cs.error),
              ],
            ),
            if (a.creditLimit > 0) ...[
              const SizedBox(height: 12),
              UsageBar(used: a.usedLimit, limit: a.creditLimit),
              const SizedBox(height: 4),
              Text(
                'ใช้ไป ${fmtMoney(a.usedLimit)} · คงเหลือ ${fmtMoney(a.availableLimit)} · วงเงิน ${fmtMoney(a.creditLimit)}'
                '${a.account.sharedLimit != null ? ' (ใช้ร่วมกัน)' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (a.account.note != null && a.account.note!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(a.account.note!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context) {
    final acc = a.account;
    final cs = Theme.of(context).colorScheme;
    final stmtDue = a.statementDueDate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ยอดเรียกเก็บงวดล่าสุด', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (acc.statementDate == null)
              const Text('ยังไม่ได้บันทึกยอดเรียกเก็บ')
            else ...[
              InfoRow('วันที่ออกใบแจ้งยอด', fmtDate(acc.statementDate!)),
              InfoRow('ยอดเรียกเก็บ', fmtMoney(acc.statementBalance), bold: true),
              InfoRow('ยอดขั้นต่ำ', fmtMoney(acc.minimumPayment)),
              if (stmtDue != null) InfoRow('ครบกำหนดชำระ', fmtDate(stmtDue)),
              InfoRow('จ่ายแล้วตั้งแต่ออกใบแจ้งยอด', fmtMoney(a.paidTowardStatement), valueColor: cs.positive),
              InfoRow(
                'ขั้นต่ำคงเหลือ',
                a.isStatementPaid ? 'จ่ายครบแล้ว' : fmtMoney(a.minimumOutstanding),
                valueColor: a.isStatementPaid ? cs.positive : cs.error,
                bold: true,
              ),
              InfoRow('เต็มยอดคงเหลือ', fmtMoney(a.statementOutstanding)),
            ],
            InfoRow(
              'รอบบิล',
              [
                acc.billingDay == null ? 'ตัดรอบ: ไม่ระบุ' : 'ตัดรอบทุกวันที่ ${acc.billingDay}',
                acc.dueDay == null ? 'ครบกำหนด: ไม่ระบุ' : 'ครบกำหนดทุกวันที่ ${acc.dueDay}',
              ].join(' · '),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('อัปเดตยอดเรียกเก็บ'),
                onPressed: () => showStatementSheet(context, a),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.a, required this.line});
  final AccountSummary a;
  final CreditLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = a.usedOnLine(line);
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _editBalance(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(line.name, style: t.titleSmall)),
                  RateBadge(rate: line.annualRate, method: line.interestMethod),
                ],
              ),
              const SizedBox(height: 8),
              InfoRow('ยอดคงค้าง (ไม่รวมรายการผ่อน)', fmtMoney(line.balance), bold: true),
              if (used > line.balance + 0.005) InfoRow('ใช้วงเงินรวมรายการผ่อน', fmtMoney(used)),
              if (line.creditLimit > 0) ...[
                InfoRow('วงเงิน', fmtMoney(line.creditLimit)),
                const SizedBox(height: 4),
                UsageBar(used: used, limit: line.creditLimit),
              ],
              Row(
                children: [
                  Expanded(child: Text('แตะเพื่อแก้ยอดคงค้าง', style: t.bodySmall)),
                  TextButton.icon(
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text('เพิ่มยอดใช้จ่าย'),
                    onPressed: () => _addSpending(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editBalance(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: amountToField(line.balance));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ยอดคงค้าง: ${line.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AmountField(controller: controller, label: 'ยอดคงค้างล่าสุด', autofocus: true),
            const SizedBox(height: 8),
            const Text(
              'ใช้ตัวเลขจากแอพธนาคาร/ใบแจ้งยอด (ไม่รวมยอดผ่อนที่บันทึกเป็นรายการผ่อนไว้แล้ว)',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseAmount(controller.text)),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref.read(ledgerProvider).setLineBalance(line.id, value);
    ref.refreshData();
  }

  /// Adds one purchase on top of the balance, so the user doesn't have to
  /// work out the new total like [_editBalance] needs.
  Future<void> _addSpending(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('เพิ่มยอดใช้จ่าย: ${line.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AmountField(controller: controller, label: 'ยอดที่ใช้', required: true, allowZero: false, autofocus: true),
              const SizedBox(height: 8),
              Text(
                'บวกเพิ่มจากยอดคงค้างตอนนี้ ${fmtMoney(line.balance)} '
                '— ถ้าแบ่งจ่ายเป็นงวด ให้ใช้ "เพิ่มรายการผ่อน" แทน',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, parseAmount(controller.text));
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    await ref.read(ledgerProvider).addSpending(line.id, amount);
    ref.refreshData();
    if (context.mounted) {
      showSnack(context, 'เพิ่มยอดใช้จ่าย ${fmtMoney(amount)} แล้ว · ยอดคงค้าง ${fmtMoney(line.balance + amount)}');
    }
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.a, required this.p});
  final AccountSummary a;
  final InstallmentState p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final plan = p.plan;
    final locked = p.isLockedOn(DateTime.now());
    final next = p.nextRow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(plan.name, style: t.titleMedium)),
                RateBadge(rate: plan.annualRate, method: plan.interestMethod),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => PlanFormScreen(account: a, existing: plan)));
                    } else if (v == 'delete') {
                      final ok = await confirmDialog(context,
                          title: 'ลบรายการผ่อน "${plan.name}"?',
                          message: 'ประวัติการจ่ายยังอยู่ แต่จะไม่ผูกกับรายการผ่อนนี้แล้ว',
                          confirmLabel: 'ลบ',
                          destructive: true);
                      if (!ok) return;
                      await ref.read(ledgerProvider).deletePlan(plan.id);
                      ref.refreshData();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                    PopupMenuItem(value: 'delete', child: Text('ลบ')),
                  ],
                ),
              ],
            ),
            if (plan.interestMethod == InterestMethod.flat)
              Text('อัตราที่แท้จริง (ลดต้นลดดอก) ≈ ${fmtPercent(p.effectiveAnnualRate)}/ปี',
                  style: t.bodySmall?.copyWith(color: cs.error)),
            const SizedBox(height: 10),
            if (p.isClosed)
              Pill('ปิดยอดแล้ว', color: cs.positive, icon: Icons.check_circle)
            else ...[
              Text('งวดที่จ่ายแล้ว ${p.paidInstallments}/${p.paidInstallments + p.remainingInstallments}',
                  style: t.bodySmall),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(value: p.progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
              ),
            ],
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  InfoRow('เงินต้นคงเหลือ', fmtMoney(p.remainingPrincipal), bold: true),
                  if (!p.isClosed) ...[
                    InfoRow('ค่าผ่อน/เดือน', fmtMoney(p.currentPayment)),
                    InfoRow('เหลืออีก', fmtMonths(p.remainingInstallments)),
                    if (next?.dueDate != null) InfoRow('งวดถัดไป', '${fmtDate(next!.dueDate!)} · ${fmtMoney(next.payment)}'),
                    if (p.projectedPayoffDate != null) InfoRow('ปิดยอดตามแผน', fmtDate(p.projectedPayoffDate!)),
                  ],
                  InfoRow('ดอกที่จ่ายไปแล้ว', fmtMoney(p.interestPaid)),
                  if (!p.isClosed) InfoRow('ดอกที่ต้องจ่ายอีก', fmtMoney(p.projectedRemainingInterest), valueColor: cs.error),
                  if (p.extraPaid > 0) InfoRow('โปะเพิ่มไปแล้ว', fmtMoney(p.extraPaid), valueColor: cs.positive),
                  if (p.interestSavedSoFar > 0.5)
                    InfoRow('ประหยัดดอกจากการโปะ', fmtMoney(p.interestSavedSoFar), valueColor: cs.positive),
                  if (p.earliestClosureDate != null)
                    InfoRow(
                      'ปิดก่อนกำหนดได้เร็วสุด',
                      locked ? '${fmtDate(p.earliestClosureDate!)} (ติด lock-in)' : '${fmtDate(p.earliestClosureDate!)} (พ้นแล้ว)',
                      valueColor: locked ? cs.warning : cs.positive,
                    ),
                  if (!p.isClosed && (plan.penaltyPercent > 0 || plan.penaltyFixed > 0))
                    InfoRow('ยอดปิดวันนี้ (รวมค่าปรับ ${fmtMoney(p.earlyClosurePenalty)})', fmtMoney(p.payoffAmount)),
                  if (plan.includedInStatement)
                    const InfoRow('การชำระ', 'รวมในยอดเรียกเก็บบัตร (เดินงวดอัตโนมัติ)'),
                ],
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.table_rows_outlined),
                  label: const Text('ตารางผ่อน'),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ScheduleScreen(accountId: a.account.id, planId: plan.id))),
                ),
                if (!p.isClosed)
                  TextButton.icon(
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('คำนวณโปะ'),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => CalculatorScreen(initialPlanId: plan.id))),
                  ),
                if (!p.isClosed && !plan.includedInStatement)
                  TextButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('จ่ายงวดนี้'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentFormScreen(
                          accountId: a.account.id,
                          planId: plan.id,
                          type: PaymentType.installment,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of payment history; long-press or the menu deletes it.
class PaymentTile extends ConsumerWidget {
  const PaymentTile({super.key, required this.payment, required this.summary, this.showAccount = false});
  final Payment payment;
  final AccountSummary summary;
  final bool showAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    String? target;
    for (final s in summary.plans) {
      if (s.plan.id == p.planId) target = s.plan.name;
    }
    for (final l in summary.lines) {
      if (l.id == p.creditLineId && p.planId == null) target = l.name;
    }
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: p.type == PaymentType.extra ? cs.tertiaryContainer : cs.secondaryContainer,
        child: Icon(
          switch (p.type) {
            PaymentType.extra => Icons.rocket_launch_outlined,
            PaymentType.installment => Icons.event_repeat,
            PaymentType.full => Icons.done_all,
            PaymentType.minimum => Icons.south,
            PaymentType.other => Icons.payments_outlined,
          },
          size: 20,
        ),
      ),
      title: Text('${fmtMoney(p.amount)} · ${p.type.label}'),
      subtitle: Text([
        fmtDate(p.date),
        if (showAccount) summary.account.name,
        ?target,
        if (p.prepaymentMode != null && p.type == PaymentType.extra) p.prepaymentMode!.label,
        if (p.source != PaymentSource.manual) 'จาก ${p.source.label}',
        if (p.note != null && p.note!.isNotEmpty) p.note!,
      ].join(' · ')),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'ลบ',
        onPressed: () => _delete(context, ref),
      ),
      onLongPress: () => _delete(context, ref),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'ลบรายการจ่ายนี้?',
      message: '${fmtMoney(payment.amount)} เมื่อ ${fmtDate(payment.date)} — ยอดคงค้างจะถูกคืนค่ากลับ',
      confirmLabel: 'ลบ',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(ledgerProvider).deletePayment(payment.id);
    ref.refreshData();
  }
}
