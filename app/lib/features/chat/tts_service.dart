import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../data/app_settings.dart';

typedef _TtsOptsNative = Int32 Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> optionsJson,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TtsOptsDart = int Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> optionsJson,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TtsLegacyNative = Int32 Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TtsLegacyDart = int Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

/// Speech output with a user selectable engine.
///
/// * [TtsEngine.edge] — Edge read-aloud (network) through the native read_aloud
///   backend, returns an MP3 file that is played by the platform audio channel.
/// * [TtsEngine.system] — the OS speech engine via `flutter_tts`.
///
/// Settings (engine, voice, rate, pitch, volume) come from [applySettings]; the
/// defaults keep the historical Edge behaviour when nothing is configured yet.
class TtsService {
  static const MethodChannel _audio = MethodChannel('chatvv/audio');
  final FlutterTts _system = FlutterTts();
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  AppSettings _settings = AppSettings.defaults();
  bool _ready = false;
  bool _systemReady = false;

  void applySettings(AppSettings settings) {
    _settings = settings;
  }

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    _audio.setMethodCallHandler((call) async {
      if (call.method == 'completed' || call.method == 'error') {
        _playbackWatchdog?.cancel();
        _playbackWatchdog = null;
        speaking.value = false;
      }
    });
    try {
      await _system.awaitSpeakCompletion(true);
      _system.setCompletionHandler(() => speaking.value = false);
      _system.setErrorHandler((message) {
        debugPrint('system TTS error: $message');
        speaking.value = false;
      });
      _systemReady = true;
    } catch (_) {
      _systemReady = false;
    }
  }

  Future<void> speak(String text) async {
    final clean = _plain(text);
    if (clean.isEmpty) return;
    await stop();
    speaking.value = true;

    final settings = _settings;
    if (settings.ttsEngine == TtsEngine.system) {
      if (await _speakSystem(clean, settings)) return;
      // System engine unavailable: fall back to Edge so the reply is still
      // spoken instead of going silent.
    }
    if (await _speakEdge(clean, settings)) return;
    if (settings.ttsEngine == TtsEngine.edge &&
        await _speakSystem(clean, settings)) {
      return;
    }
    speaking.value = false;
  }

  Future<bool> _speakEdge(String clean, AppSettings settings) async {
    try {
      final dir = await Directory.systemTemp.createTemp('chatvv_tts_');
      final path = '${dir.path}/reply.mp3';
      final options = jsonEncode({
        'pitch_hz': settings.ttsPitchHz,
        'rate': _edgeRate(settings.ttsRate),
        'volume': _edgeVolume(settings.ttsVolume),
      });
      final voice = settings.ttsVoice.trim().isEmpty
          ? 'zh-CN-XiaoyiNeural'
          : settings.ttsVoice.trim();
      final error = await Isolate.run(
        () => _edgeSynthesize(clean, voice, options, path),
      );
      if (error == null && File(path).existsSync()) {
        if (await _playFile(path)) return true;
      }
      debugPrint('Edge TTS failed: $error');
    } catch (error) {
      debugPrint('Edge TTS exception: $error');
    }
    return false;
  }

  Future<bool> _speakSystem(String clean, AppSettings settings) async {
    if (!_systemReady) return false;
    try {
      final locale = _localeFor(settings.ttsVoice);
      if (locale.isNotEmpty) await _system.setLanguage(locale);
      await _system.setSpeechRate(settings.ttsRate.clamp(0.1, 2.0));
      await _system.setPitch(
        (1.0 + settings.ttsPitchHz / 100.0).clamp(0.5, 2.0),
      );
      await _system.setVolume(settings.ttsVolume.clamp(0.0, 1.0));
      await _system.stop();
      await _system.speak(clean);
      return true;
    } catch (error) {
      debugPrint('system TTS exception: $error');
      return false;
    }
  }

  Future<void> stop() async {
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
    try {
      await _audio.invokeMethod('stop');
    } catch (_) {}
    if (_systemReady) {
      try {
        await _system.stop();
      } catch (_) {}
    }
    speaking.value = false;
  }

  Future<void> dispose() async {
    await stop();
    speaking.dispose();
  }

  Timer? _playbackWatchdog;

  void _armPlaybackWatchdog(int durationMs) {
    _playbackWatchdog?.cancel();
    final safeMs = durationMs > 0 ? durationMs : 120000;
    _playbackWatchdog = Timer(Duration(milliseconds: safeMs + 1500), () {
      if (!speaking.value) return;
      // The native completion callback can be lost (player released by another
      // screen etc.); never leave the speaking state/mouth animation stuck on.
      speaking.value = false;
      _audio.invokeMethod('stop').catchError((_) => null);
    });
  }

  Future<bool> _playFile(String path) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final durationMs =
            await _audio.invokeMethod<int>('play', {'path': path}) ?? -1;
        _armPlaybackWatchdog(durationMs);
        return true;
      } catch (error) {
        debugPrint('native audio failed: $error');
        return false;
      }
    }
    if (Platform.isLinux) {
      try {
        final process = await Process.start(
          'ffplay',
          ['-nodisp', '-autoexit', '-loglevel', 'quiet', path],
        );
        process.exitCode.then((_) => speaking.value = false);
        return true;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isMacOS) {
      try {
        final process = await Process.start('afplay', [path]);
        process.exitCode.then((_) => speaking.value = false);
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Edge TTS voice names are `locale-NameNeural` (`zh-CN-XiaoxiaoNeural`) or
  /// the full `Microsoft Server Speech ... (zh-CN, XiaoxiaoNeural)` form.
  String _localeFor(String voice) {
    final trimmed = voice.trim();
    final match = RegExp(r'^([a-z]{2,3}[-_][A-Z]{2})').firstMatch(trimmed);
    if (match != null) return match.group(1)!.replaceAll('_', '-');
    final full = RegExp(r'\(([a-z]{2,3})[-_, ]\s*').firstMatch(trimmed);
    if (full != null) return full.group(1)!;
    return 'zh-CN';
  }

  /// UI rate multiplier (0.3–2.0, 1.0 = service default) to read_aloud's
  /// relative rate in -1..1. The down side is stretched so 0.5 is clearly
  /// slower instead of barely noticeable.
  double _edgeRate(double rate) {
    if (rate < 1.0) {
      // 1.0 -> 0.0, 0.3 -> -1.0
      return ((rate - 1.0) / 0.7).clamp(-1.0, 0.0);
    }
    // 1.0 -> 0.0, 2.0 -> +0.9
    return ((rate - 1.0) * 0.9).clamp(0.0, 1.0);
  }

  /// UI volume (0–1) to read_aloud's relative volume offset.
  double _edgeVolume(double volume) => (volume - 1.0).clamp(-1.0, 0.0);

  String _plain(String input) {
    return input
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        // Never read parenthetical stage directions out loud:
        // （动作描写） / (stage direction) / 【旁白】 / [note].
        .replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), ' ')
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Runs in a short-lived isolate so the WebSocket handshake does not block
/// Flutter's UI thread. Returns null on success, otherwise an error string.
String? _edgeSynthesize(
  String text,
  String voice,
  String optionsJson,
  String path,
) {
  final library = _openLibrary();
  final free = library.lookupFunction<_FreeNative, _FreeDart>('chatvv_free');
  Pointer<Utf8>? textPtr;
  Pointer<Utf8>? voicePtr;
  Pointer<Utf8>? optionsPtr;
  Pointer<Utf8>? pathPtr;
  final errorPtr = calloc<Pointer<Utf8>>();
  try {
    textPtr = text.toNativeUtf8();
    voicePtr = voice.toNativeUtf8();
    optionsPtr = optionsJson.toNativeUtf8();
    pathPtr = path.toNativeUtf8();
    int rc;
    try {
      final synthOpts = library.lookupFunction<_TtsOptsNative, _TtsOptsDart>(
        'chatvv_tts_synthesize_opts',
      );
      rc = synthOpts(textPtr, voicePtr, optionsPtr, pathPtr, errorPtr);
    } on ArgumentError {
      // Older FFI library without the options entry point.
      final legacy = library.lookupFunction<_TtsLegacyNative, _TtsLegacyDart>(
        'chatvv_tts_synthesize',
      );
      rc = legacy(textPtr, voicePtr, pathPtr, errorPtr);
    }
    if (rc == 0) return null;
    final ptr = errorPtr.value;
    if (ptr == nullptr) return 'TTS failed ($rc)';
    final message = ptr.toDartString();
    free(ptr);
    return message;
  } finally {
    if (textPtr != null) calloc.free(textPtr);
    if (voicePtr != null) calloc.free(voicePtr);
    if (optionsPtr != null) calloc.free(optionsPtr);
    if (pathPtr != null) calloc.free(pathPtr);
    calloc.free(errorPtr);
  }
}

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid) return DynamicLibrary.open('libchatvv_ffi.so');
  final executable = File(Platform.resolvedExecutable);
  final bundled = switch (Platform.operatingSystem) {
    'linux' => '${executable.parent.path}/lib/libchatvv_ffi.so',
    'macos' => '${executable.parent.parent.path}/Frameworks/libchatvv_ffi.dylib',
    'windows' => '${executable.parent.path}/chatvv_ffi.dll',
    _ => null,
  };
  if (bundled != null && File(bundled).existsSync()) {
    return DynamicLibrary.open(bundled);
  }
  if (Platform.isLinux) return DynamicLibrary.open('libchatvv_ffi.so');
  if (Platform.isMacOS) return DynamicLibrary.open('libchatvv_ffi.dylib');
  if (Platform.isWindows) return DynamicLibrary.open('chatvv_ffi.dll');
  throw UnsupportedError('TTS is not available on this platform');
}
