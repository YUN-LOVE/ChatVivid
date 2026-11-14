import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A lightweight frosted surface. Keep this to app bars, composers and sheets;
/// do not wrap every list item in a blur.
///
/// Set [premium] for the HyperOS-like "advanced material" used by the composer
/// and the output card: two stacked backdrop blur layers plus a faint grain
/// texture so the glass reads as a real material instead of a flat tint.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.padding = EdgeInsets.zero,
    this.color,
    this.border = true,
    this.premium = false,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool border;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final outerBlur = premium ? blur * 1.35 + 8 : blur;
    final innerBlur = premium ? blur * 0.45 : 0.0;
    final baseColor = color ?? AppColors.glass;

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: premium ? 0.32 : 0.24),
            blurRadius: premium ? 32 : 24,
            offset: Offset(0, premium ? 14 : 10),
          ),
          if (premium)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            // Layer 1: wide milk-glass blur.
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: outerBlur,
                  sigmaY: outerBlur,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
            // Layer 2 (premium): short blur + tint that gives the material its
            // soft, slightly "wet" depth without washing out the content.
            if (premium)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: innerBlur,
                    sigmaY: innerBlur,
                  ),
                  child: ColoredBox(
                    color: baseColor.withValues(alpha: 0.34),
                  ),
                ),
              ),
            // Layer 3 (premium): grain / micro-texture.
            if (premium)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: const _GlassGrainPainter()),
                ),
              ),
            // Layer 4: tint + highlights + content.
            Container(
              padding: padding,
              decoration: BoxDecoration(
                color: premium
                    ? baseColor.withValues(alpha: 0.44)
                    : baseColor,
                borderRadius: borderRadius,
                border: border
                    ? Border.all(
                        color: Colors.white.withValues(
                          alpha: premium ? 0.14 : 0.10,
                        ),
                      )
                    : null,
                gradient: premium
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.13),
                          Colors.white.withValues(alpha: 0.02),
                          Colors.white.withValues(alpha: 0.015),
                          Colors.white.withValues(alpha: 0.06),
                        ],
                        stops: const [0.0, 0.32, 0.68, 1.0],
                      )
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.055),
                          Colors.transparent,
                        ],
                      ),
              ),
              child: premium
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          math.max(radius - 1, 0),
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.045),
                        ),
                      ),
                      child: child,
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Deterministic micro-noise so frosted panels look like etched glass.
class _GlassGrainPainter extends CustomPainter {
  const _GlassGrainPainter();

  static final List<Offset> _points = _buildPoints();
  static final List<Offset> _streaks = _buildStreaks();

  static List<Offset> _buildPoints() {
    final random = math.Random(20261114);
    return List<Offset>.generate(
      420,
      (_) => Offset(random.nextDouble(), random.nextDouble()),
      growable: false,
    );
  }

  static List<Offset> _buildStreaks() {
    final random = math.Random(7);
    return List<Offset>.generate(
      26,
      (_) => Offset(random.nextDouble(), random.nextDouble() * 0.98),
      growable: false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    for (final point in _points) {
      canvas.drawPoints(PointMode.points, [
        Offset(point.dx * size.width, point.dy * size.height),
      ], dotPaint);
    }

    final streakPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.028)
      ..strokeWidth = 0.6;
    for (final streak in _streaks) {
      final x = streak.dx * size.width;
      final y = streak.dy * size.height;
      final length = 6.0 + (streak.dx * 22.0);
      canvas.drawLine(Offset(x, y), Offset(x + length, y), streakPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
