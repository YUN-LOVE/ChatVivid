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

  /// True while the Edge request is in flight / the TTS engine is preparing
  /// audio. The mouth must NOT animate during this phase; [speaking] only
  /// becomes true once playback actually starts.
  final ValueNotifier<bool> synthesizing = ValueNotifier(false);

  bool get active => speaking.value || synthesizing.value;

  // ---- sentence-level streaming speech (LLM deltas -> TTS chunks) ----
  bool _streamActive = false;
  bool _streamClosing = false;
  int _streamSession = 0;
  String _streamText = '';
  String _streamPending = '';
  String _streamReplyId = '';
  final List<_SpeechChunk> _streamChunks = [];
  Future<void>? _streamWorker;

  bool get streamActive => _streamActive;
  String get streamReplyId => _streamReplyId;

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
        _cancelSpeakingStart();
        _playbackWatchdog?.cancel();
        _playbackWatchdog = null;
        speaking.value = false;
        final done = _playbackDone;
        _playbackDone = null;
        if (done != null && !done.isCompleted) done.complete();
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

  /// Starts a streaming speech session. Feed the growing assistant text with
  /// [feedSpeechStream]; completed sentences are synthesized eagerly (next
  /// sentence while the current one plays) and played in order, so the first
  /// audio starts after one short sentence instead of after the whole reply.
  void beginSpeechStream(String replyId) {
    _cancelSpeechStream();
    _streamActive = true;
    _streamClosing = false;
    _streamSession += 1;
    _streamText = '';
    _streamPending = '';
    _streamReplyId = replyId;
    _streamChunks.clear();
    synthesizing.value = true;
    speaking.value = false;
    _cancelSpeakingStart();
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
    _audio.invokeMethod('stop').catchError((_) => null);
    if (_systemReady) _system.stop().catchError((_) => null);
  }

  void feedSpeechStream(String fullText) {
    if (!_streamActive) return;
    if (fullText.length <= _streamText.length) return;
    final delta = fullText.substring(_streamText.length);
    _streamText = fullText;
    _streamPending += delta;
    _drainCompleteSentences();
  }

  Future<void> finishSpeechStream() async {
    if (!_streamActive) return;
    _drainCompleteSentences();
    final tail = _streamPending.trim();
    _streamPending = '';
    if (tail.isNotEmpty) _enqueueSentence(tail);
    _streamClosing = true;
    final worker = _streamWorker;
    if (worker != null) {
      try {
        await worker;
      } catch (_) {}
    }
    if (_streamActive) {
      _streamActive = false;
      synthesizing.value = false;
      speaking.value = false;
    }
  }

  void _drainCompleteSentences() {
    final terminators = RegExp(r'[。！？!?；;…\n]');
    while (true) {
      final match = terminators.firstMatch(_streamPending);
      if (match == null) break;
      final end = match.end;
      final sentence = _streamPending.substring(0, end).trim();
      _streamPending = _streamPending.substring(end);
      if (sentence.isNotEmpty) _enqueueSentence(sentence);
    }
  }

  void _enqueueSentence(String raw) {
    final clean = _plain(raw);
    if (clean.isEmpty) return;
    _streamChunks.add(
      _SpeechChunk(
        clean,
        _settings.ttsEngine == TtsEngine.edge
            ? _synthesizeEdgeFile(clean)
            : null,
      ),
    );
    _ensureStreamWorker();
  }

  void _ensureStreamWorker() {
    if (_streamWorker != null) return;
    final session = _streamSession;
    _streamWorker = _runStreamWorker(session).whenComplete(() {
      _streamWorker = null;
      if (_streamActive &&
          session == _streamSession &&
          _streamChunks.isNotEmpty) {
        _ensureStreamWorker();
      }
    });
  }

  Future<void> _runStreamWorker(int session) async {
    while (_streamActive && session == _streamSession) {
      if (_streamChunks.isEmpty) {
        if (_streamClosing) break;
        return;
      }
      final chunk = _streamChunks.removeAt(0);
      try {
        if (chunk.file != null) {
          final file = await chunk.file;
          if (!_streamActive || session != _streamSession) return;
          if (file == null) continue;
          await _playChunkAndWait(file);
        } else {
          await _speakSystem(chunk.text, _settings);
        }
      } catch (error) {
        debugPrint('streaming TTS chunk failed: $error');
      }
    }
  }

  Future<void> _playChunkAndWait(String path) async {
    final done = Completer<void>();
    _playbackDone = done;
    final played = await _playFile(path);
    if (!played) {
      if (!done.isCompleted) done.complete();
      _playbackDone = null;
      return;
    }
    _startSpeakingAfter(_settings.ttsLipSyncOffsetMs.clamp(0, 1500));
    try {
      await done.future;
    } catch (_) {}
    _playbackDone = null;
  }

  void _cancelSpeechStream() {
    _streamSession += 1;
    _streamActive = false;
    _streamClosing = false;
    _streamText = '';
    _streamPending = '';
    _streamReplyId = '';
    _streamChunks.clear();
    _streamWorker = null;
    final done = _playbackDone;
    _playbackDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<String?> _synthesizeEdgeFile(String clean) async {
    try {
      final dir = await Directory.systemTemp.createTemp('chatvv_tts_');
      final path = '${dir.path}/reply.mp3';
      final settings = _settings;
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
      if (error == null && File(path).existsSync()) return path;
      debugPrint('Edge streaming TTS failed: $error');
    } catch (error) {
      debugPrint('Edge streaming TTS exception: $error');
    }
    return null;
  }

  Future<void> speak(String text) async {
    final clean = _plain(text);
    if (clean.isEmpty) return;
    await stop();
    synthesizing.value = true;
    var handled = false;

    final settings = _settings;
    if (settings.ttsEngine == TtsEngine.system) {
      handled = await _speakSystem(clean, settings);
      // System engine unavailable: fall back to Edge so the reply is still
      // spoken instead of going silent.
    }
    if (!handled) handled = await _speakEdge(clean, settings);
    if (!handled && settings.ttsEngine == TtsEngine.edge) {
      handled = await _speakSystem(clean, settings);
    }
    synthesizing.value = false;
    if (!handled) speaking.value = false;
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
        if (await _startPlayback(path)) return true;
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
      _startSpeakingAfter(_settings.ttsLipSyncOffsetMs);
      await _system.speak(clean);
      return true;
    } catch (error) {
      debugPrint('system TTS exception: $error');
      return false;
    }
  }

  Future<void> stop() async {
    _cancelSpeechStream();
    _cancelSpeakingStart();
    _playbackWatchdog?.cancel();
    _playbackWatchdog = null;
    synthesizing.value = false;
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
  Completer<void>? _playbackDone;

  void _armPlaybackWatchdog(int durationMs) {
    _playbackWatchdog?.cancel();
    final safeMs = durationMs > 0 ? durationMs : 120000;
    _playbackWatchdog = Timer(Duration(milliseconds: safeMs + 1500), () {
      final done = _playbackDone;
      _playbackDone = null;
      if (done != null && !done.isCompleted) done.complete();
      if (!speaking.value) return;
      // The native completion callback can be lost (player released by another
      // screen etc.); never leave the speaking state/mouth animation stuck on.
      speaking.value = false;
      _audio.invokeMethod('stop').catchError((_) => null);
    });
  }

  Timer? _speakingStartTimer;

  void _cancelSpeakingStart() {
    _speakingStartTimer?.cancel();
    _speakingStartTimer = null;
  }

  /// Starts the mouth animation relative to the actual audio start. Positive
  /// [offsetMs] delays it (compensating output latency), so synthesis time no
  /// longer shows as "mouth moving before any sound".
  void _startSpeakingAfter(int offsetMs) {
    _cancelSpeakingStart();
    if (offsetMs <= 0) {
      speaking.value = true;
      return;
    }
    _speakingStartTimer = Timer(Duration(milliseconds: offsetMs), () {
      if (!synthesizing.value) speaking.value = true;
    });
  }

  Future<bool> _startPlayback(String path) async {
    _cancelSpeakingStart();
    final offset = _settings.ttsLipSyncOffsetMs.clamp(0, 1500);
    final played = await _playFile(path);
    if (!played) return false;
    _startSpeakingAfter(offset);
    return true;
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


class _SpeechChunk {
  _SpeechChunk(this.text, this.file);

  final String text;
  final Future<String?>? file;
}
