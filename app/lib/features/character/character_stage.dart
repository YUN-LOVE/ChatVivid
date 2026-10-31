import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The top character stage. The first build uses the transparent mascot art;
/// the Live2D runtime will occupy the same slot later.
class CharacterStage extends StatelessWidget {
  const CharacterStage({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _StageBackdrop(),
          Align(
            alignment: const Alignment(0, 0.10),
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4D6BFE).withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: height * 0.01),
                  child: Image.asset(
                    'assets/mascot/full.png',
                    height: height * 0.94,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 20,
            bottom: 76,
            child: _StageBadge(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 82,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.surface.withValues(alpha: 0),
                      AppColors.surface.withValues(alpha: 0.86),
                      AppColors.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageBackdrop extends StatelessWidget {
  const _StageBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundTop,
            AppColors.backgroundMid,
            AppColors.backgroundBottom,
          ],
          stops: [0, 0.58, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -50,
            child: _Glow(color: Color(0x334D6BFE), size: 230),
          ),
          Positioned(
            left: -80,
            top: 90,
            child: _Glow(color: Color(0x227B9CFF), size: 200),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, Colors.transparent],
        ),
      ),
    );
  }
}

class _StageBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          const Text(
            '鲸鱼娘 · 待机',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
