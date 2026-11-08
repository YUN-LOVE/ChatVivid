import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

typedef _TtsNative = Int32 Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TtsDart = int Function(
  Pointer<Utf8> text,
  Pointer<Utf8> voice,
  Pointer<Utf8> outputPath,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

class TtsService {
  static const MethodChannel _audio = MethodChannel('chatvv/audio');
  final FlutterTts _system = FlutterTts();
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  bool _ready = false;
  bool _systemReady = false;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    _audio.setMethodCallHandler((call) async {
      if (call.method == 'completed' || call.method == 'error') {
        speaking.value = false;
      }
    });
    try {
      await _system.setLanguage('zh-CN');
      await _system.awaitSpeakCompletion(true);
      _system.setCompletionHandler(() => speaking.value = false);
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

    try {
      final dir = await Directory.systemTemp.createTemp('chatvv_tts_');
      final path = '${dir.path}/reply.mp3';
      final error = await Isolate.run(
        () => _edgeSynthesize(clean, 'zh-CN-XiaoxiaoNeural', path),
      );
      if (error == null && File(path).existsSync()) {
        final played = await _playFile(path);
        if (played) return;
      }
      debugPrint('Edge TTS failed: $error');
    } catch (error) {
      debugPrint('Edge TTS exception: $error');
    }

    // Network/Edge unavailable: keep the system engine as a last resort.
    if (_systemReady) {
      try {
        await _system.speak(clean);
        return;
      } catch (_) {}
    }
    speaking.value = false;
  }

  Future<void> stop() async {
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

  Future<bool> _playFile(String path) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await _audio.invokeMethod('play', {'path': path});
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

  String _plain(String input) {
    return input
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'[*_`#>\[\]()]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// Runs in a short-lived isolate so the WebSocket handshake does not block
/// Flutter's UI thread. Returns null on success, otherwise an error string.
String? _edgeSynthesize(String text, String voice, String path) {
  final library = _openLibrary();
  final synth = library.lookupFunction<_TtsNative, _TtsDart>(
    'chatvv_tts_synthesize',
  );
  final free = library.lookupFunction<_FreeNative, _FreeDart>('chatvv_free');
  final textPtr = text.toNativeUtf8();
  final voicePtr = voice.toNativeUtf8();
  final pathPtr = path.toNativeUtf8();
  final errorPtr = calloc<Pointer<Utf8>>();
  try {
    final rc = synth(textPtr, voicePtr, pathPtr, errorPtr);
    if (rc == 0) return null;
    final ptr = errorPtr.value;
    if (ptr == nullptr) return 'TTS failed ($rc)';
    final message = ptr.toDartString();
    free(ptr);
    return message;
  } finally {
    calloc.free(textPtr);
    calloc.free(voicePtr);
    calloc.free(pathPtr);
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
