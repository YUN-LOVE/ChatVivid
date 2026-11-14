import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A frosted surface. Keep this to app bars, composers and sheets; do not wrap
/// every list item in a blur.
///
/// Two tints are available:
/// * [GlassTint.dark] — the original dark deep-sea glass.
/// * [GlassTint.light] — white frosted glass (composer + output card). This is a
///   single backdrop blur layer (no stacked blur / grain) to keep it cheap on
///   Android where the character platform view animates behind it.
///
/// [intensity] is a global 0.2–2.0 multiplier driven by the 设置 → 外观 →
/// 毛玻璃强度 slider. It scales the blur sigma (and lets the user disable the
/// material almost entirely).
enum GlassTint { dark, light }

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.padding = EdgeInsets.zero,
    this.color,
    this.border = true,
    this.tint = GlassTint.dark,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool border;
  final GlassTint tint;

  /// Global frost multiplier, set by the app from `AppSettings.glassStrength`.
  static double intensity = 1.0;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final effectiveBlur = (blur * intensity.clamp(0.2, 2.0)).clamp(1.0, 48.0);
    final light = tint == GlassTint.light;
    final base = color ??
        (light ? const Color(0xFFFFFFFF) : AppColors.glass);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.20 : 0.24),
            blurRadius: light ? 20 : 24,
            offset: Offset(0, light ? 8 : 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: effectiveBlur,
                  sigmaY: effectiveBlur,
                ),
                child: ColoredBox(
                  color: light
                      ? base.withValues(alpha: 0.14 + 0.10 * intensity.clamp(0, 1))
                      : base.withValues(alpha: 0.78),
                ),
              ),
            ),
            Container(
              padding: padding,
              decoration: BoxDecoration(
                color: light
                    ? Colors.white.withValues(alpha: 0.08 + 0.06 * intensity.clamp(0, 1))
                    : Colors.transparent,
                borderRadius: borderRadius,
                border: border
                    ? Border.all(
                        color: light
                            ? Colors.white.withValues(alpha: 0.34)
                            : Colors.white.withValues(alpha: 0.10),
                        width: light ? 1.0 : 1.0,
                      )
                    : null,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: light
                      ? [
                          Colors.white.withValues(alpha: 0.26),
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.04),
                          Colors.white.withValues(alpha: 0.14),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.055),
                          Colors.transparent,
                        ],
                  stops: light
                      ? const [0.0, 0.35, 0.7, 1.0]
                      : const [0.0, 1.0],
                ),
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
