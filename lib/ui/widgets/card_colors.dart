import 'package:flutter/material.dart';

/// Colors a card can be painted in (cards like the bank's own).
const cardColors = <(String, Color)>[
  ('น้ำเงิน', Color(0xFF1565C0)),
  ('ฟ้า', Color(0xFF0288D1)),
  ('เขียวอมฟ้า', Color(0xFF00838F)),
  ('เขียว', Color(0xFF2E7D32)),
  ('ม่วง', Color(0xFF6A1B9A)),
  ('ชมพู', Color(0xFFAD1457)),
  ('แดง', Color(0xFFC62828)),
  ('ส้ม', Color(0xFFE65100)),
  ('เหลือง', Color(0xFFF9A825)),
  ('น้ำตาล', Color(0xFF5D4037)),
  ('เทา', Color(0xFF455A64)),
  ('ดำ', Color(0xFF212121)),
];

/// Repaints [child] for a card filled with [color]: text, badges and bars
/// get colors that stay readable on it. A null [color] changes nothing.
class CardColorTheme extends StatelessWidget {
  const CardColorTheme({super.key, required this.color, required this.child});
  final int? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = color;
    if (c == null) return child;
    return Theme(data: themeForCard(Theme.of(context), Color(c)), child: child);
  }
}

ThemeData themeForCard(ThemeData base, Color color) {
  final brightness = ThemeData.estimateBrightnessForColor(color);
  final on = brightness == Brightness.dark ? Colors.white : const Color(0xFF1B1B1B);
  final scheme = ColorScheme.fromSeed(seedColor: color, brightness: brightness).copyWith(
    surface: color,
    surfaceContainerLow: color,
    onSurface: on,
    onSurfaceVariant: on.withValues(alpha: 0.8),
    surfaceContainerHighest: on.withValues(alpha: 0.22),
    secondaryContainer: on.withValues(alpha: 0.18),
    onSecondaryContainer: on,
  );
  return base.copyWith(
    colorScheme: scheme,
    cardTheme: base.cardTheme.copyWith(color: color),
    textTheme: base.textTheme.apply(bodyColor: on, displayColor: on),
    iconTheme: base.iconTheme.copyWith(color: on),
  );
}

/// Row of color dots for picking a card color; the first dot is "no color".
class CardColorPicker extends StatelessWidget {
  const CardColorPicker({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dot({required Color fill, required bool selected, required String tip, required int? pick, Widget? icon}) {
      final check = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : Colors.black87;
      return Tooltip(
        message: tip,
        child: InkResponse(
          onTap: () => onChanged(pick),
          radius: 22,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 3 : 1),
            ),
            child: selected ? Icon(Icons.check, size: 18, color: check) : icon,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        dot(
          fill: cs.surfaceContainerLow,
          selected: value == null,
          tip: 'ตามธีม',
          pick: null,
          icon: Icon(Icons.format_color_reset, size: 18, color: cs.onSurfaceVariant),
        ),
        for (final (name, c) in cardColors)
          dot(fill: c, selected: value == c.toARGB32(), tip: name, pick: c.toARGB32()),
      ],
    );
  }
}
