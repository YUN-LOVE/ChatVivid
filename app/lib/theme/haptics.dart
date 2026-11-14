import 'package:flutter/services.dart';

/// Central place for the AOSP-flavoured haptic vocabulary used across the app.
///
/// All calls are fire-and-forget: Flutter routes them to the platform's
/// `performHapticFeedback` so they respect the user's system haptics setting.
class AppHaptics {
  AppHaptics._();

  /// Moving between options, small toggles, back/close.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Primary actions: send message, open a screen, speak.
  static Future<void> light() => HapticFeedback.lightImpact();

  /// Committing a state change: live mode, dev mode enabled, delete.
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Destructive confirmation.
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Success feedback for longer operations.
  static Future<void> success() => HapticFeedback.vibrate();
}
