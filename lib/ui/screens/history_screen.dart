import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';

/// All payments across accounts, grouped by month.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _accountId;

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติการจ่าย')),
      body: AsyncBody(
        value: portfolio,
        builder: (s) {
          final entries = <(Payment, AccountSummary)>[
            for (final a in s.accounts)
              if (_accountId == null || a.account.id == _accountId)
                for (final p in a.payments) (p, a),
          ]..sort((x, y) {
              final c = y.$1.date.compareTo(x.$1.date);
              return c != 0 ? c : y.$1.createdAt.compareTo(x.$1.createdAt);
            });

          final children = <Widget>[
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('ทั้งหมด'),
                      selected: _accountId == null,
                      onSelected: (_) => setState(() => _accountId = null),
                    ),
                  ),
                  for (final a in s.accounts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(a.account.name),
                        selected: _accountId == a.account.id,
                        onSelected: (_) => setState(() => _accountId = a.account.id),
                      ),
                    ),
                ],
              ),
            ),
          ];

          if (entries.isEmpty) {
            children.add(const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'ยังไม่มีประวัติการจ่าย',
                message: 'กด "บันทึกการจ่าย" ที่หน้าภาพรวมทุกครั้งที่โอนเงินจ่ายบัตร/สินเชื่อ',
              ),
            ));
          }

          DateTime? month;
          for (final (p, a) in entries) {
            if (month == null || !isSameMonth(month, p.date)) {
              month = startOfMonth(p.date);
              final m = month;
              final inMonth = entries.where((e) => isSameMonth(e.$1.date, m));
              final total = inMonth.fold(0.0, (t, e) => t + e.$1.amount);
              final extra = inMonth
                  .where((e) => e.$1.type == PaymentType.extra)
                  .fold(0.0, (t, e) => t + e.$1.amount);
              children.add(SectionHeader(
                fmtMonthYear(m),
                trailing: Text(
                  '${fmtMoney(total)}${extra > 0 ? ' (โปะ ${fmtMoney(extra)})' : ''}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ));
            }
            children.add(InkWell(
              onTap: () => openAccount(context, a.account.id),
              child: PaymentTile(payment: p, summary: a, showAccount: true),
            ));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refreshData(),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
          );
        },
      ),
    );
  }
}
