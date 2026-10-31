import 'package:flutter/material.dart';

abstract final class AppColors {
  static const backgroundTop = Color(0xFF070D19);
  static const backgroundMid = Color(0xFF101C35);
  static const backgroundBottom = Color(0xFF2A3F6B);
  static const surface = Color(0xFF0E1526);
  static const surfaceHigh = Color(0xFF19243A);
  static const primary = Color(0xFFB8C4FF);
  static const primaryDeep = Color(0xFF3254B5);
  static const primaryContainer = Color(0xFF1B2C7A);
  static const onPrimaryContainer = Color(0xFFDDE1FF);
  static const coral = Color(0xFFFFB4A8);
  static const gold = Color(0xFFF5C26B);
  static const text = Color(0xFFE6E8F0);
  static const muted = Color(0xFF98A2B8);
  static const glass = Color(0xB31A2338);
  static const success = Color(0xFF8FD6A6);
}

abstract final class AppTheme {
  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primaryDeep,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: AppColors.primary,
      onPrimary: const Color(0xFF00208A),
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: const Color(0xFFB7C7E8),
      onSecondary: const Color(0xFF1C2B4A),
      secondaryContainer: const Color(0xFF263A5E),
      onSecondaryContainer: const Color(0xFFD9E2FF),
      tertiary: AppColors.coral,
      onTertiary: const Color(0xFF561F18),
      tertiaryContainer: const Color(0xFF70352C),
      onTertiaryContainer: const Color(0xFFFFDAD4),
      surface: AppColors.surface,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: const Color(0xFF8E91A3),
      outlineVariant: const Color(0xFF3A4358),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
    );

    final textTheme = ThemeData.dark().textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        hintStyle: TextStyle(color: AppColors.muted.withValues(alpha: 0.75)),
      ),
      iconTheme: const IconThemeData(color: AppColors.muted),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06)),
    );
  }
}
