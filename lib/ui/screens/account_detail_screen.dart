import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../data/services/ledger_service.dart';
import '../../domain/finance/installment_engine.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/credit_line.dart';
import '../../domain/models/recurring_charge.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/spending.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/card_colors.dart';
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
      body: AsyncBody(
        value: portfolio,
        builder: (_) {
          if (a == null) return const EmptyState(icon: Icons.search_off, title: 'ไม่พบข้อมูล');
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _DueCard(a: a),
              _QuickActions(a: a),
              CardColorTheme(color: a.account.color, child: _OverviewCard(a: a)),
              SectionHeader(a.lines.length > 1 ? 'วงเงินย่อย (${a.lines.length})' : 'วงเงิน'),
              for (final l in a.lines) _LineTile(a: a, line: l),
              if (a.lines.isNotEmpty) _RecurringSection(a: a),
              if (a.spendings.isNotEmpty) _SpendingSection(a: a),
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

/// What to pay next and by when: the open statement and separately billed
/// installments, with the statement details kept small underneath.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context) {
    final acc = a.account;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final stmtDue = a.statementDueDate;
    final hasStatement = acc.statementDate != null;
    final stmtOpen = hasStatement && !a.isStatementPaid;
    final planDues = [
      for (final p in a.activePlans)
        if (!p.plan.includedInStatement && p.nextRow?.dueDate != null)
          (name: p.plan.name, date: p.nextRow!.dueDate!, amount: p.nextRow!.payment),
    ];
    final dates = [if (stmtOpen && stmtDue != null) stmtDue, for (final d in planDues) d.date]..sort();
    final first = dates.isEmpty ? null : dates.first;
    final days = first == null ? null : daysBetween(a.today, first);
    final overdue = days != null && days < 0;
    final fg = overdue ? cs.onErrorContainer : cs.onPrimaryContainer;
    final accent = overdue ? cs.error : (days != null && days <= 3 ? cs.warning : fg);
    // Dates other than the headline one are shown next to their amount.
    String on(DateTime? d) => d == null || d == first ? '' : ' (${fmtDateShort(d)})';
    final headline = t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600);
    final small = t.bodySmall?.copyWith(color: fg);
    final cycle = [
      if (acc.billingDay != null) 'ตัดรอบทุกวันที่ ${acc.billingDay}',
      if (acc.dueDay != null) 'ครบกำหนดทุกวันที่ ${acc.dueDay}',
    ].join(' · ');

    return Card(
      color: overdue ? cs.errorContainer : cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (first != null)
              Row(
                children: [
                  Icon(overdue ? Icons.warning_amber : Icons.event, color: accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${overdue ? 'เลยกำหนดจ่าย' : 'ต้องจ่ายภายใน'} ${fmtDate(first)}', style: headline)),
                  Pill(fmtRelativeDays(days!), color: accent),
                ],
              )
            else
              Row(
                children: [
                  Icon(
                    !hasStatement && acc.type == AccountType.creditCard ? Icons.info_outline : Icons.check_circle,
                    color: !hasStatement && acc.type == AccountType.creditCard ? fg : cs.positive,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasStatement
                          ? (a.statementOutstanding > 0.005 ? 'จ่ายขั้นต่ำงวดนี้ครบแล้ว' : 'จ่ายบิลงวดนี้ครบแล้ว')
                          : acc.type == AccountType.creditCard
                              ? 'ยังไม่ได้บันทึกยอดบิล'
                              : 'ไม่มียอดต้องจ่ายตอนนี้',
                      style: headline,
                    ),
                  ),
                ],
              ),
            if (stmtOpen) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'ขั้นต่ำ${on(stmtDue)}', value: fmtMoney(a.minimumOutstanding), color: fg)),
                  Expanded(child: StatTile(label: 'หรือจ่ายเต็มยอด', value: fmtMoney(a.statementOutstanding), color: fg)),
                ],
              ),
              if (a.paidTowardStatement > 0.005)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('จ่ายแล้ว ${fmtMoney(a.paidTowardStatement)} ตั้งแต่ออกใบแจ้งยอด',
                      style: t.bodySmall?.copyWith(color: cs.positive)),
                ),
            ],
            if (planDues.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final d in planDues) InfoRow('ค่าผ่อน ${d.name}${on(d.date)}', fmtMoney(d.amount), valueColor: fg, bold: true),
            ],
            if (hasStatement && !stmtOpen && first != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('บิลบัตร: จ่ายขั้นต่ำครบแล้ว', style: t.bodySmall?.copyWith(color: cs.positive)),
              ),
            if (hasStatement && !stmtOpen && a.statementOutstanding > 0.005)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('ยังเหลือเต็มยอด ${fmtMoney(a.statementOutstanding)}', style: t.bodyMedium?.copyWith(color: fg)),
              ),
            if (!hasStatement && first == null && acc.type == AccountType.creditCard)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('กด "อัปเดตยอดบิล" เมื่อได้ใบแจ้งยอดหรือ SMS จากธนาคาร', style: small),
              ),
            if (hasStatement || cycle.isNotEmpty) ...[
              Divider(height: 24, color: fg.withValues(alpha: 0.2)),
              if (hasStatement)
                Text('ใบแจ้งยอด ${fmtDate(acc.statementDate!)} · ยอดบิล ${fmtMoney(acc.statementBalance)}', style: small),
              if (cycle.isNotEmpty) Text(cycle, style: small),
            ],
          ],
        ),
      ),
    );
  }
}

/// The things done most often on a card, in one place.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    Widget action(IconData icon, String label, VoidCallback? onPressed, {bool primary = false}) {
      final child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center)],
      );
      return Expanded(
        child: primary
            ? FilledButton(style: style, onPressed: onPressed, child: child)
            : FilledButton.tonal(style: style, onPressed: onPressed, child: child),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        spacing: 8,
        children: [
          action(
            Icons.payments_outlined,
            'บันทึกการจ่าย',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PaymentFormScreen(accountId: a.account.id)),
            ),
            primary: true,
          ),
          action(
            a.account.type == AccountType.cashCard ? Icons.local_atm : Icons.add_shopping_cart,
            'เพิ่มยอด${a.account.type.spendingWord}',
            a.lines.isEmpty ? null : () => _spendingDialog(context, ref, a),
          ),
          action(Icons.edit_note, 'อัปเดตยอดบิล', () => showStatementSheet(context, a)),
        ],
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
    final interest = a.estimatedMonthlyInterest;
    final coming = a.comingInstallments;
    return Card(
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
                AccountRateBadge(a: a),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                StatTile(label: a.account.type.revolvingLabel, value: fmtMoney(a.revolvingBalance)),
                if (a.plans.isNotEmpty) StatTile(label: 'ยอดผ่อน', value: fmtMoney(a.installmentBalance)),
                StatTile(
                  label: 'ดอกราว/เดือน',
                  value: fmtMoney(interest),
                  color: interest > 0.005 ? cs.error : null,
                ),
              ],
            ),
            if (a.creditLimit > 0) ...[
              const SizedBox(height: 12),
              UsageBar(used: a.usedLimit, limit: a.creditLimit),
              const SizedBox(height: 4),
              Text(
                'ใช้วงเงินไป ${fmtMoney(a.usedLimit)} จาก ${fmtMoney(a.creditLimit)}'
                '${a.account.sharedLimit != null ? ' (ใช้ร่วมกัน)' : ''} · เหลือใช้ได้ ${fmtMoney(a.availableLimit)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (a.spendingSinceCutoff > 0.005) ...[
              const SizedBox(height: 10),
              InfoRow('รอเรียกเก็บรอบหน้า', fmtMoney(a.spendingSinceCutoff)),
              Text(
                'รายการที่บันทึกไว้หลังตัดรอบ ${fmtDate(a.lastCutoff!)} · รวมอยู่ใน${a.account.type.revolvingLabel}แล้ว'
                '${a.nextCutoff == null ? '' : ' จะเข้าบิลรอบ ${fmtDate(a.nextCutoff!)}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (coming.isNotEmpty) ...[
              const SizedBox(height: 10),
              InfoRow('ค่างวดที่บัตรยังไม่แจ้ง', fmtMoney(coming.fold(0.0, (s, r) => s + r.payment))),
              Text(
                '${coming.length} งวด รวมดอกแล้ว · แอพจะบวกเข้า${a.account.type.revolvingLabel}ทีละงวดทุกวันตัดรอบ'
                ' งวดถัดไป ${fmtDate(coming.first.dueDate!)} ${fmtMoney(coming.first.payment)}',
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

class _LineTile extends ConsumerWidget {
  const _LineTile({required this.a, required this.line});
  final AccountSummary a;
  final CreditLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = a.usedOnLine(line);
    final onPlans = used - math.max(0, line.balance);
    final label = a.account.type.revolvingLabel;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
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
              InfoRow(label, fmtMoney(line.balance), bold: true),
              if (line.creditLimit > 0) ...[
                const SizedBox(height: 6),
                UsageBar(used: used, limit: line.creditLimit),
                const SizedBox(height: 4),
                Text(
                  'ใช้วงเงินไป ${fmtMoney(used)} จาก ${fmtMoney(line.creditLimit)}'
                  '${onPlans > 0.005 ? ' · รวมยอดผ่อน ${fmtMoney(onPlans)}' : ''}',
                  style: t.bodySmall,
                ),
              ] else if (onPlans > 0.005)
                InfoRow('ยอดผ่อนบนวงเงินนี้', fmtMoney(onPlans)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.edit_outlined, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      line.balanceAsOf == null
                          ? 'แตะเพื่อแก้$labelให้ตรงกับแอพธนาคาร'
                          : 'อัปเดตตามแอพธนาคารล่าสุด ${fmtDate(line.balanceAsOf!)} · แตะเพื่อแก้',
                      style: t.bodySmall?.copyWith(color: muted),
                    ),
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
        title: Text('${a.account.type.revolvingLabel}: ${line.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AmountField(controller: controller, label: 'ยอดล่าสุด', autofocus: true),
            const SizedBox(height: 8),
            Text(
              'ดูจากแอพธนาคารหรือใบแจ้งยอด ค่างวดที่บัตรแจ้งแล้วรวมได้ แต่ไม่ต้องรวมงวดที่ยังไม่แจ้ง\n'
              'ยอด${a.account.type.spendingWord}และการจ่ายที่ลงวันที่ก่อนวันนี้ จะถือว่ารวมอยู่ในยอดนี้แล้ว ไม่บวกหรือหักซ้ำ',
              style: const TextStyle(fontSize: 12),
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
}

/// Adds one purchase on top of a sub-limit's balance, so the user doesn't
/// have to work out the new total like editing the balance needs. With
/// [existing], corrects that entry instead.
Future<void> _spendingDialog(BuildContext context, WidgetRef ref, AccountSummary a, {Spending? existing}) async {
  final label = a.account.type.revolvingLabel;
  final word = a.account.type.spendingWord;
  final amountCtl = TextEditingController(text: amountToField(existing?.amount));
  final noteCtl = TextEditingController(text: existing?.note ?? '');
  final formKey = GlobalKey<FormState>();
  final today = dateOnly(DateTime.now());
  var line = a.lines.firstWhere((l) => l.id == existing?.creditLineId, orElse: () => a.lines.first);
  var date = existing?.date ?? DateTime.now();
  bool? included; // the user's answer to "already in the balance"; null = guess
  bool sameLine() => existing != null && line.id == existing.creditLineId;
  // A balance typed in from the bank after the entry was recorded replaced
  // whatever it did, so editing it can't change the balance.
  bool replacedByBank() => sameLine() && line.typedInAfter(existing!.createdAt);
  // Anything backdated may already be in a balance copied from the bank app.
  bool ask() => !replacedByBank() && (existing != null || line.mayCount(date) || dateOnly(date).isBefore(today));
  bool skip() =>
      ask() && (included ?? (sameLine() ? existing!.lineBalanceApplied < 0.005 : line.alreadyCounts(date)));
  // The sub-limit balance once saved.
  double after() {
    if (replacedByBank()) return line.balance;
    final back = sameLine() ? existing!.lineBalanceApplied : 0.0;
    return math.max(0.0, line.balance - back) + (skip() ? 0 : parseAmount(amountCtl.text) ?? 0);
  }

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'เพิ่มยอด$word' : 'แก้ไขยอด$word'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.lines.length > 1) ...[
                  DropdownButtonFormField<CreditLine>(
                    initialValue: line,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ใช้จากวงเงิน'),
                    items: [for (final l in a.lines) DropdownMenuItem(value: l, child: Text(l.name))],
                    onChanged: (l) => setState(() {
                      line = l ?? line;
                      included = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                AmountField(
                  controller: amountCtl,
                  label: a.account.type == AccountType.cashCard ? 'ยอดที่กด' : 'ยอดที่ใช้',
                  required: true,
                  allowZero: false,
                  autofocus: existing == null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteCtl,
                  decoration: InputDecoration(
                    labelText: 'รายละเอียด',
                    hintText: a.account.type == AccountType.cashCard ? 'เอาไปใช้อะไร เช่น ค่าซ่อมรถ' : 'จ่ายค่าอะไร เช่น ค่าอาหาร',
                  ),
                ),
                const SizedBox(height: 12),
                DateField(
                  value: date,
                  label: 'วันที่$word',
                  onChanged: (d) => setState(() {
                    date = d ?? date;
                    included = null;
                  }),
                ),
                if (ask())
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: skip(),
                    onChanged: (v) => setState(() => included = v),
                    title: Text(line.balanceAsOf == null
                        ? '$labelที่กรอกไว้รวมรายการนี้แล้ว'
                        : '$labelที่แก้ไว้เมื่อ ${fmtDate(line.balanceAsOf!)} รวมรายการนี้แล้ว'),
                    subtitle: const Text('เปิดไว้ = เก็บเข้าประวัติอย่างเดียว ไม่บวกซ้ำ'),
                  ),
                const SizedBox(height: 8),
                Text(
                  replacedByBank()
                      ? '$labelแก้ตามแอพธนาคารหลังบันทึกรายการนี้แล้ว — แก้รายการนี้จะไม่เปลี่ยน$label (${fmtMoney(line.balance)})'
                      : existing != null
                          ? '$label ${fmtMoney(line.balance)} → ${fmtMoney(after())}'
                          : skip()
                              ? 'ไม่บวกเพิ่ม — $labelยังเป็น ${fmtMoney(line.balance)}'
                              : 'บวกเพิ่มจาก$labelตอนนี้ ${fmtMoney(line.balance)} '
                                  '— ถ้าแบ่งจ่ายเป็นงวด ให้ใช้ "เพิ่มรายการผ่อน" แทน',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final amount = parseAmount(amountCtl.text)!;
  final note = noteCtl.text.trim();
  final balanceAfter = after();
  final draft = Spending(
    id: existing?.id ?? newId(),
    accountId: line.accountId,
    creditLineId: line.id,
    date: date,
    amount: amount,
    note: note.isEmpty ? null : note,
    source: existing?.source ?? PaymentSource.manual,
    createdAt: existing?.createdAt ?? DateTime.now(),
  );
  final ledger = ref.read(ledgerProvider);
  final s = existing == null
      ? await ledger.recordSpending(draft, alreadyInBalance: skip())
      : await ledger.updateSpending(draft, alreadyInBalance: skip());
  ref.refreshData();
  if (context.mounted) {
    showSnack(
      context,
      existing != null
          ? 'แก้ไขยอด$wordแล้ว · $label ${fmtMoney(balanceAfter)}'
          : s.lineBalanceApplied > 0
              ? 'เพิ่มยอด$word ${fmtMoney(amount)} แล้ว · $label ${fmtMoney(balanceAfter)}'
              : 'บันทึกยอด$word ${fmtMoney(amount)} แล้ว · $labelรวมรายการนี้อยู่แล้ว ไม่บวกซ้ำ',
    );
  }
}

/// Card charges that repeat (Netflix and the like); each time one comes due
/// it is recorded as spending.
class _RecurringSection extends ConsumerWidget {
  const _RecurringSection({required this.a});
  final AccountSummary a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          a.recurring.isEmpty ? 'รายการหักประจำ' : 'รายการหักประจำ (${a.recurring.length})',
          trailing: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('เพิ่ม'),
            onPressed: () => _recurringDialog(context, ref, a),
          ),
        ),
        if (a.recurring.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text('ยังไม่มี — เช่น Netflix หรือ Spotify ที่หักบัตรทุกเดือน แอพจะบันทึกเป็นยอดใช้จ่ายให้เองทุกรอบ'),
          ),
        for (final c in a.recurring) _RecurringTile(a: a, charge: c),
      ],
    );
  }
}

String _schedule(RecurrenceInterval interval, int day, int month) => interval == RecurrenceInterval.monthly
    ? 'ทุกเดือน วันที่ $day'
    : 'ทุกปี วันที่ $day ${thaiMonthsLong[month - 1]}';

class _RecurringTile extends ConsumerWidget {
  const _RecurringTile({required this.a, required this.charge});
  final AccountSummary a;
  final RecurringCharge charge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = charge;
    String? lineName;
    if (a.lines.length > 1) {
      for (final l in a.lines) {
        if (l.id == c.creditLineId) lineName = l.name;
      }
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.autorenew, size: 20),
      ),
      title: Text('${fmtMoney(c.amount)} · ${c.name}'),
      subtitle: Text([
        [_schedule(c.interval, c.anchorDay, c.nextDate.month), ?lineName].join(' · '),
        c.active ? 'ครั้งถัดไป ${fmtDate(c.nextDate)}' : 'หยุดหักไว้',
      ].join('\n')),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        tooltip: 'ตัวเลือก ${c.name}',
        onSelected: (v) {
          if (v == 'edit') {
            _recurringDialog(context, ref, a, existing: c);
          } else if (v == 'pause') {
            _togglePause(context, ref);
          } else {
            _delete(context, ref);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
          PopupMenuItem(value: 'pause', child: Text(c.active ? 'หยุดหักชั่วคราว' : 'เริ่มหักต่อ')),
          const PopupMenuItem(value: 'delete', child: Text('ลบ')),
        ],
      ),
      onTap: () => _recurringDialog(context, ref, a, existing: c),
    );
  }

  /// Resuming skips the charges that fell while it was paused.
  Future<void> _togglePause(BuildContext context, WidgetRef ref) async {
    final today = dateOnly(DateTime.now());
    var next = charge.nextDate;
    while (next.isBefore(today)) {
      next = charge.following(next);
    }
    final updated = charge.active ? charge.copyWith(active: false) : charge.copyWith(active: true, nextDate: next);
    await ref.read(ledgerProvider).saveRecurring(updated);
    ref.refreshData();
    if (context.mounted) {
      showSnack(
        context,
        updated.active
            ? 'เริ่มหัก ${charge.name} ต่อ · ครั้งถัดไป ${fmtDate(next)}'
            : 'หยุดหัก ${charge.name} ไว้ · จะไม่บันทึกจนกว่าจะเริ่มหักต่อ',
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'ลบ ${charge.name}?',
      message: 'แอพจะหยุดบันทึกรายการนี้ ยอดใช้จ่ายที่บันทึกไปแล้วยังอยู่ในประวัติ',
      confirmLabel: 'ลบ',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(ledgerProvider).deleteRecurring(charge.id);
    ref.refreshData();
  }
}

/// Sets up (or, with [existing], changes) a charge that repeats on the card.
/// Recording starts from the next charge: earlier ones are already in the
/// bank's figures or were added by hand.
Future<void> _recurringDialog(BuildContext context, WidgetRef ref, AccountSummary a, {RecurringCharge? existing}) async {
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final amountCtl = TextEditingController(text: amountToField(existing?.amount));
  final formKey = GlobalKey<FormState>();
  final today = dateOnly(DateTime.now());
  var line = a.lines.firstWhere((l) => l.id == existing?.creditLineId, orElse: () => a.lines.first);
  var interval = existing?.interval ?? RecurrenceInterval.monthly;
  // A paused charge can sit in the past; the picker starts at today.
  DateTime? next = existing == null ? null : (existing.nextDate.isBefore(today) ? today : existing.nextDate);
  var dateMissing = false;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'เพิ่มรายการหักประจำ' : 'แก้ไขรายการหักประจำ'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: nameCtl,
                  autofocus: existing == null,
                  decoration: const InputDecoration(labelText: 'ชื่อรายการ', hintText: 'เช่น Netflix'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'กรุณากรอก' : null,
                ),
                const SizedBox(height: 12),
                AmountField(controller: amountCtl, label: 'ยอดที่หักต่อรอบ', required: true, allowZero: false),
                if (a.lines.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CreditLine>(
                    initialValue: line,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'หักจากวงเงิน'),
                    items: [for (final l in a.lines) DropdownMenuItem(value: l, child: Text(l.name))],
                    onChanged: (l) => setState(() => line = l ?? line),
                  ),
                ],
                const SizedBox(height: 12),
                SegmentedButton<RecurrenceInterval>(
                  segments: [
                    for (final i in RecurrenceInterval.values) ButtonSegment(value: i, label: Text(i.label)),
                  ],
                  selected: {interval},
                  onSelectionChanged: (v) => setState(() => interval = v.first),
                ),
                const SizedBox(height: 12),
                DateField(
                  value: next,
                  label: 'หักครั้งถัดไป',
                  firstDate: today,
                  onChanged: (d) => setState(() {
                    next = d ?? next;
                    dateMissing = false;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  next == null
                      ? 'เลือกวันที่บัตรจะถูกหักครั้งถัดไป'
                      : 'หัก${_schedule(interval, next!.day, next!.month)}'
                          '${interval == RecurrenceInterval.monthly && next!.day > 28 ? ' (เดือนที่ไม่มีวันนี้ หักวันสุดท้ายของเดือน)' : ''}'
                          ' · แอพจะบันทึกเป็นยอดใช้จ่ายให้เองตั้งแต่ ${fmtDate(next!)} รอบที่ผ่านมาแล้วไม่บันทึกย้อนหลัง',
                  style: TextStyle(
                    fontSize: 12,
                    color: dateMissing ? Theme.of(ctx).colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              final ok = formKey.currentState!.validate();
              setState(() => dateMissing = next == null);
              if (ok && next != null) Navigator.pop(ctx, true);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final date = next!;
  final name = nameCtl.text.trim();
  final charge = RecurringCharge(
    id: existing?.id ?? newId(),
    accountId: a.account.id,
    creditLineId: line.id,
    name: name,
    amount: parseAmount(amountCtl.text)!,
    interval: interval,
    nextDate: date,
    // Unchanged date: keep the day it really falls on (e.g. 31 after February).
    anchorDay: existing != null && date == existing.nextDate ? existing.anchorDay : date.day,
    active: existing?.active ?? true,
    createdAt: existing?.createdAt ?? DateTime.now(),
  );
  await ref.read(ledgerProvider).saveRecurring(charge);
  // Recording a charge due today happens on this refresh.
  ref.refreshData();
  if (context.mounted) {
    final when = date.isAfter(today)
        ? 'หักครั้งถัดไป ${fmtDate(date)}'
        : 'บันทึกยอดของวันนี้แล้ว · ครั้งถัดไป ${fmtDate(charge.following(date))}';
    showSnack(context, '${existing == null ? 'เพิ่ม' : 'แก้ไข'} $name แล้ว · $when');
  }
}

/// Spending history of one account; long lists start collapsed.
class _SpendingSection extends StatefulWidget {
  const _SpendingSection({required this.a});
  final AccountSummary a;

  @override
  State<_SpendingSection> createState() => _SpendingSectionState();
}

class _SpendingSectionState extends State<_SpendingSection> {
  static const _collapsedCount = 3;
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.a.spendings;
    final shown = _expanded ? all : all.take(_collapsedCount);
    return Column(
      children: [
        SectionHeader(
          'ประวัติการ${widget.a.account.type.spendingWord} (${all.length})',
          trailing: all.length <= _collapsedCount
              ? null
              : TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'ย่อ' : 'ดูทั้งหมด'),
                ),
        ),
        for (final s in shown) SpendingTile(spending: s, summary: widget.a),
      ],
    );
  }
}

class SpendingTile extends ConsumerWidget {
  const SpendingTile({super.key, required this.spending, required this.summary, this.showAccount = false, this.onTap});
  final Spending spending;
  final AccountSummary summary;
  final bool showAccount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = spending;
    final type = summary.account.type;
    String? lineName;
    if (summary.lines.length > 1) {
      for (final l in summary.lines) {
        if (l.id == s.creditLineId) lineName = l.name;
      }
    }
    final details = [
      if (showAccount) summary.account.name,
      ?lineName,
      if (s.source != PaymentSource.manual) 'จาก ${s.source.label}',
      if (s.creditLineId != null && s.lineBalanceApplied < 0.005) 'ไม่ได้บวกยอด (รวมอยู่แล้ว)',
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(type == AccountType.cashCard ? Icons.local_atm : Icons.shopping_bag_outlined, size: 20),
      ),
      title: Text('${fmtMoney(s.amount)} · ${s.note ?? type.spendingWord}'),
      subtitle: Text([fmtDate(s.date), if (details.isNotEmpty) details.join(' · ')].join('\n')),
      isThreeLine: details.isNotEmpty,
      trailing: PopupMenuButton<bool>(
        tooltip: 'แก้ไขหรือลบ',
        onSelected: (edit) => edit ? _edit(context, ref) : _delete(context, ref),
        itemBuilder: (_) => [
          if (summary.lines.isNotEmpty) const PopupMenuItem(value: true, child: Text('แก้ไข')),
          const PopupMenuItem(value: false, child: Text('ลบ')),
        ],
      ),
      onTap: onTap ?? () => _edit(context, ref),
      onLongPress: () => _delete(context, ref),
    );
  }

  void _edit(BuildContext context, WidgetRef ref) {
    if (summary.lines.isNotEmpty) _spendingDialog(context, ref, summary, existing: spending);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    CreditLine? line;
    for (final l in summary.lines) {
      if (l.id == spending.creditLineId) line = l;
    }
    final effect = spending.lineBalanceApplied <= 0
        ? 'ยอดคงค้างไม่เปลี่ยน เพราะตอนบันทึกไม่ได้บวกเข้าไป'
        : line != null && line.typedInAfter(spending.createdAt)
            ? 'ยอดคงค้างไม่เปลี่ยน เพราะแก้ยอดตามแอพธนาคารหลังบันทึกรายการนี้แล้ว'
            : 'ยอดนี้จะถูกหักออกจากยอดคงค้าง';
    final ok = await confirmDialog(
      context,
      title: 'ลบรายการ${summary.account.type.spendingWord}นี้?',
      message: '${fmtMoney(spending.amount)} เมื่อ ${fmtDate(spending.date)} — $effect',
      confirmLabel: 'ลบ',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(ledgerProvider).deleteSpending(spending.id);
    ref.refreshData();
  }
}

/// Key facts of a plan up front; the rest behind "รายละเอียด".
class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({required this.a, required this.p});
  final AccountSummary a;
  final InstallmentState p;

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final p = widget.p;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final plan = p.plan;
    final locked = p.isLockedOn(DateTime.now());
    final next = p.nextRow;
    final hasPenalty = plan.penaltyPercent > 0 || plan.penaltyFixed > 0;
    // Tight enough that all three buttons share one row on a 390pt screen.
    final compact = TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
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
              Text('flat ${fmtRate(plan.annualRate)} เท่ากับดอกจริงราว ${fmtRate(p.effectiveAnnualRate)}/ปี',
                  style: t.bodySmall?.copyWith(color: cs.error)),
            const SizedBox(height: 10),
            if (p.isClosed)
              Pill('ปิดยอดแล้ว', color: cs.positive, icon: Icons.check_circle)
            else ...[
              Text(
                '${plan.includedInStatement ? 'บัตรแจ้งแล้ว' : 'จ่ายแล้ว'} '
                '${p.paidInstallments}/${p.paidInstallments + p.remainingInstallments} งวด · '
                'เหลืออีก ${fmtMonths(p.remainingInstallments)}',
                style: t.bodySmall,
              ),
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
                  if (!p.isClosed && next?.dueDate != null && !plan.includedInStatement)
                    InfoRow('งวดถัดไป ${fmtDate(next!.dueDate!)}', fmtMoney(next.payment)),
                  if (!p.isClosed && next?.dueDate != null && plan.includedInStatement) ...[
                    InfoRow('งวด ${next!.number} ลงบัตร ${fmtDate(next.dueDate!)}', fmtMoney(next.payment)),
                    InfoRow(
                      'ยังไม่ลงบัตร ${p.remainingInstallments} งวด',
                      fmtMoney(p.projection.fold(0.0, (s, r) => s + r.payment)),
                    ),
                  ],
                  if (!p.isClosed && locked && p.earliestClosureDate != null)
                    InfoRow('ปิดก่อนกำหนดได้ตั้งแต่', fmtDate(p.earliestClosureDate!), valueColor: cs.warning),
                  if (!p.isClosed && plan.includedInStatement)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                                'แอพบวกค่างวดเข้า${a.account.type.revolvingLabel}ให้ทุกวันตัดรอบ จ่ายพร้อมบิลบัตร ไม่ต้องจ่ายแยก',
                                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  if (_expanded) ...[
                    if (!p.isClosed) ...[
                      InfoRow('ค่าผ่อน/เดือน', fmtMoney(p.currentPayment)),
                      if (p.projectedPayoffDate != null) InfoRow('ปิดยอดตามแผน', fmtDate(p.projectedPayoffDate!)),
                    ],
                    InfoRow('ดอกที่จ่ายไปแล้ว', fmtMoney(p.interestPaid)),
                    if (!p.isClosed)
                      InfoRow(
                        'ดอกที่ต้องจ่ายอีก',
                        fmtMoney(p.projectedRemainingInterest),
                        valueColor: p.projectedRemainingInterest > 0.005 ? cs.error : null,
                      ),
                    if (p.extraPaid > 0) InfoRow('โปะเพิ่มไปแล้ว', fmtMoney(p.extraPaid), valueColor: cs.positive),
                    if (p.interestSavedSoFar > 0.5)
                      InfoRow('ประหยัดดอกจากการโปะ', fmtMoney(p.interestSavedSoFar), valueColor: cs.positive),
                    if (!p.isClosed && !locked && p.earliestClosureDate != null)
                      InfoRow('ปิดก่อนกำหนด', 'ทำได้แล้ว (พ้น lock-in ${fmtDate(p.earliestClosureDate!)})',
                          valueColor: cs.positive),
                    if (!p.isClosed && hasPenalty)
                      InfoRow('ยอดปิดวันนี้ (รวมค่าปรับ ${fmtMoney(p.earlyClosurePenalty)})', fmtMoney(p.payoffAmount)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.table_rows_outlined),
                        label: const Text('ดูตารางผ่อนทุกงวด'),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ScheduleScreen(accountId: a.account.id, planId: plan.id))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Wrap(
              children: [
                TextButton.icon(
                  style: compact,
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(_expanded ? 'ซ่อน' : 'รายละเอียด'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
                if (!p.isClosed)
                  TextButton.icon(
                    style: compact,
                    icon: const Icon(Icons.calculate_outlined),
                    label: const Text('คำนวณโปะ'),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => CalculatorScreen(initialPlanId: plan.id))),
                  ),
                if (!p.isClosed && !plan.includedInStatement)
                  TextButton.icon(
                    style: compact,
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

/// One row of payment history: tap or the menu edits it, long-press deletes.
class PaymentTile extends ConsumerWidget {
  const PaymentTile({super.key, required this.payment, required this.summary, this.showAccount = false, this.onTap});
  final Payment payment;
  final AccountSummary summary;
  final bool showAccount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    String? target;
    for (final s in summary.plans) {
      if (s.plan.id == p.planId) target = s.plan.name;
    }
    if (summary.lines.length > 1) {
      for (final l in summary.lines) {
        if (l.id == p.creditLineId && p.planId == null) target = l.name;
      }
    }
    final details = [
      if (showAccount) summary.account.name,
      ?target,
      if (p.prepaymentMode != null && p.type == PaymentType.extra) p.prepaymentMode!.label,
      if (p.source != PaymentSource.manual) 'จาก ${p.source.label}',
      if (p.note != null && p.note!.isNotEmpty) p.note!,
    ];
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
      subtitle: Text([fmtDate(p.date), if (details.isNotEmpty) details.join(' · ')].join('\n')),
      isThreeLine: details.isNotEmpty,
      trailing: PopupMenuButton<bool>(
        tooltip: 'แก้ไขหรือลบ',
        onSelected: (edit) => edit ? _edit(context) : _delete(context, ref),
        itemBuilder: (_) => const [
          PopupMenuItem(value: true, child: Text('แก้ไข')),
          PopupMenuItem(value: false, child: Text('ลบ')),
        ],
      ),
      onTap: onTap ?? () => _edit(context),
      onLongPress: () => _delete(context, ref),
    );
  }

  void _edit(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentFormScreen(existing: payment)));

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
