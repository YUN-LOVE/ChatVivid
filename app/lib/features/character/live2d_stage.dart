// ignore_for_file: prefer_const_constructors_in_immutables
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live2d_flutter/live2d_flutter.dart';

import '../../theme/app_theme.dart';

bool get live2dSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

/// Renders the bundled DS whale-girl Cubism model with app-side blink,
/// breathing and mouth motion. The Cubism core loads the .model3.json and all
/// referenced moc3/texture/motion/physics files.
class Live2DStage extends StatefulWidget {
  Live2DStage({
    super.key,
    this.modelDir = 'assets/live2d/whale-girl/',
    this.modelFile = 'c_0120.model3.json',
    this.speaking = false,
    this.fallback,
  });

  final String modelDir;
  final String modelFile;
  final bool speaking;
  final Widget? fallback;

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

class _Live2DStageState extends State<Live2DStage> {
  final Live2DViewController _controller = Live2DViewController();
  Timer? _blinkTimer;
  Timer? _mouthTimer;
  bool _loaded = false;
  bool _failed = false;
  bool _blinking = false;
  double _mouth = 0;

  @override
  void initState() {
    super.initState();
    _controller.whenAttached.then((_) async {
      try {
        var ok = false;
        // The platform view can attach before its GL surface has a size;
        // loadModel is deliberately rejected by the native side in that case.
        for (var attempt = 0; attempt < 6 && !ok; attempt++) {
          ok = await _controller.loadModel(
            modelDir: widget.modelDir,
            modelFileName: widget.modelFile,
          );
          if (!ok) {
            await Future<void>.delayed(Duration(milliseconds: 220));
          }
        }
        if (!mounted) return;
        setState(() {
          _loaded = ok;
          _failed = !ok;
        });
        if (ok) {
          await _controller.startMotion(group: 'idle', priority: 1);
          _startBlink();
          _startMouth();
        }
      } catch (error) {
        debugPrint('Live2D load failed: $error');
        if (mounted) setState(() => _failed = true);
      }
    });
  }

  @override
  void didUpdateWidget(Live2DStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speaking != widget.speaking && _loaded) {
      _startMouth();
    }
  }

  void _startBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(Duration(seconds: 4), (_) async {
      if (!_loaded || _blinking) return;
      _blinking = true;
      try {
        for (var i = 0; i < 4; i++) {
          await _controller.setParameter('ParamEyeLOpen', 0);
          await _controller.setParameter('ParamEyeROpen', 0);
          await Future<void>.delayed(Duration(milliseconds: 35));
        }
        for (var i = 0; i < 4; i++) {
          await _controller.setParameter('ParamEyeLOpen', 1);
          await _controller.setParameter('ParamEyeROpen', 1);
          await Future<void>.delayed(Duration(milliseconds: 35));
        }
      } catch (_) {
        // Cubism may not expose eye parameters on imported models.
      } finally {
        _blinking = false;
      }
    });
  }

  void _startMouth() {
    _mouthTimer?.cancel();
    if (!widget.speaking) {
      _setMouth(0);
      return;
    }
    _mouthTimer = Timer.periodic(Duration(milliseconds: 90), (_) {
      if (!_loaded) return;
      _mouth = 0.15 + (math.sin(DateTime.now().millisecondsSinceEpoch / 95) + 1) * 0.36;
      _setMouth(_mouth);
    });
  }

  Future<void> _setMouth(double value) async {
    try {
      await _controller.setParameter('ParamMouthOpenY', value.clamp(0, 1));
    } catch (_) {
      // imported models may use a different mouth parameter.
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _mouthTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback ?? SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the platform view at a stable index. Do not put a conditional
        // fallback sibling in front of it: changing the child list after the
        // model loads recreates/detaches the native view.
        Live2DView(
          key: ValueKey('chatvv-live2d-view'),
          controller: _controller,
        ),
        if (!_loaded)
          Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.2,
                color: AppColors.primary.withValues(alpha: 0.65),
              ),
            ),
          ),
      ],
    );
  }
}
