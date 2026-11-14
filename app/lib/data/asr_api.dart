import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// FFI bindings for the ChatVivid ASR C ABI (include/chatvv/chatvv.h,
// chatvv_asr_*). One engine owns one loaded whisper.cpp model.
//
// This is a data-layer binding only: it is intentionally not wired into the UI
// and does not depend on Flutter widgets. The native C++ library is loaded with
// the same search order as ffi_chat_api.dart.
//
// Native calls are blocking (model load takes seconds, transcription can take
// seconds per minute of audio), so every native operation runs in a background
// isolate via [Isolate.run]. A native engine address is just a process-wide
// pointer; the engine is created in one worker isolate and can be used from
// another as long as the owning [AsrEngine] is not disposed concurrently.
//
// Models are not bundled: download a ggml Whisper model (ggml-tiny.bin,
// ggml-base.bin, ...) separately, see docs/asr.md.

/// Error thrown by the ASR bindings. [code] is the stable machine-readable
/// code from the native error JSON (e.g. `invalid_wav`, `model_load_failed`).
class AsrApiException implements Exception {
  const AsrApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

/// One transcript segment; times are milliseconds from the start of the audio.
class AsrSegment {
  const AsrSegment({
    required this.id,
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  factory AsrSegment.fromJson(Map<String, dynamic> json) => AsrSegment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
        endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
        text: json['text']?.toString() ?? '',
      );

  final int id;
  final int startMs;
  final int endMs;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'start_ms': startMs,
        'end_ms': endMs,
        'text': text,
      };
}

/// Result of one transcription (the native `chatvv_asr_transcribe_*` JSON).
class AsrTranscript {
  const AsrTranscript({
    required this.text,
    required this.language,
    required this.model,
    required this.durationMs,
    required this.segments,
  });

  factory AsrTranscript.fromJson(Map<String, dynamic> json) {
    final segments = <AsrSegment>[];
    final rawSegments = json['segments'];
    if (rawSegments is List) {
      for (final item in rawSegments) {
        if (item is Map) {
          segments.add(
            AsrSegment.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return AsrTranscript(
      text: json['text']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      segments: List<AsrSegment>.unmodifiable(segments),
    );
  }

  final String text;
  final String language;
  final String model;
  final int durationMs;
  final List<AsrSegment> segments;

  bool get isEmpty => text.trim().isEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'language': language,
        'model': model,
        'duration_ms': durationMs,
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };
}

/// Build/engine capabilities (the native `chatvv_asr_capabilities` JSON).
class AsrCapabilities {
  const AsrCapabilities({
    required this.engine,
    required this.version,
    required this.loaded,
    required this.model,
    required this.sampleRate,
    required this.audioFormats,
    required this.languages,
    required this.backends,
    required this.gpuAvailable,
    required this.gpuRequested,
    required this.gpuActive,
    required this.flashAttn,
    required this.threads,
    required this.supportsTranslate,
  });

  factory AsrCapabilities.fromJson(Map<String, dynamic> json) {
    List<String> stringList(Object? value) {
      if (value is! List) return const [];
      return value.map((item) => item.toString()).toList(growable: false);
    }

    return AsrCapabilities(
      engine: json['engine']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      loaded: json['loaded'] == true,
      model: json['model']?.toString() ?? '',
      sampleRate: (json['sample_rate'] as num?)?.toInt() ?? 16000,
      audioFormats: stringList(json['audio_formats']),
      languages: stringList(json['languages']),
      backends: stringList(json['backends']),
      gpuAvailable: json['gpu_available'] == true,
      gpuRequested: json['gpu_requested'] == true,
      gpuActive: json['gpu_active'] == true,
      flashAttn: json['flash_attn'] == true,
      threads: (json['threads'] as num?)?.toInt() ?? 0,
      supportsTranslate: json['supports_translate'] == true,
    );
  }

  final String engine;
  final String version;
  final bool loaded;
  final String model;
  final int sampleRate;
  final List<String> audioFormats;
  final List<String> languages;
  final List<String> backends;
  final bool gpuAvailable;
  final bool gpuRequested;
  final bool gpuActive;
  final bool flashAttn;
  final int threads;
  final bool supportsTranslate;
}

// ---------------------------------------------------------------------------
// Native typedefs
// ---------------------------------------------------------------------------

typedef _CreateNative = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _CreateDart = Pointer<Void> Function(
  Pointer<Utf8> modelPath,
  Pointer<Utf8> configJson,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _DestroyNative = Void Function(Pointer<Void> asr);
typedef _DestroyDart = void Function(Pointer<Void> asr);

typedef _TranscribeFileNative = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Utf8> wavPath,
  Pointer<Utf8> optionsJson,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TranscribeFileDart = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Utf8> wavPath,
  Pointer<Utf8> optionsJson,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _TranscribePcmNative = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Float> samples,
  Int32 sampleCount,
  Int32 sampleRate,
  Pointer<Utf8> optionsJson,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _TranscribePcmDart = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Float> samples,
  int sampleCount,
  int sampleRate,
  Pointer<Utf8> optionsJson,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _CapabilitiesNative = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _CapabilitiesDart = Pointer<Utf8> Function(
  Pointer<Void> asr,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

/// Symbol lookups for one loaded `chatvv_ffi` library handle.
class _AsrBindings {
  _AsrBindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'chatvv_asr_create',
        ),
        destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
          'chatvv_asr_destroy',
        ),
        transcribeFile =
            library.lookupFunction<_TranscribeFileNative, _TranscribeFileDart>(
          'chatvv_asr_transcribe_file',
        ),
        transcribePcm =
            library.lookupFunction<_TranscribePcmNative, _TranscribePcmDart>(
          'chatvv_asr_transcribe_pcm',
        ),
        capabilities =
            library.lookupFunction<_CapabilitiesNative, _CapabilitiesDart>(
          'chatvv_asr_capabilities',
        ),
        free = library.lookupFunction<_FreeNative, _FreeDart>('chatvv_free');

  final _CreateDart create;
  final _DestroyDart destroy;
  final _TranscribeFileDart transcribeFile;
  final _TranscribePcmDart transcribePcm;
  final _CapabilitiesDart capabilities;
  final _FreeDart free;
}

// ---------------------------------------------------------------------------
// Background-isolate tasks. They only use sendable arguments (String, int,
// bool, Map, TransferableTypedData) and return plain maps.
// ---------------------------------------------------------------------------

Map<String, Object?> _ok([Map<String, Object?> fields = const {}]) =>
    <String, Object?>{'ok': true, ...fields};

Map<String, Object?> _failure(String message, [String? code]) =>
    <String, Object?>{
      'ok': false,
      'code': code ?? 'asr_failed',
      'message': message,
    };

Map<String, Object?> _exceptionFailure(Object error) {
  if (error is AsrApiException) {
    return _failure(error.message, error.code);
  }
  if (error is ArgumentError) {
    // lookupFunction throws ArgumentError when the loaded library predates the
    // ASR ABI; make that actionable instead of surfacing a raw symbol error.
    return _failure(
      '当前 chatvv_ffi 动态库不包含 ASR 符号（chatvv_asr_*），'
      '请使用包含 ASR 的构建产物重新打包：$error',
      'asr_symbol_missing',
    );
  }
  return _failure(error.toString(), 'asr_native_error');
}

/// Parses `{"code","message"}` written through `char** error_json` and frees it.
Map<String, Object?> _nativeFailure(
  _AsrBindings bindings,
  Pointer<Pointer<Utf8>> errorPtr,
) {
  final pointer = errorPtr.value;
  if (pointer.address == 0) {
    return _failure('FFI 调用失败');
  }
  final raw = pointer.toDartString();
  bindings.free(pointer);
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return _failure(
        decoded['message']?.toString() ?? raw,
        decoded['code']?.toString(),
      );
    }
  } on FormatException {
    // Fall through and report the raw native error string.
  }
  return _failure(raw);
}

String? _encodeJson(Map<String, Object?>? values) {
  if (values == null || values.isEmpty) return null;
  return jsonEncode(values);
}

Pointer<Utf8> _toNative(String? value) =>
    value == null ? nullptr : value.toNativeUtf8();

void _freeNative(Pointer<Utf8> pointer) {
  if (pointer.address != 0) calloc.free(pointer);
}

Map<String, Object?> _createEngineTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    final modelPathPtr = (args['modelPath'] as String).toNativeUtf8();
    final configPtr = _toNative(args['configJson'] as String?);
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final engine = bindings.create(modelPathPtr, configPtr, errorPtr);
      if (engine.address == 0) return _nativeFailure(bindings, errorPtr);
      return _ok({'address': engine.address});
    } finally {
      _freeNative(modelPathPtr);
      _freeNative(configPtr);
      calloc.free(errorPtr);
    }
  } catch (error) {
    return _exceptionFailure(error);
  }
}

Map<String, Object?> _destroyEngineTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    bindings.destroy(Pointer<Void>.fromAddress(args['address'] as int));
    return _ok();
  } catch (error) {
    return _exceptionFailure(error);
  }
}

String _transcribeFileWith(
  _AsrBindings bindings,
  Pointer<Void> engine,
  Map<String, Object?> args,
) {
  final wavPathPtr = (args['wavPath'] as String).toNativeUtf8();
  final optionsPtr = _toNative(args['optionsJson'] as String?);
  final errorPtr = calloc<Pointer<Utf8>>();
  try {
    final result =
        bindings.transcribeFile(engine, wavPathPtr, optionsPtr, errorPtr);
    if (result.address == 0) {
      final failure = _nativeFailure(bindings, errorPtr);
      throw AsrApiException(
        failure['message'] as String,
        code: failure['code'] as String?,
      );
    }
    final json = result.toDartString();
    bindings.free(result);
    return json;
  } finally {
    _freeNative(wavPathPtr);
    _freeNative(optionsPtr);
    calloc.free(errorPtr);
  }
}

Map<String, Object?> _transcribeFileTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    final json = _transcribeFileWith(
      bindings,
      Pointer<Void>.fromAddress(args['address'] as int),
      args,
    );
    return _ok({'json': json});
  } catch (error) {
    return _exceptionFailure(error);
  }
}

Map<String, Object?> _transcribeFileOnceTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    final modelPathPtr = (args['modelPath'] as String).toNativeUtf8();
    final configPtr = _toNative(args['configJson'] as String?);
    final errorPtr = calloc<Pointer<Utf8>>();
    Pointer<Void> engine = nullptr;
    try {
      engine = bindings.create(modelPathPtr, configPtr, errorPtr);
      if (engine.address == 0) return _nativeFailure(bindings, errorPtr);
      final json = _transcribeFileWith(bindings, engine, args);
      return _ok({'json': json});
    } finally {
      if (engine.address != 0) bindings.destroy(engine);
      _freeNative(modelPathPtr);
      _freeNative(configPtr);
      calloc.free(errorPtr);
    }
  } catch (error) {
    return _exceptionFailure(error);
  }
}

Map<String, Object?> _transcribePcmTask(
  Map<String, Object?> args, {
  required Pointer<Void> engine,
  required _AsrBindings bindings,
}) {
  final samples =
      (args['pcm'] as TransferableTypedData).materialize().asFloat32List();
  final nativeSamples = calloc<Float>(samples.length);
  nativeSamples.asTypedList(samples.length).setAll(0, samples);
  final optionsPtr = _toNative(args['optionsJson'] as String?);
  final errorPtr = calloc<Pointer<Utf8>>();
  try {
    final result = bindings.transcribePcm(
      engine,
      nativeSamples,
      samples.length,
      args['sampleRate'] as int,
      optionsPtr,
      errorPtr,
    );
    if (result.address == 0) {
      final failure = _nativeFailure(bindings, errorPtr);
      throw AsrApiException(
        failure['message'] as String,
        code: failure['code'] as String?,
      );
    }
    final json = result.toDartString();
    bindings.free(result);
    return _ok({'json': json});
  } finally {
    _freeNative(optionsPtr);
    calloc.free(nativeSamples);
    calloc.free(errorPtr);
  }
}

Map<String, Object?> _transcribePcmWithEngineTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    return _transcribePcmTask(
      args,
      engine: Pointer<Void>.fromAddress(args['address'] as int),
      bindings: bindings,
    );
  } catch (error) {
    return _exceptionFailure(error);
  }
}

Map<String, Object?> _transcribePcmOnceTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    final modelPathPtr = (args['modelPath'] as String).toNativeUtf8();
    final configPtr = _toNative(args['configJson'] as String?);
    final errorPtr = calloc<Pointer<Utf8>>();
    Pointer<Void> engine = nullptr;
    try {
      engine = bindings.create(modelPathPtr, configPtr, errorPtr);
      if (engine.address == 0) return _nativeFailure(bindings, errorPtr);
      return _transcribePcmTask(args, engine: engine, bindings: bindings);
    } finally {
      if (engine.address != 0) bindings.destroy(engine);
      _freeNative(modelPathPtr);
      _freeNative(configPtr);
      calloc.free(errorPtr);
    }
  } catch (error) {
    return _exceptionFailure(error);
  }
}

Map<String, Object?> _capabilitiesTask(Map<String, Object?> args) {
  try {
    final bindings =
        _AsrBindings(DynamicLibrary.open(args['library'] as String));
    final address = args['address'] as int?;
    final engine =
        address == null ? nullptr : Pointer<Void>.fromAddress(address);
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final result = bindings.capabilities(engine, errorPtr);
      if (result.address == 0) return _nativeFailure(bindings, errorPtr);
      final json = result.toDartString();
      bindings.free(result);
      return _ok({'json': json});
    } finally {
      calloc.free(errorPtr);
    }
  } catch (error) {
    return _exceptionFailure(error);
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

Map<String, dynamic> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  throw const AsrApiException('ASR 响应不是 JSON 对象', code: 'bad_response');
}

Map<String, Object?> _decodeNativeResult(Map<String, Object?> result) {
  if (result['ok'] != true) {
    throw AsrApiException(
      result['message']?.toString() ?? 'ASR 调用失败',
      code: result['code']?.toString(),
    );
  }
  return result;
}

/// Entry point for the ASR FFI. Opening an [AsrApi] loads the native library and
/// keeps a handle alive so engines created through it stay valid; it does not
/// load a model.
///
/// Use [createEngine] for repeated transcriptions with one loaded model, or the
/// one-shot [transcribeFileOnce]/[transcribePcmOnce] helpers which load and free
/// the model inside a single background isolate.
///
/// All native work runs in a background isolate, so these futures never block
/// the Flutter UI isolate.
class AsrApi {
  AsrApi({String? libraryPath})
      : _libraryPath = _resolveLibraryPath(libraryPath) {
    try {
      // Keep one handle on the calling isolate so the library cannot be
      // unloaded between Isolate.run tasks that use the same native engine.
      _library = DynamicLibrary.open(_libraryPath);
    } on Object catch (error) {
      throw AsrApiException(
        '无法加载 chatvv ASR 动态库（$_libraryPath）：$error',
        code: 'asr_sdk_load_failed',
      );
    }
    if (!_library.providesSymbol('chatvv_asr_create')) {
      throw AsrApiException(
        '当前 chatvv_ffi 动态库不包含 ASR 符号（chatvv_asr_*），'
        '请使用包含 ASR 的构建产物重新打包：$_libraryPath',
        code: 'asr_symbol_missing',
      );
    }
  }

  final String _libraryPath;
  late final DynamicLibrary _library;
  final Set<AsrEngine> _engines = <AsrEngine>{};
  bool _disposed = false;

  /// The resolved native library path/name used by this instance.
  String get libraryPath => _libraryPath;

  /// Build-level capabilities (no model required).
  Future<AsrCapabilities> capabilities() => _capabilitiesFor(null);

  /// One-shot: loads [modelPath], transcribes WAV file [wavPath], frees the
  /// model. The whole pipeline runs in one background isolate.
  Future<AsrTranscript> transcribeFileOnce({
    required String modelPath,
    required String wavPath,
    String language = 'auto',
    bool useGpu = true,
    int threads = 0,
    bool flashAttn = false,
    bool translate = false,
  }) async {
    _ensureOpen();
    _requireNonEmpty('modelPath', modelPath);
    _requireNonEmpty('wavPath', wavPath);
    final args = <String, Object?>{
      'library': _libraryPath,
      'modelPath': modelPath,
      'configJson': _encodeJson(<String, Object?>{
        'use_gpu': useGpu,
        'threads': threads,
        'flash_attn': flashAttn,
      }),
      'wavPath': wavPath,
      'optionsJson': _encodeJson(<String, Object?>{
        'language': language,
        'threads': threads,
        'translate': translate,
      }),
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _transcribeFileOnceTask(args)),
    );
    return AsrTranscript.fromJson(_decodeObject(result['json'] as String));
  }

  /// One-shot: loads [modelPath], transcribes mono float32 PCM, frees the model.
  ///
  /// [samples] are mono float samples in [-1, 1]; [sampleRate] may be any
  /// positive rate (non-16 kHz input is resampled natively). The samples are
  /// transferred to the worker isolate without an extra copy.
  Future<AsrTranscript> transcribePcmOnce({
    required String modelPath,
    required Float32List samples,
    int sampleRate = 16000,
    String language = 'auto',
    bool useGpu = true,
    int threads = 0,
    bool flashAttn = false,
    bool translate = false,
  }) async {
    _ensureOpen();
    _requireNonEmpty('modelPath', modelPath);
    if (samples.isEmpty) {
      throw const AsrApiException('samples 不能为空', code: 'audio_empty');
    }
    if (sampleRate <= 0) {
      throw const AsrApiException(
        'sampleRate 必须大于 0',
        code: 'invalid_argument',
      );
    }
    final args = <String, Object?>{
      'library': _libraryPath,
      'modelPath': modelPath,
      'configJson': _encodeJson(<String, Object?>{
        'use_gpu': useGpu,
        'threads': threads,
        'flash_attn': flashAttn,
      }),
      'pcm': TransferableTypedData.fromList(<TypedData>[samples]),
      'sampleRate': sampleRate,
      'optionsJson': _encodeJson(<String, Object?>{
        'language': language,
        'threads': threads,
        'translate': translate,
      }),
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _transcribePcmOnceTask(args)),
    );
    return AsrTranscript.fromJson(_decodeObject(result['json'] as String));
  }

  /// Loads a Whisper model in a background isolate and returns a reusable
  /// [AsrEngine]. Throws [AsrApiException] when the model cannot be loaded.
  Future<AsrEngine> createEngine({
    required String modelPath,
    bool useGpu = true,
    int threads = 0,
    bool flashAttn = false,
  }) async {
    _ensureOpen();
    _requireNonEmpty('modelPath', modelPath);
    final args = <String, Object?>{
      'library': _libraryPath,
      'modelPath': modelPath,
      'configJson': _encodeJson(<String, Object?>{
        'use_gpu': useGpu,
        'threads': threads,
        'flash_attn': flashAttn,
      }),
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _createEngineTask(args)),
    );
    final engine = AsrEngine._(
      this,
      Pointer<Void>.fromAddress(result['address'] as int),
      modelPath: modelPath,
    );
    _engines.add(engine);
    return engine;
  }

  /// Disposes every engine created by this API and releases the native library
  /// handle held by the calling isolate. Further calls throw.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final engine in _engines.toList(growable: false)) {
      await engine.dispose();
    }
    _engines.clear();
  }

  Future<AsrCapabilities> _capabilitiesFor(AsrEngine? engine) async {
    _ensureOpen();
    final args = <String, Object?>{
      'library': _libraryPath,
      'address': engine?._address?.address,
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _capabilitiesTask(args)),
    );
    return AsrCapabilities.fromJson(_decodeObject(result['json'] as String));
  }

  void _removeEngine(AsrEngine engine) {
    _engines.remove(engine);
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const AsrApiException('ASR API 已释放', code: 'asr_disposed');
    }
  }

  static void _requireNonEmpty(String name, String value) {
    if (value.isEmpty) {
      throw AsrApiException('$name 不能为空', code: 'invalid_argument');
    }
  }

  static String _resolveLibraryPath(String? explicitPath) {
    final configured = explicitPath ??
        const String.fromEnvironment('CHATVV_FFI_LIB', defaultValue: '');
    if (configured.isNotEmpty) return configured;
    if (Platform.isAndroid) return 'libchatvv_ffi.so';

    final executable = File(Platform.resolvedExecutable);
    final bundled = switch (Platform.operatingSystem) {
      'linux' => '${executable.parent.path}/lib/libchatvv_ffi.so',
      'macos' =>
        '${executable.parent.parent.path}/Frameworks/libchatvv_ffi.dylib',
      'windows' => '${executable.parent.path}/chatvv_ffi.dll',
      _ => null,
    };
    if (bundled != null && File(bundled).existsSync()) return bundled;
    if (Platform.isLinux) return 'libchatvv_ffi.so';
    if (Platform.isMacOS) return 'libchatvv_ffi.dylib';
    if (Platform.isWindows) return 'chatvv_ffi.dll';
    throw const AsrApiException('当前平台不支持 FFI ASR 后端');
  }
}

/// A reusable ASR engine: one loaded whisper.cpp model that can transcribe any
/// number of files/PCM buffers. Every call runs in a background isolate.
///
/// The native engine serializes concurrent transcriptions internally, but
/// [dispose] must not race with an in-flight transcription.
class AsrEngine {
  AsrEngine._(this._api, this._address, {required this.modelPath});

  final AsrApi _api;
  final String modelPath;
  Pointer<Void>? _address;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Transcribes a WAV file (PCM 8/16/24/32-bit or IEEE float; mono or
  /// multi-channel; any rate is resampled to 16 kHz natively).
  Future<AsrTranscript> transcribeFile(
    String wavPath, {
    String language = 'auto',
    int threads = 0,
    bool translate = false,
  }) async {
    final address = _ensureUsable();
    if (wavPath.isEmpty) {
      throw const AsrApiException('wavPath 不能为空', code: 'invalid_argument');
    }
    final args = <String, Object?>{
      'library': _api._libraryPath,
      'address': address.address,
      'wavPath': wavPath,
      'optionsJson': _encodeJson(<String, Object?>{
        'language': language,
        'threads': threads,
        'translate': translate,
      }),
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _transcribeFileTask(args)),
    );
    return AsrTranscript.fromJson(_decodeObject(result['json'] as String));
  }

  /// Transcribes mono float32 PCM in [-1, 1] at [sampleRate] Hz.
  Future<AsrTranscript> transcribePcm(
    Float32List samples, {
    int sampleRate = 16000,
    String language = 'auto',
    int threads = 0,
    bool translate = false,
  }) async {
    final address = _ensureUsable();
    if (samples.isEmpty) {
      throw const AsrApiException('samples 不能为空', code: 'audio_empty');
    }
    if (sampleRate <= 0) {
      throw const AsrApiException(
        'sampleRate 必须大于 0',
        code: 'invalid_argument',
      );
    }
    final args = <String, Object?>{
      'library': _api._libraryPath,
      'address': address.address,
      'pcm': TransferableTypedData.fromList(<TypedData>[samples]),
      'sampleRate': sampleRate,
      'optionsJson': _encodeJson(<String, Object?>{
        'language': language,
        'threads': threads,
        'translate': translate,
      }),
    };
    final result = _decodeNativeResult(
      await Isolate.run(() => _transcribePcmWithEngineTask(args)),
    );
    return AsrTranscript.fromJson(_decodeObject(result['json'] as String));
  }

  /// Capabilities of this loaded engine (model, GPU state, backends).
  Future<AsrCapabilities> capabilities() => _api._capabilitiesFor(this);

  /// Frees the native engine and its model.
  Future<void> dispose() async {
    if (_disposed) return;
    final address = _address;
    _disposed = true;
    _address = null;
    _api._removeEngine(this);
    if (address == null) return;
    final result = await Isolate.run(
      () => _destroyEngineTask(<String, Object?>{
        'library': _api._libraryPath,
        'address': address.address,
      }),
    );
    if (result['ok'] != true) {
      throw AsrApiException(
        result['message']?.toString() ?? 'ASR 引擎释放失败',
        code: result['code']?.toString(),
      );
    }
  }

  Pointer<Void> _ensureUsable() {
    if (_disposed) {
      throw const AsrApiException('ASR 引擎已释放', code: 'asr_disposed');
    }
    final address = _address;
    if (address == null) {
      throw const AsrApiException('ASR 引擎地址无效', code: 'asr_disposed');
    }
    return address;
  }
}
