import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A lightweight frosted-look surface.
///
/// Deliberately **does not use `BackdropFilter`**: on Android the chat screen
/// keeps a live2d platform view (a GL texture) behind the composer and the
/// output card, and re-blurring the backdrop every frame made the whole UI
/// janky (main thread + RenderThread pegged). The frosted look is reproduced
/// with layered translucent gradients, a soft border highlight and a static
/// grain texture painted once — visually similar, but essentially free.
///
/// [intensity] (0.2–2.0, 设置 → 外观 → 毛玻璃强度) scales the tint opacity and
/// grain so the user can still tune the material.
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

  /// Kept for API compatibility with the old blur-based panel; it now scales
  /// the soft inner shadow only.
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool border;
  final GlassTint tint;

  /// Global frost multiplier, set by the app from `AppSettings.glassStrength`.
  static double intensity = 1.0;

  static double get _clamped => intensity.clamp(0.2, 2.0);

  @override
  Widget build(BuildContext context) {
    final i = _clamped;
    final borderRadius = BorderRadius.circular(radius);
    final light = tint == GlassTint.light;
    final base = color ??
        (light ? const Color(0xFFFFFFFF) : AppColors.glass);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.18 : 0.22),
            blurRadius: (blur * i).clamp(8.0, 40.0),
            offset: Offset(0, light ? 6 : 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: light
                    ? base.withValues(alpha: (0.22 + 0.16 * i).clamp(0.0, 0.62))
                    : base.withValues(alpha: 0.86),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _FrostGrainPainter(
                    light: light,
                    intensity: i,
                  ),
                ),
              ),
            ),
            Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: border
                    ? Border.all(
                        color: light
                            ? Colors.white.withValues(alpha: 0.30 + 0.12 * i)
                            : Colors.white.withValues(alpha: 0.10),
                      )
                    : null,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: light
                      ? [
                          Colors.white.withValues(alpha: 0.22 + 0.10 * i),
                          Colors.white.withValues(alpha: 0.05),
                          Colors.white.withValues(alpha: 0.03),
                          Colors.white.withValues(alpha: 0.10),
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

/// Deterministic frost grain, painted once per panel build (no backdrop
/// read-back, no blur layer).
class _FrostGrainPainter extends CustomPainter {
  _FrostGrainPainter({required this.light, required this.intensity});

  final bool light;
  final double intensity;

  static final List<Offset> _points = _buildPoints();
  static final List<Offset> _streaks = _buildStreaks();

  static List<Offset> _buildPoints() {
    final random = math.Random(20261114);
    return List<Offset>.generate(
      260,
      (_) => Offset(random.nextDouble(), random.nextDouble()),
      growable: false,
    );
  }

  static List<Offset> _buildStreaks() {
    final random = math.Random(7);
    return List<Offset>.generate(
      18,
      (_) => Offset(random.nextDouble(), random.nextDouble() * 0.98),
      growable: false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grain = light ? 0.05 : 0.03;
    final dotPaint = Paint()
      ..color = (light ? Colors.white : Colors.white)
          .withValues(alpha: grain * intensity.clamp(0.0, 2.0))
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    for (final point in _points) {
      canvas.drawPoints(
        PointMode.points,
        [Offset(point.dx * size.width, point.dy * size.height)],
        dotPaint,
      );
    }

    final streakPaint = Paint()
      ..color = Colors.white.withValues(
        alpha: (light ? 0.04 : 0.02) * intensity.clamp(0.0, 2.0),
      )
      ..strokeWidth = 0.6;
    for (final streak in _streaks) {
      final x = streak.dx * size.width;
      final y = streak.dy * size.height;
      final length = 5.0 + (streak.dx * 18.0);
      canvas.drawLine(Offset(x, y), Offset(x + length, y), streakPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FrostGrainPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.light != light;
}
