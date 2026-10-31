import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../features/chat/chat_models.dart';
import 'chat_backend.dart';

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
typedef _SendNative = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Utf8> text,
  Pointer<NativeFunction<_EventCallbackNative>> callback,
  Pointer<Void> userData,
  Pointer<Pointer<Utf8>> errorJson,
);
typedef _SendDart = Pointer<Utf8> Function(
  Pointer<Void> engine,
  Pointer<Utf8> text,
  Pointer<NativeFunction<_EventCallbackNative>> callback,
  Pointer<Void> userData,
  Pointer<Pointer<Utf8>> errorJson,
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
  }) : _library = _openLibrary(libraryPath) {
    _create = _library.lookupFunction<_CreateNative, _CreateDart>(
      'chatvv_create',
    );
    _destroy = _library.lookupFunction<_DestroyNative, _DestroyDart>(
      'chatvv_destroy',
    );
    _send = _library.lookupFunction<_SendNative, _SendDart>('chatvv_send');
    _cancel = _library.lookupFunction<_CancelNative, _CancelDart>(
      'chatvv_cancel',
    );
    _history = _library.lookupFunction<_HistoryNative, _HistoryDart>(
      'chatvv_history',
    );
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

  final DynamicLibrary _library;
  late final _CreateDart _create;
  late final _DestroyDart _destroy;
  late final _SendDart _send;
  late final _CancelDart _cancel;
  late final _HistoryDart _history;
  late final _FreeDart _free;
  late final NativeCallable<_EventCallbackNative> _callable;

  Pointer<Void> _engine = nullptr;
  bool _disposed = false;
  int _nextToken = 1;
  final Map<int, _PendingCall> _pending = {};

  @override
  String get endpointLabel => 'embedded FFI';

  static DynamicLibrary _openLibrary(String? explicitPath) {
    final configured = explicitPath ??
        const String.fromEnvironment('CHATVV_FFI_LIB', defaultValue: '');
    if (configured.isNotEmpty) return DynamicLibrary.open(configured);
    if (Platform.isAndroid) return DynamicLibrary.open('libchatvv_ffi.so');
    if (Platform.isLinux) return DynamicLibrary.open('libchatvv_ffi.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libchatvv_ffi.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('chatvv_ffi.dll');
    throw const ChatApiException('当前平台不支持 FFI 后端');
  }

  @override
  Stream<ChatStreamEvent> send(String text) {
    if (_disposed) {
      return Stream.error(const ChatApiException('FFI engine 已释放'));
    }

    final token = _nextToken++;
    final controller = StreamController<ChatStreamEvent>();
    final pending = _PendingCall(controller);
    _pending[token] = pending;

    final textPtr = text.toNativeUtf8();
    final errorPtr = calloc<Pointer<Utf8>>();
    final idPtr = _send(
      _engine,
      textPtr,
      _callable.nativeFunction,
      Pointer<Void>.fromAddress(token),
      errorPtr,
    );
    calloc.free(textPtr);

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
        return error['message'].toString();
      }
    }
    final error = payload['error'];
    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }
    return error?.toString() ?? '本轮生成失败';
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
