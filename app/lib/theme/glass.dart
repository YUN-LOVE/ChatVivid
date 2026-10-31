import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A lightweight frosted surface. Keep this to app bars, composers and sheets;
/// do not wrap every list item in a blur.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.padding = EdgeInsets.zero,
    this.color,
    this.border = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? AppColors.glass,
              borderRadius: borderRadius,
              border: border
                  ? Border.all(color: Colors.white.withValues(alpha: 0.10))
                  : null,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.055),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
