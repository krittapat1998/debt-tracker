import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF00695C);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: _seed));

  static ThemeData dark() =>
      _build(ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark));

  static ThemeData _build(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      );
}

extension AppColors on ColorScheme {
  Color get positive => brightness == Brightness.light ? const Color(0xFF2E7D32) : const Color(0xFF81C784);
  Color get warning => brightness == Brightness.light ? const Color(0xFFB26A00) : const Color(0xFFFFB74D);
}
