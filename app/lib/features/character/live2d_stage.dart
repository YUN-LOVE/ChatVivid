// ignore_for_file: prefer_const_constructors_in_immutables
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live2d_flutter/live2d_flutter.dart';

import '../../theme/app_theme.dart';

/// Platforms where `live2d_flutter` ships a renderer.
///
/// The vendored plugin implements Android, iOS, macOS, Windows and Web. It has
/// no Linux implementation, and this app does not fake one: on Linux (and any
/// other unsupported target) [CharacterStage] renders the static mascot image
/// instead of a [Live2DStage]. Web is listed because the plugin declares it,
/// even though the app currently has no web build target.
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
    this.gazeNotifier,
  });

  final String modelDir;
  final String modelFile;
  final bool speaking;
  final Widget? fallback;

  /// Normalized (-1..1) pointer target from the chat screen's top-level touch
  /// layer. The platform view itself does not reliably receive Flutter pointer
  /// events on Android, so the screen owns the gesture and pushes it here.
  final ValueNotifier<Offset?>? gazeNotifier;

  @override
  State<Live2DStage> createState() => _Live2DStageState();
}

class _Live2DStageState extends State<Live2DStage> {
  final Live2DViewController _controller = Live2DViewController();
  Timer? _blinkTimer;
  Timer? _mouthTimer;
  Timer? _tailTimer;
  Timer? _drawTimer;
  bool _loaded = false;
  bool _failed = false;
  bool _blinking = false;
  double _mouth = 0;
  Timer? _gazeTimer;
  Offset _gazeTarget = Offset.zero;
  Offset _gaze = Offset.zero;
  DateTime? _lastPointerAt;

  @override
  void initState() {
    super.initState();
    _attachGaze();
    _controller.whenAttached.then((_) async {
      try {
        var ok = false;
        // The platform view can attach before its GL surface has a size;
        // loadModel is deliberately rejected by the native side in that case.
        for (var attempt = 0; attempt < 6 && !ok; attempt++) {
          ok = await _controller
              .loadModel(
                modelDir: widget.modelDir,
                modelFileName: widget.modelFile,
              )
              .timeout(const Duration(seconds: 6), onTimeout: () => false);
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
          _startTail();
          _startGaze();
          _syncSpeakingMotion();
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
    if (oldWidget.gazeNotifier != widget.gazeNotifier) {
      oldWidget.gazeNotifier?.removeListener(_onGazeChanged);
      _attachGaze();
    }
    if (oldWidget.speaking != widget.speaking && _loaded) {
      _startMouth();
      _syncSpeakingMotion();
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

  void _syncSpeakingMotion() {
    _drawTimer?.cancel();
    if (!_loaded) return;
    if (widget.speaking) {
      _controller
          .startMotion(group: 'idle', priority: 2)
          .catchError((_) {});
      _drawTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_loaded || !widget.speaking) return;
        _controller
            .startMotion(group: 'idle', priority: 2)
            .catchError((_) {});
      });
    } else {
      _controller.startMotion(group: 'idle', priority: 1).catchError((_) {});
    }
  }

  void _attachGaze() {
    widget.gazeNotifier?.addListener(_onGazeChanged);
  }

  void _onGazeChanged() {
    final point = widget.gazeNotifier?.value;
    if (point == null) return;
    _gazeTarget = Offset(
      point.dx.clamp(-1.0, 1.0),
      point.dy.clamp(-1.0, 1.0),
    );
    _lastPointerAt = DateTime.now();
  }

  /// Restores gaze tracking: the eyes (ParamEyeBallX/Y) and head
  /// (ParamAngleX/Y/Z) follow the pointer, with an idle auto-sway when the user
  /// has not touched the stage for a while.
  void _startGaze() {
    _gazeTimer?.cancel();
    _gazeTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_loaded) return;
      final now = DateTime.now();
      final last = _lastPointerAt;
      if (last == null || now.difference(last) > const Duration(milliseconds: 2500)) {
        final phase = now.millisecondsSinceEpoch / 2400.0;
        _gazeTarget = Offset(
          math.sin(phase) * 0.32,
          math.sin(now.millisecondsSinceEpoch / 3800.0) * 0.18,
        );
      }
      _gaze = Offset(
        _gaze.dx + (_gazeTarget.dx - _gaze.dx) * 0.22,
        _gaze.dy + (_gazeTarget.dy - _gaze.dy) * 0.22,
      );
      _applyGaze(_gaze);
    });
  }

  void _applyGaze(Offset gaze) {
    final eyeX = gaze.dx;
    final eyeY = -gaze.dy;
    _controller.setParameter('ParamEyeBallX', eyeX).catchError((_) {});
    _controller.setParameter('ParamEyeBallY', eyeY).catchError((_) {});
    _controller.setParameter('ParamAngleX', gaze.dx * 22).catchError((_) {});
    _controller.setParameter('ParamAngleY', -gaze.dy * 14).catchError((_) {});
    _controller.setParameter('ParamAngleZ', gaze.dx * -4).catchError((_) {});
  }

  void _startTail() {
    _tailTimer?.cancel();
    _tailTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!_loaded) return;
      final phase = DateTime.now().millisecondsSinceEpoch / 850.0;
      final sway = math.sin(phase);
      // Tail_2 bends the whale tail; small values keep the idle silhouette.
      _controller
          .setParameter('Param10', 0.5 + sway * 0.22)
          .catchError((_) {});
      _controller
          .setParameter('Param_Angle_Rotation_1_B_tail3', 0.5 + sway * 0.18)
          .catchError((_) {});
      _controller
          .setParameter('Param_Angle_Rotation_2_B_tail3', 0.5 + sway * 0.14)
          .catchError((_) {});
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
    widget.gazeNotifier?.removeListener(_onGazeChanged);
    _blinkTimer?.cancel();
    _mouthTimer?.cancel();
    _tailTimer?.cancel();
    _drawTimer?.cancel();
    _gazeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback ?? SizedBox.shrink();
    return _buildStage();
  }

  Widget _buildStage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the platform view at a stable index. Do not put a conditional
        // fallback sibling in front of it: changing the child list after the
        // model loads recreates/detaches the native view.
        IgnorePointer(
          child: Transform.scale(
            scale: 1.18,
            alignment: Alignment.bottomCenter,
            child: Live2DView(
              key: ValueKey('chatvv-live2d-view'),
              controller: _controller,
            ),
          ),
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
