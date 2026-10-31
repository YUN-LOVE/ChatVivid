import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../features/chat/chat_models.dart';
import 'chat_backend.dart';
import 'memory_entry.dart';
import 'prompt_injection.dart';

const String chatApiBase = String.fromEnvironment(
  'CHATVV_API',
  defaultValue: 'http://127.0.0.1:8080',
);

class RemoteChatApi implements ChatBackend {
  RemoteChatApi({
    String baseUrl = chatApiBase,
    String apiKey = '',
    this.savedInjections = const [],
  })  : baseUrl = _normalize(baseUrl),
        _dio = Dio(
          BaseOptions(
            baseUrl: _normalize(baseUrl),
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 90),
            sendTimeout: const Duration(seconds: 15),
            headers: apiKey.isEmpty
                ? null
                : {'Authorization': 'Bearer $apiKey'},
          ),
        );

  final String baseUrl;
  final List<PromptInjection> savedInjections;
  final Dio _dio;

  @override
  String get modeLabel => 'Only client';

  @override
  String get endpointLabel => baseUrl;

  static String _normalize(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  @override
  Future<List<ChatMessage>> history({int limit = 30}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/v1/messages',
        queryParameters: {'limit': limit},
      );
      final data = response.data;
      if (data is! Map) return const [];
      final raw = data['data'];
      if (raw is! List) return const [];
      final messages = raw
          .whereType<Map>()
          .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return messages;
    } on DioException catch (error) {
      throw ChatApiException(_friendlyError(error));
    }
  }

  @override
  Stream<ChatStreamEvent> send(
    String text, {
    List<PromptInjection> injections = const [],
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/v1/turns',
        data: {
          'message': text,
          'stream': true,
          'injections': [
            ...savedInjections,
            ...injections,
          ]
              .where((item) => item.enabled && item.content.trim().isNotEmpty)
              .map((item) => item.toApiJson())
              .toList(),
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
    } on DioException catch (error) {
      throw ChatApiException(_friendlyError(error));
    }

    final body = response.data;
    if (body == null) {
      throw const ChatApiException('后端没有返回 SSE 流');
    }

    await for (final frame in _sseFrames(body.stream)) {
      final payload = _decode(frame.data);
      if (payload == null) continue;
      final type = (payload['type'] ?? frame.event ?? '').toString();

      switch (type) {
        case 'response.created':
          final id = _responseId(payload);
          if (id != null) yield ChatStreamEvent.started(id);
          break;
        case 'response.output_text.delta':
          final delta = payload['delta'] ?? payload['text'];
          if (delta != null) yield ChatStreamEvent.delta(delta.toString());
          break;
        case 'response.completed':
          yield const ChatStreamEvent.completed();
          break;
        case 'response.failed':
        case 'error':
          yield ChatStreamEvent.failed(_errorText(payload));
          break;
      }
    }
  }

  @override
  Future<void> cancel(String responseId) async {
    if (responseId.isEmpty) return;
    try {
      await _dio.post<dynamic>('/v1/responses/$responseId/cancel');
    } on DioException {
      // Cancelling a already-finished stream is harmless.
    }
  }

  @override
  Future<List<MemoryEntry>> memories({int limit = 50, String query = ''}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/v1/memories',
        queryParameters: {'limit': limit, 'query': query},
      );
      final data = response.data;
      if (data is! Map) return const [];
      final raw = data['data'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => MemoryEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (error) {
      throw ChatApiException(_friendlyError(error));
    }
  }

  @override
  Future<MemoryArchiveResult> archive({int keepRecent = 20}) async {
    try {
      final response = await _dio.post<dynamic>(
        '/v1/memories/archive',
        data: {'keep_recent': keepRecent},
      );
      final data = response.data;
      if (data is! Map) {
        throw const ChatApiException('归档响应格式错误');
      }
      return MemoryArchiveResult.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (error) {
      throw ChatApiException(_friendlyError(error));
    }
  }

  @override
  Future<void> deleteMemory(String id) async {
    try {
      await _dio.delete<dynamic>('/v1/memories/${Uri.encodeComponent(id)}');
    } on DioException catch (error) {
      throw ChatApiException(_friendlyError(error));
    }
  }

  @override
  Future<void> dispose() async => _dio.close(force: true);

  static String? _responseId(Map<String, dynamic> payload) {
    final response = payload['response'];
    if (response is Map) {
      final id = response['id'];
      if (id != null) return id.toString();
    }
    final id = payload['id'];
    return id?.toString();
  }

  static String _errorText(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is Map) {
      final message = error['message'];
      if (message != null) return message.toString();
    }
    if (error != null) return error.toString();
    return '本轮生成失败';
  }

  static Map<String, dynamic>? _decode(String data) {
    if (data.trim().isEmpty || data.trim() == '[DONE]') return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String _friendlyError(DioException error) {
    final response = error.response;
    if (response != null) {
      final data = response.data;
      if (data is Map) {
        final err = data['error'];
        if (err is Map && err['message'] != null) {
          return 'HTTP ${response.statusCode}: ${err['message']}';
        }
      }
      return 'HTTP ${response.statusCode}；检查后端地址/API Key';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return '连接不上后端（${error.requestOptions.baseUrl}）';
    }
    return error.message ?? '请求失败';
  }

  static Stream<_SseFrame> _sseFrames(Stream<Uint8List> stream) async* {
    var buffer = '';
    await for (final chunk in stream.cast<List<int>>().transform(utf8.decoder)) {
      buffer += chunk;
      buffer = buffer.replaceAll('\r\n', '\n');
      while (true) {
        final boundary = buffer.indexOf('\n\n');
        if (boundary < 0) break;
        final block = buffer.substring(0, boundary);
        buffer = buffer.substring(boundary + 2);
        final frame = _parseFrame(block);
        if (frame != null) yield frame;
      }
    }
    final tail = buffer.trim();
    if (tail.isNotEmpty) {
      final frame = _parseFrame(tail);
      if (frame != null) yield frame;
    }
  }

  static _SseFrame? _parseFrame(String block) {
    String? event;
    final data = StringBuffer();
    for (final line in block.split('\n')) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).trimLeft());
      }
    }
    if (data.isEmpty) return null;
    return _SseFrame(event: event, data: data.toString());
  }
}

class _SseFrame {
  const _SseFrame({this.event, required this.data});

  final String? event;
  final String data;
}
