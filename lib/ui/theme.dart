import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Cool light blue. The `content` variant keeps the palettes close to it
  /// and picks a neighbouring (still cool) hue for tertiary.
  static const _seed = Color(0xFF0288D1);

  static ThemeData light() => _build(ColorScheme.fromSeed(
        seedColor: _seed,
        dynamicSchemeVariant: DynamicSchemeVariant.content,
      ).copyWith(
        primary: _seed,
        onPrimary: Colors.white,
        // `content` fills containers with the seed itself; cards holding
        // body text and red/green amounts need light ones.
        primaryContainer: const Color(0xFFD6EEFC),
        onPrimaryContainer: const Color(0xFF003A5C),
        tertiaryContainer: const Color(0xFFE0E4FF),
        onTertiaryContainer: const Color(0xFF26326E),
        // Navy and slate-blue text instead of neutral black and grey.
        onSurface: const Color(0xFF0F2A3D),
        onSurfaceVariant: const Color(0xFF4F6B80),
      ));

  static ThemeData dark() => _build(ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.content,
      ).copyWith(
        primaryContainer: const Color(0xFF0B3A57),
        onPrimaryContainer: const Color(0xFFD6EEFC),
        tertiaryContainer: const Color(0xFF2C3570),
        onTertiaryContainer: const Color(0xFFE0E4FF),
        onSurface: const Color(0xFFE3F0F9),
        onSurfaceVariant: const Color(0xFFA7BED0),
      ));

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
