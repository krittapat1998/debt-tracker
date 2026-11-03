import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date_utils.dart';
import '../../core/formatters.dart';

/// Total debt month by month: the plan as a filled line, the baseline as a
/// thin grey one, and an optional [stretch] plan (paying the most one can)
/// as a third line. Long baselines are cut at [maxMonths].
class DebtChart extends StatelessWidget {
  const DebtChart({
    super.key,
    required this.plan,
    required this.baseline,
    required this.start,
    this.stretch,
    this.maxMonths = 360,
  });
  final List<double> plan;
  final List<double> baseline;
  final List<double>? stretch;
  final DateTime start;
  final int maxMonths;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 200,
      child: CustomPaint(
        size: Size.infinite,
        painter: _DebtChartPainter(
          plan: plan,
          baseline: baseline,
          stretch: stretch,
          start: start,
          maxMonths: maxMonths,
          planColor: cs.primary,
          stretchColor: cs.tertiary,
          baseColor: cs.outline,
          gridColor: cs.outlineVariant,
          labelStyle: t.labelSmall!.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DebtChartPainter extends CustomPainter {
  _DebtChartPainter({
    required this.plan,
    required this.baseline,
    required this.stretch,
    required this.start,
    required this.maxMonths,
    required this.planColor,
    required this.stretchColor,
    required this.baseColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<double> plan;
  final List<double> baseline;
  final List<double>? stretch;
  final DateTime start;
  final int maxMonths;
  final Color planColor;
  final Color stretchColor;
  final Color baseColor;
  final Color gridColor;
  final TextStyle labelStyle;

  static const _left = 72.0;
  static const _bottom = 20.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (plan.isEmpty) return;
    final months = math.min(maxMonths, math.max(plan.length, baseline.length) - 1).clamp(1, maxMonths);
    final top = [...plan, ...baseline.take(months + 1)].fold(0.0, math.max);
    if (top <= 0) return;
    final chart = Rect.fromLTRB(_left, 6, size.width - 8, size.height - _bottom);
    Offset at(int m, double v) =>
        Offset(chart.left + chart.width * m / months, chart.bottom - chart.height * (v / top).clamp(0, 1));

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = chart.bottom - chart.height * f;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _label(canvas, fmtMoneyCompact(top * f), Offset(0, y - 7), width: _left - 6, alignRight: true);
    }

    Path line(List<double> values) {
      final p = Path()..moveTo(at(0, values.first).dx, at(0, values.first).dy);
      for (var m = 1; m < values.length && m <= months; m++) {
        final o = at(m, values[m]);
        p.lineTo(o.dx, o.dy);
      }
      return p;
    }

    canvas.drawPath(
      line(baseline),
      Paint()
        ..color = baseColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    final planLine = line(plan);
    final last = math.min(plan.length - 1, months);
    final fill = Path.from(planLine)
      ..lineTo(at(last, 0).dx, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = planColor.withValues(alpha: 0.15));
    canvas.drawPath(
      planLine,
      Paint()
        ..color = planColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    final most = stretch;
    if (most != null && most.isNotEmpty) {
      canvas.drawPath(
        line(most),
        Paint()
          ..color = stretchColor
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }

    _label(canvas, 'ตอนนี้', Offset(chart.left, chart.bottom + 4), width: 60);
    _label(canvas, fmtMonthYear(addMonths(start, months)), Offset(chart.right - 110, chart.bottom + 4),
        width: 110, alignRight: true);
  }

  void _label(Canvas canvas, String text, Offset at, {required double width, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      maxLines: 1,
    )..layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_DebtChartPainter old) =>
      old.plan != plan || old.baseline != baseline || old.stretch != stretch || old.planColor != planColor;
}
