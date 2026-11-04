import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment.dart';
import '../../domain/models/spending.dart';
import '../providers.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';
import '../widgets/app_icons.dart';

enum _Kind { all, payments, spendings }

/// One history row: a payment or a spending.
typedef _Entry = ({AccountSummary a, Payment? payment, Spending? spending});

extension on _Entry {
  DateTime get date => payment?.date ?? spending!.date;
  DateTime get createdAt => payment?.createdAt ?? spending!.createdAt;
}

/// Payments and spending across accounts, grouped by month.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _accountId;
  var _kind = _Kind.all;

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(portfolioProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติ')),
      body: AsyncBody(
        value: portfolio,
        builder: (s) {
          final entries = <_Entry>[
            for (final a in s.accounts)
              if (_accountId == null || a.account.id == _accountId) ...[
                if (_kind != _Kind.spendings)
                  for (final p in a.payments) (a: a, payment: p, spending: null),
                if (_kind != _Kind.payments)
                  for (final sp in a.spendings) (a: a, payment: null, spending: sp),
              ],
          ]..sort((x, y) {
              final c = y.date.compareTo(x.date);
              return c != 0 ? c : y.createdAt.compareTo(x.createdAt);
            });

          final children = <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<_Kind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Kind.all, label: Text('ทั้งหมด')),
                  ButtonSegment(value: _Kind.payments, label: Text('การจ่าย')),
                  ButtonSegment(value: _Kind.spendings, label: Text('ยอดใช้จ่าย')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.single),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('ทุกบัตร'),
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
            children.add(Padding(
              padding: const EdgeInsets.only(top: 48),
              child: switch (_kind) {
                _Kind.all => const EmptyState(
                    icon: Glyph.history,
                    title: 'ยังไม่มีประวัติ',
                    message: 'การจ่ายและยอดใช้จ่ายที่บันทึกไว้จะแสดงที่นี่',
                  ),
                _Kind.payments => const EmptyState(
                    icon: Glyph.pay,
                    title: 'ยังไม่มีประวัติการจ่าย',
                    message: 'กด "บันทึกการจ่าย" ทุกครั้งที่โอนเงินจ่ายบัตร/สินเชื่อ',
                  ),
                _Kind.spendings => const EmptyState(
                    icon: Glyph.spend,
                    title: 'ยังไม่มียอดใช้จ่าย',
                    message: 'กด "เพิ่มยอดใช้จ่าย" ในหน้าบัตรเมื่อรูดซื้อของ',
                  ),
              },
            ));
          }

          DateTime? month;
          for (final e in entries) {
            if (month == null || !isSameMonth(month, e.date)) {
              month = startOfMonth(e.date);
              children.add(SectionHeader(
                fmtMonthYear(month),
                icon: Glyph.dueDate,
                trailing: Text(
                  _monthTotals(entries.where((x) => isSameMonth(x.date, month!))),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ));
            }
            void open() => openAccount(context, e.a.account.id);
            children.add(e.payment != null
                ? PaymentTile(payment: e.payment!, summary: e.a, showAccount: true, onTap: open)
                : SpendingTile(spending: e.spending!, summary: e.a, showAccount: true, onTap: open));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.refreshData(),
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
          );
        },
      ),
    );
  }

  /// "จ่าย ฿X (โปะ ฿Y) · ใช้ ฿Z" for the parts the current filter shows.
  String _monthTotals(Iterable<_Entry> inMonth) {
    var paid = 0.0, extra = 0.0, spent = 0.0;
    for (final e in inMonth) {
      final p = e.payment;
      if (p != null) {
        paid += p.amount;
        if (p.type == PaymentType.extra) extra += p.amount;
      } else {
        spent += e.spending!.amount;
      }
    }
    return [
      if (paid > 0) 'จ่าย ${fmtMoney(paid)}${extra > 0 && _kind == _Kind.payments ? ' (โปะ ${fmtMoney(extra)})' : ''}',
      if (spent > 0) 'ใช้ ${fmtMoney(spent)}',
    ].join(' · ');
  }
}
