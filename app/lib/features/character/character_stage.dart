import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

import '../../theme/app_theme.dart';

/// The top character stage. A local Rive animation occupies the character slot;
/// the static mascot remains as the loading/fallback image.
class CharacterStage extends StatefulWidget {
  const CharacterStage({super.key});

  @override
  State<CharacterStage> createState() => _CharacterStageState();
}

class _CharacterStageState extends State<CharacterStage> {
  int _taps = 0;
  late final FileLoader _riveLoader = FileLoader.fromAsset(
    'assets/rive/walking.riv',
    riveFactory: Factory.flutter,
  );

  @override
  void dispose() {
    _riveLoader.dispose();
    super.dispose();
  }

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
                  child: GestureDetector(
                    onTap: () => setState(() => _taps++),
                    child: SizedBox(
                      height: height * 0.94,
                      child: RiveWidgetBuilder(
                        fileLoader: _riveLoader,
                        stateMachineSelector:
                            StateMachineSelector.byName('State Machine 1'),
                        onFailed: (error, stackTrace) {
                          debugPrint('Rive load failed: $error');
                        },
                        builder: (context, state) => switch (state) {
                          RiveLoading() => Image.asset(
                            'assets/mascot/full.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                          RiveFailed() => Image.asset(
                            'assets/mascot/full.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                          RiveLoaded() => RiveWidget(
                            controller: state.controller,
                            fit: Fit.contain,
                            alignment: Alignment.bottomCenter,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 20,
            bottom: 76,
            child: _StageBadge(taps: _taps),
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
  const _StageBadge({required this.taps});

  final int taps;

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
          Text(
            '鲸鱼娘 · ${taps == 0 ? '待机' : '已互动 $taps'}',
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
