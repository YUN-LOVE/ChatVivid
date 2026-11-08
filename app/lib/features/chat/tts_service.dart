import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the platform TTS engine. Edge TTS is intentionally not
/// wired here yet; this gives the UI a working speaker path on devices where a
/// system voice is available.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  bool _ready = false;
  bool _available = false;

  bool get available => _available;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.05);
      await _tts.awaitSpeakCompletion(true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
      _available = true;
    } catch (error) {
      debugPrint('TTS unavailable: $error');
      _available = false;
    }
  }

  Future<void> speak(String text) async {
    final clean = _plain(text);
    if (clean.isEmpty || !_available) return;
    await stop();
    speaking.value = true;
    try {
      await _tts.speak(clean);
    } catch (error) {
      debugPrint('TTS speak failed: $error');
      speaking.value = false;
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }

  Future<void> dispose() async {
    await stop();
    speaking.dispose();
  }

  String _plain(String input) {
    return input
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'[*_`#>\[\]()]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
