import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../domain/finance/portfolio.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/installment_plan.dart';
import '../theme.dart';

/// Renders loading / error states for an [AsyncValue] uniformly.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('เกิดข้อผิดพลาด: $e', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
          ),
          // Long trailing text wraps instead of pushing the row off screen.
          if (trailing != null) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: trailing),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.caption, this.color});

  final String label;
  final String value;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: color)),
        if (caption != null)
          Text(caption!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor, this.bold = false});
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: t.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: bold ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Annual rate in plain words, e.g. "ดอก 16%/ปี", "ดอก flat 15%/ปี", "ไม่มีดอก".
class RateBadge extends StatelessWidget {
  const RateBadge({super.key, required this.rate, this.method, this.highlight = false, this.prefix = 'ดอก'});
  final double rate;
  final InterestMethod? method;
  final bool highlight;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = highlight ? cs.errorContainer : cs.secondaryContainer;
    final fg = highlight ? cs.onErrorContainer : cs.onSecondaryContainer;
    final flat = method == InterestMethod.flat ? ' flat' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        rate < 0.005 ? 'ไม่มีดอก' : '$prefix$flat ${fmtRate(rate)}/ปี',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// An account's highest rate; says "สูงสุด" when its balances carry different rates.
class AccountRateBadge extends StatelessWidget {
  const AccountRateBadge({super.key, required this.a, this.highlight = false});
  final AccountSummary a;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final rates = {for (final d in a.debtItems) d.effectiveRate.toStringAsFixed(2)};
    return RateBadge(rate: a.topRate, highlight: highlight, prefix: rates.length > 1 ? 'ดอกสูงสุด' : 'ดอก');
  }
}

/// A promotional plan's rates by installment, e.g. "งวด 1–3 21.99% · งวด 4–6 24%".
String rateScheduleText(InstallmentPlan p) {
  final parts = <String>[];
  var from = 1;
  final steps = p.rateSteps;
  for (var i = 0; i <= steps.length; i++) {
    final to = i < steps.length ? steps[i].fromInstallment - 1 : p.termMonths;
    final rate = i == 0 ? p.annualRate : steps[i - 1].annualRate;
    if (to >= from) parts.add('งวด ${from == to ? '$from' : '$from–$to'} ${fmtRate(rate)}');
    from = to + 1;
  }
  return parts.join(' · ');
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
          Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}

class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.used, required this.limit});
  final double used;
  final double limit;

  @override
  Widget build(BuildContext context) {
    if (limit <= 0) return const SizedBox.shrink();
    final ratio = (used / limit).clamp(0.0, 1.0);
    final cs = Theme.of(context).colorScheme;
    final color = ratio > 0.8 ? cs.error : (ratio > 0.5 ? cs.warning : cs.primary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 6,
        color: color,
        backgroundColor: cs.surfaceContainerHighest,
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.bodyMedium, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'ยืนยัน',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
