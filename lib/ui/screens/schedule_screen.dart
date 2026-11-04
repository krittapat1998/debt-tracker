import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../domain/finance/installment_engine.dart';
import '../../domain/finance/loan_state.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/app_icons.dart';

/// Full amortization table: paid installments followed by the projection.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key, required this.accountId, required this.planId});
  final String accountId;
  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(portfolioProvider);
    InstallmentState? state;
    for (final p in portfolio.value?.byId(accountId)?.plans ?? const <InstallmentState>[]) {
      if (p.plan.id == planId) state = p;
    }
    return Scaffold(
      appBar: AppBar(title: Text(state == null ? 'ตารางผ่อน' : 'ตารางผ่อน: ${state.plan.name}')),
      body: AsyncBody(
        value: portfolio,
        builder: (_) {
          final s = state;
          if (s == null) return const EmptyState(icon: Glyph.notFound, title: 'ไม่พบรายการผ่อน');
          final rows = s.fullSchedule;
          final cs = Theme.of(context).colorScheme;
          return ListView.builder(
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        InfoRow('เงินต้นตั้งต้น', fmtMoney(s.plan.principal)),
                        InfoRow('ดอกเบี้ย', '${fmtPercent(s.plan.annualRate)} ${s.plan.interestMethod.label}'),
                        InfoRow('อัตราที่แท้จริง', '${fmtPercent(s.effectiveAnnualRate)}/ปี'),
                        InfoRow('ดอกเบี้ยรวมตามสัญญาเดิม', fmtMoney(s.originalTotalInterest)),
                        InfoRow('ดอกที่จ่ายแล้ว + ที่ต้องจ่ายอีก', fmtMoney(s.interestPaid + s.projectedRemainingInterest)),
                        if (s.extraPaid > 0) InfoRow('โปะเพิ่มรวม', fmtMoney(s.extraPaid), valueColor: cs.positive),
                      ],
                    ),
                  ),
                );
              }
              return _RowTile(row: rows[i - 1], cardBilled: s.plan.includedInStatement);
            },
          );
        },
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.cardBilled});
  final ScheduleRow row;

  /// Dates are the cutoffs the bank puts each installment on the card.
  final bool cardBilled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final paid = row.isPaid;
    return Container(
      color: paid ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: paid ? cs.primary : cs.surfaceContainerHighest,
          child: paid
              ? GlyphIcon(Glyph.done, size: 16, color: cs.onPrimary)
              : Text('${row.number}', style: t.labelSmall),
        ),
        title: Text(
          '${row.dueDate == null ? 'งวด ${row.number}' : '${cardBilled ? 'ลงบัตร ' : ''}${fmtDate(row.dueDate!)}'}'
          ' · ${fmtMoney(row.payment)}',
        ),
        subtitle: Text(
          'ต้น ${fmtMoney(row.principal)} · ดอก ${fmtMoney(row.interest)} · คงเหลือ ${fmtMoney(row.balance)}'
          '${row.paidOn != null ? '\nจ่ายเมื่อ ${fmtDate(row.paidOn!)}' : (row.automatic ? (cardBilled ? '\nลงบัตรแล้ว' : '\nเดินงวดอัตโนมัติ') : '')}',
        ),
        isThreeLine: paid,
      ),
    );
  }
}
