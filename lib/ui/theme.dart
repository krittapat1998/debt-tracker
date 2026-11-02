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

  /// Light text on the app icon's royal blue, a shade darker.
  static ThemeData blue() => _build(ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A6FE8),
        brightness: Brightness.dark,
      ).copyWith(
        surface: const Color(0xFF1150C8),
        surfaceDim: const Color(0xFF0C44B3),
        surfaceBright: const Color(0xFF2A6CE0),
        surfaceContainerLowest: const Color(0xFF0B3FA8),
        surfaceContainerLow: const Color(0xFF1E61D9),
        surfaceContainer: const Color(0xFF0C44B3),
        surfaceContainerHigh: const Color(0xFF2A6CE0),
        surfaceContainerHighest: const Color(0xFF3A79E6),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFCFE0FF),
        primary: const Color(0xFFA8DDFF),
        onPrimary: const Color(0xFF003063),
        primaryContainer: const Color(0xFF0A3A9E),
        onPrimaryContainer: Colors.white,
        secondaryContainer: const Color(0xFF3B7BEA),
        onSecondaryContainer: Colors.white,
        tertiaryContainer: const Color(0xFF3D3FB0),
        onTertiaryContainer: Colors.white,
        outline: const Color(0xFF8FB2F0),
        outlineVariant: const Color(0xFF4F82E3),
        inverseSurface: const Color(0xFFEAF1FF),
        onInverseSurface: const Color(0xFF0F2A3D),
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
