import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../data/app_settings.dart';

/// Static color aliases used by the stage-first UI. They are intentionally
/// mutable so the whole app can switch palettes without migrating every
/// widget to a ThemeExtension.
abstract final class AppColors {
  static Color backgroundTop = const Color(0xFF070D19);
  static Color backgroundMid = const Color(0xFF101C35);
  static Color backgroundBottom = const Color(0xFF2A3F6B);
  static Color surface = const Color(0xFF0E1526);
  static Color surfaceHigh = const Color(0xFF19243A);
  static Color primary = const Color(0xFFB8C4FF);
  static Color primaryDeep = const Color(0xFF3254B5);
  static Color primaryContainer = const Color(0xFF1B2C7A);
  static Color onPrimaryContainer = const Color(0xFFDDE1FF);
  static Color coral = const Color(0xFFFFB4A8);
  static Color gold = const Color(0xFFF5C26B);
  static Color text = const Color(0xFFE6E8F0);
  static Color muted = const Color(0xFF98A2B8);
  static Color glass = const Color(0xB31A2338);
  static Color success = const Color(0xFF8FD6A6);

  static void resetClassic() {
    backgroundTop = const Color(0xFF070D19);
    backgroundMid = const Color(0xFF101C35);
    backgroundBottom = const Color(0xFF2A3F6B);
    surface = const Color(0xFF0E1526);
    surfaceHigh = const Color(0xFF19243A);
    primary = const Color(0xFFB8C4FF);
    primaryDeep = const Color(0xFF3254B5);
    primaryContainer = const Color(0xFF1B2C7A);
    onPrimaryContainer = const Color(0xFFDDE1FF);
    coral = const Color(0xFFFFB4A8);
    gold = const Color(0xFFF5C26B);
    text = const Color(0xFFE6E8F0);
    muted = const Color(0xFF98A2B8);
    glass = const Color(0xB31A2338);
    success = const Color(0xFF8FD6A6);
  }

  static void applyScheme(ColorScheme scheme) {
    backgroundTop = Color.lerp(scheme.surface, Colors.black, 0.38)!;
    backgroundMid = Color.lerp(scheme.surface, scheme.primary, 0.16)!;
    backgroundBottom = Color.lerp(scheme.surface, scheme.primary, 0.42)!;
    surface = scheme.surface;
    surfaceHigh = scheme.surfaceContainerHigh;
    primary = scheme.primary;
    primaryDeep = scheme.primaryContainer;
    primaryContainer = scheme.primaryContainer;
    onPrimaryContainer = scheme.onPrimaryContainer;
    coral = scheme.tertiary;
    gold = scheme.secondary;
    text = scheme.onSurface;
    muted = scheme.onSurfaceVariant;
    glass = scheme.surface.withValues(alpha: 0.72);
    success = const Color(0xFF8FD6A6);
  }
}

abstract final class AppTheme {
  static ColorScheme classicScheme() {
    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF3254B5),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFB8C4FF),
      onPrimary: const Color(0xFF00208A),
      primaryContainer: const Color(0xFF1B2C7A),
      onPrimaryContainer: const Color(0xFFDDE1FF),
      secondary: const Color(0xFFB7C7E8),
      onSecondary: const Color(0xFF1C2B4A),
      secondaryContainer: const Color(0xFF263A5E),
      onSecondaryContainer: const Color(0xFFD9E2FF),
      tertiary: const Color(0xFFFFB4A8),
      onTertiary: const Color(0xFF561F18),
      tertiaryContainer: const Color(0xFF70352C),
      onTertiaryContainer: const Color(0xFFFFDAD4),
      surface: const Color(0xFF0E1526),
      onSurface: const Color(0xFFE6E8F0),
      surfaceContainerHighest: const Color(0xFF19243A),
      outline: const Color(0xFF8E91A3),
      outlineVariant: const Color(0xFF3A4358),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
    );
  }

  static ThemeData dark({ColorScheme? scheme}) {
    final resolved = scheme ?? classicScheme();
    AppColors.applyScheme(resolved);
    final textTheme = ThemeData.dark().textTheme.apply(
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: resolved,
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
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
      iconTheme: IconThemeData(color: AppColors.muted),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06)),
    );
  }
}

/// Owns the selected palette. The actual Widgets read [AppColors], so the
/// MaterialApp must rebuild when this notifier changes.
class AppThemeController extends ChangeNotifier {
  AppColorMode _mode = AppColorMode.classic;
  ColorScheme? _stageScheme;
  ColorScheme? _systemScheme;
  bool _loadingStage = false;
  bool _loadingSystem = false;

  AppColorMode get mode => _mode;
  ColorScheme? get stageScheme => _stageScheme;
  ColorScheme? get systemScheme => _systemScheme;
  bool get loadingStage => _loadingStage;

  Future<void> setMode(AppColorMode mode) async {
    if (_mode == mode && (mode != AppColorMode.stage || _stageScheme != null)) {
      return;
    }
    _mode = mode;
    notifyListeners();
    if (mode == AppColorMode.stage && _stageScheme == null) {
      await _loadStagePalette();
    }
    if (mode == AppColorMode.system && _systemScheme == null) {
      await _loadSystemPalette();
    }
  }

  Future<void> _loadSystemPalette() async {
    if (_loadingSystem) return;
    _loadingSystem = true;
    notifyListeners();
    try {
      final core = await DynamicColorPlugin.getCorePalette();
      Color? seed;
      if (core != null) {
        seed = Color(core.primary.get(40));
      } else {
        seed = await DynamicColorPlugin.getAccentColor();
      }
      if (seed != null) {
        _systemScheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        );
      }
    } catch (_) {
      // Android pre-12 / unsupported desktop: classic fallback.
    } finally {
      _loadingSystem = false;
      notifyListeners();
    }
  }

  Future<void> _loadStagePalette() async {
    if (_loadingStage) return;
    _loadingStage = true;
    notifyListeners();
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        const AssetImage('assets/mascot/dafeiyu-front.png'),
        maximumColorCount: 12,
      );
      final seed = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.darkVibrantColor?.color ??
          const Color(0xFF3254B5);
      _stageScheme = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      );
    } catch (_) {
      _stageScheme = AppTheme.classicScheme();
    } finally {
      _loadingStage = false;
      notifyListeners();
    }
  }
}

final appThemeController = AppThemeController();
