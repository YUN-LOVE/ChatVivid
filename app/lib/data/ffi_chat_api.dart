import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../features/chat/chat_models.dart';
import 'chat_backend.dart';
import 'memory_entry.dart';
import 'prompt_injection.dart';

typedef _CreateNative = Pointer<Void> Function(
  Pointer<Utf8> configJson,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _CreateDart = Pointer<Void> Function(
  Pointer<Utf8> configJson,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _DestroyNative = Void Function(Pointer<Void> engine);
typedef _DestroyDart = void Function(Pointer<Void> engine);

typedef _EventCallbackNative = Void Function(
  Pointer<Void> userData,
  Int32 eventType,
  Pointer<Utf8> eventJson,
);
typedef _SendExNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Utf8> text,
  Pointer<Utf8> injectionsJson,
  Pointer<NativeFunction<_EventCallbackNative>> callback,
  Pointer<Void> userData,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _SendExDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Utf8> text,
  Pointer<Utf8> injectionsJson,
  Pointer<NativeFunction<_EventCallbackNative>> callback,
  Pointer<Void> userData,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _MemoriesNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Int32 limit,
  Pointer<Utf8> query,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _MemoriesDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  int limit,
  Pointer<Utf8> query,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _ArchiveNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Int32 keepRecent,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _ArchiveDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  int keepRecent,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _SaveContextNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _SaveContextDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _ClearContextNative = Int32 Function(
  Pointer<Void> engine,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _ClearContextDart = int Function(
  Pointer<Void> engine,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _DeleteMemoryNative = Int32 Function(
  Pointer<Void> engine,
  Pointer<Utf8> memoryId,
);
typedef _DeleteMemoryDart = int Function(
  Pointer<Void> engine,
  Pointer<Utf8> memoryId,
);

typedef _CancelNative = Void Function(
  Pointer<Void> engine,
  Pointer<Utf8> responseId,
);
typedef _CancelDart = void Function(
  Pointer<Void> engine,
  Pointer<Utf8> responseId,
);

typedef _HistoryNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Int32 limit,
  Int64 beforeSeq,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _HistoryDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  int limit,
  int beforeSeq,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _ContextLogNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Int32 limit,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _ContextLogDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  int limit,
  Pointer<Pointer<Utf8>> errorJson,
);

typedef _FreeNative = Void Function(Pointer<Utf8> value);
typedef _FreeDart = void Function(Pointer<Utf8> value);

class _PendingCall {
  _PendingCall(this.controller);

  final StreamController<ChatStreamEvent> controller;
  String? responseId;
  bool closed = false;
}

/// Full mode: direct Dart FFI into the embedded C++ core.
///
/// The C++ library owns SQLite and the provider; no socket or localhost server
/// is involved. The native callbacks are marshalled to the main isolate by
/// [NativeCallable.listener].
class FfiChatApi implements ChatBackend {
  FfiChatApi({
    String? libraryPath,
    required Map<String, Object?> config,
  })  : _provider = (config['provider'] ?? 'mock').toString(),
        _model = (config['model'] ?? 'deepseek-chat').toString(),
        _library = _openLibrary(libraryPath) {
    _create = _library.lookupFunction<_CreateNative, _CreateDart>(
      'chatvv_create',
    );
    _destroy = _library.lookupFunction<_DestroyNative, _DestroyDart>(
      'chatvv_destroy',
    );
    _sendEx = _library.lookupFunction<_SendExNative, _SendExDart>(
      'chatvv_send_ex',
    );
    _cancel = _library.lookupFunction<_CancelNative, _CancelDart>(
      'chatvv_cancel',
    );
    _history = _library.lookupFunction<_HistoryNative, _HistoryDart>(
      'chatvv_history',
    );
    _memories = _library.lookupFunction<_MemoriesNative, _MemoriesDart>(
      'chatvv_memories',
    );
    _archive = _library.lookupFunction<_ArchiveNative, _ArchiveDart>(
      'chatvv_archive',
    );
    _deleteMemory = _library.lookupFunction<
        _DeleteMemoryNative, _DeleteMemoryDart>('chatvv_delete_memory');
    _saveContext = _library.lookupFunction<
        _SaveContextNative, _SaveContextDart>('chatvv_save_context');
    _clearContext = _library.lookupFunction<
        _ClearContextNative, _ClearContextDart>('chatvv_clear_context');
    // Developer-mode context log was added later: keep working with older
    // native builds that don't export the symbol.
    try {
      _contextLog = _library.lookupFunction<_ContextLogNative, _ContextLogDart>(
        'chatvv_context_log',
      );
    } on ArgumentError {
      _contextLog = null;
    }
    _free = _library.lookupFunction<_FreeNative, _FreeDart>('chatvv_free');

    _callable = NativeCallable<_EventCallbackNative>.listener(_onNativeEvent);

    final configPtr = jsonEncode(config).toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      _engine = _create(configPtr, errorPtr);
      if (_engine.address == 0) {
        throw ChatApiException(_takeError(errorPtr));
      }
    } finally {
      calloc.free(configPtr);
      calloc.free(errorPtr);
    }
  }

  final String _provider;
  final String _model;
  final DynamicLibrary _library;
  late final _CreateDart _create;
  late final _DestroyDart _destroy;
  late final _SendExDart _sendEx;
  late final _CancelDart _cancel;
  late final _HistoryDart _history;
  late final _MemoriesDart _memories;
  late final _ArchiveDart _archive;
  late final _DeleteMemoryDart _deleteMemory;
  late final _SaveContextDart _saveContext;
  late final _ClearContextDart _clearContext;
  _ContextLogDart? _contextLog;
  late final _FreeDart _free;
  late final NativeCallable<_EventCallbackNative> _callable;

  Pointer<Void> _engine = nullptr;
  bool _disposed = false;
  int _nextToken = 1;
  final Map<int, _PendingCall> _pending = {};

  @override
  String get modeLabel => 'Full · ${_provider == 'mock' ? 'mock' : 'native'}';

  @override
  String get endpointLabel => _model;

  static DynamicLibrary _openLibrary(String? explicitPath) {
    final configured = explicitPath ??
        const String.fromEnvironment('CHATVV_FFI_LIB', defaultValue: '');
    if (configured.isNotEmpty) return DynamicLibrary.open(configured);
    if (Platform.isAndroid) return DynamicLibrary.open('libchatvv_ffi.so');

    final executable = File(Platform.resolvedExecutable);
    final bundled = switch (Platform.operatingSystem) {
      'linux' => '${executable.parent.path}/lib/libchatvv_ffi.so',
      'macos' =>
        '${executable.parent.parent.path}/Frameworks/libchatvv_ffi.dylib',
      'windows' => '${executable.parent.path}/chatvv_ffi.dll',
      _ => null,
    };
    if (bundled != null && File(bundled).existsSync()) {
      return DynamicLibrary.open(bundled);
    }
    if (Platform.isLinux) return DynamicLibrary.open('libchatvv_ffi.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libchatvv_ffi.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('chatvv_ffi.dll');
    throw const ChatApiException('当前平台不支持 FFI 后端');
  }

  @override
  Stream<ChatStreamEvent> send(
    String text, {
    List<PromptInjection> injections = const [],
  }) {
    if (_disposed) {
      return Stream.error(const ChatApiException('FFI engine 已释放'));
    }

    final token = _nextToken++;
    final controller = StreamController<ChatStreamEvent>();
    final pending = _PendingCall(controller);
    _pending[token] = pending;

    final textPtr = text.toNativeUtf8();
    final Pointer<Utf8> injectionsPtr = injections.isEmpty
        ? nullptr
        : jsonEncode(
            injections
                .where((item) => item.enabled && item.content.trim().isNotEmpty)
                .map((item) => item.toApiJson())
                .toList(),
          ).toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    final idPtr = _sendEx(
      _engine,
      textPtr,
      injectionsPtr,
      _callable.nativeFunction,
      Pointer<Void>.fromAddress(token),
      errorPtr,
    );
    calloc.free(textPtr);
    if (injectionsPtr.address != 0) calloc.free(injectionsPtr);

    if (idPtr.address == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      _pending.remove(token);
      return Stream.error(ChatApiException(message));
    }

    pending.responseId = idPtr.toDartString();
    _free(idPtr);
    calloc.free(errorPtr);

    controller.onCancel = () {
      final id = pending.responseId;
      if (id != null && !pending.closed) {
        unawaited(cancel(id));
      }
      _pending.remove(token);
    };
    return controller.stream;
  }

  void _onNativeEvent(
    Pointer<Void> userData,
    int eventType,
    Pointer<Utf8> eventJson,
  ) {
    final token = userData.address;
    final pending = _pending[token];
    if (pending == null || pending.closed) return;

    final raw = eventJson.toDartString();
    _free(eventJson);
    final payload = _decode(raw);
    switch (eventType) {
      case 1: // started
        final id = _responseId(payload);
        if (id != null) pending.responseId = id;
        pending.controller.add(ChatStreamEvent.started(id ?? ''));
      case 2: // delta
        final delta = payload?['delta'] ?? payload?['text'];
        if (delta != null) {
          pending.controller.add(ChatStreamEvent.delta(delta.toString()));
        }
      case 4: // completed
        pending.closed = true;
        pending.controller.add(const ChatStreamEvent.completed());
        unawaited(pending.controller.close());
        _pending.remove(token);
      case 5: // failed
        pending.closed = true;
        pending.controller.add(
          ChatStreamEvent.failed(_errorText(payload)),
        );
        unawaited(pending.controller.close());
        _pending.remove(token);
      default:
        // context/tool events are not part of the current UI event model yet.
        break;
    }
  }

  static Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String? _responseId(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final response = payload['response'];
    if (response is Map && response['id'] != null) {
      return response['id'].toString();
    }
    return payload['id']?.toString();
  }

  static String _errorText(Map<String, dynamic>? payload) {
    if (payload == null) return '本轮生成失败';
    final response = payload['response'];
    if (response is Map) {
      final error = response['error'];
      if (error is Map && error['message'] != null) {
        return _short(error['message'].toString());
      }
    }
    final error = payload['error'];
    if (error is Map && error['message'] != null) {
      return _short(error['message'].toString());
    }
    if (payload['message'] != null) {
      return _short(payload['message'].toString());
    }
    // Providers often wrap the real message inside a serialized error body.
    final raw = jsonEncode(payload);
    final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(raw);
    if (match != null) return _short(match.group(1)!);
    return _short(raw);
  }

  static String _short(String value) {
    final oneLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 220) return oneLine;
    return '${oneLine.substring(0, 220)}…';
  }

  @override
  Future<List<ChatMessage>> history({int limit = 30}) async {
    if (_disposed) return const [];
    final errorPtr = calloc<Pointer<Utf8>>();
    final resultPtr = _history(_engine, limit, 0, errorPtr);
    if (resultPtr.address == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      throw ChatApiException(message);
    }
    final raw = resultPtr.toDartString();
    _free(resultPtr);
    calloc.free(errorPtr);

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    if (data is! List) return const [];
    final messages = data
        .whereType<Map>()
        .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  @override
  Future<void> cancel(String responseId) async {
    if (_disposed || responseId.isEmpty) return;
    final idPtr = responseId.toNativeUtf8();
    _cancel(_engine, idPtr);
    calloc.free(idPtr);
  }

  String _takeError(Pointer<Pointer<Utf8>> errorPtr) {
    final ptr = errorPtr.value;
    if (ptr.address == 0) return 'FFI 调用失败';
    final value = ptr.toDartString();
    _free(ptr);
    return value;
  }

  @override
  Future<List<MemoryEntry>> memories({int limit = 50, String query = ''}) async {
    if (_disposed) return const [];
    final queryPtr = query.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    final resultPtr = _memories(_engine, limit, queryPtr, errorPtr);
    calloc.free(queryPtr);
    if (resultPtr.address == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      throw ChatApiException(message);
    }
    final raw = resultPtr.toDartString();
    _free(resultPtr);
    calloc.free(errorPtr);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => MemoryEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<MemoryArchiveResult> archive({int keepRecent = 20}) async {
    if (_disposed) {
      throw const ChatApiException('FFI engine 已释放');
    }
    final errorPtr = calloc<Pointer<Utf8>>();
    final resultPtr = _archive(_engine, keepRecent, errorPtr);
    if (resultPtr.address == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      throw ChatApiException(message);
    }
    final raw = resultPtr.toDartString();
    _free(resultPtr);
    calloc.free(errorPtr);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const ChatApiException('归档响应格式错误');
    }
    return MemoryArchiveResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> deleteMemory(String id) async {
    if (_disposed) return;
    final idPtr = id.toNativeUtf8();
    _deleteMemory(_engine, idPtr);
    calloc.free(idPtr);
  }


  @override
  Future<Map<String, dynamic>> contextLog({int limit = 400}) async {
    final lookup = _contextLog;
    if (lookup == null) {
      return {
        'unsupported': true,
        'reason': '当前原生库不包含 chatvv_context_log（请更新构建）',
      };
    }
    if (_disposed || _engine.address == 0) {
      throw const ChatApiException('FFI engine 已释放');
    }
    final errorPtr = calloc<Pointer<Utf8>>();
    try {
      final resultPtr = lookup(_engine, limit, errorPtr);
      if (resultPtr == nullptr) {
        throw ChatApiException(_takeError(errorPtr));
      }
      try {
        final decoded = jsonDecode(resultPtr.toDartString());
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
        throw const ChatApiException('context_log 返回了非对象 JSON');
      } finally {
        _free(resultPtr);
      }
    } finally {
      if (errorPtr.value != nullptr) {
        _free(errorPtr.value);
      }
      calloc.free(errorPtr);
    }
  }

  @override
  Future<void> clearAllMemories() => clearAllMemoriesPaginated(this);
  @override
  Future<MemoryArchiveResult> saveContext() async {
    if (_disposed) {
      throw const ChatApiException('FFI engine 已释放');
    }
    final errorPtr = calloc<Pointer<Utf8>>();
    final resultPtr = _saveContext(_engine, errorPtr);
    if (resultPtr.address == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      throw ChatApiException(message);
    }
    final raw = resultPtr.toDartString();
    _free(resultPtr);
    calloc.free(errorPtr);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const ChatApiException('保存上下文响应格式错误');
    }
    return MemoryArchiveResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> clearContext() async {
    if (_disposed) return;
    final errorPtr = calloc<Pointer<Utf8>>();
    final ok = _clearContext(_engine, errorPtr);
    if (ok == 0) {
      final message = _takeError(errorPtr);
      calloc.free(errorPtr);
      throw ChatApiException(message);
    }
    calloc.free(errorPtr);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final pending in _pending.values) {
      pending.closed = true;
      unawaited(pending.controller.close());
    }
    _pending.clear();
    if (_engine.address != 0) {
      _destroy(_engine);
      _engine = nullptr;
    }
    // NativeCallable.listener posts callbacks through the isolate's event
    // queue. Let queued terminal callbacks drain before closing the metadata.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _callable.close();
  }
}
