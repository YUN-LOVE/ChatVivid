import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/chat_backend.dart';
import '../../data/prompt_injection.dart';
import 'chat_models.dart';

class ChatController extends ChangeNotifier {
  ChatController({required this.api});

  final ChatBackend api;
  final List<ChatMessage> messages = [];

  bool busy = false;
  bool online = false;
  String? error;
  String? activeResponseId;

  StreamSubscription<ChatStreamEvent>? _subscription;
  Timer? _notifyTimer;
  bool _disposed = false;

  String get apiBase => api.endpointLabel;

  String get backendLabel => '${api.modeLabel} · ${api.endpointLabel}';

  Future<void> initialize() async {
    try {
      final history = await api.history();
      online = true;
      messages
        ..clear()
        ..addAll(history);
      if (messages.isEmpty) _addIntro();
    } on ChatApiException catch (exception) {
      online = false;
      error = exception.message;
      if (messages.isEmpty) _addIntro();
    } catch (exception) {
      online = false;
      error = exception.toString();
      if (messages.isEmpty) _addIntro();
    }
    _notifyNow();
  }

  Future<void> send(
    String raw, {
    List<PromptInjection> injections = const [],
  }) async {
    final text = raw.trim();
    if (text.isEmpty || busy) return;

    messages.add(
      ChatMessage(
        id: 'local-user-${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        content: text,
        createdAt: DateTime.now(),
      ),
    );
    final reply = ChatMessage(
      id: 'local-reply-${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      streaming: true,
    );
    messages.add(reply);

    busy = true;
    error = null;
    activeResponseId = null;
    _notifyNow();

    _subscription = api.send(text, injections: injections).listen(
      (event) {
        switch (event.type) {
          case ChatStreamEventType.started:
            activeResponseId = event.responseId;
            online = true;
            break;
          case ChatStreamEventType.delta:
            online = true;
            reply.content += event.delta ?? '';
            _scheduleNotify();
            break;
          case ChatStreamEventType.completed:
            reply.streaming = false;
            busy = false;
            online = true;
            _notifyNow();
            break;
          case ChatStreamEventType.failed:
            reply.content = event.error ?? '本轮生成失败';
            reply.streaming = false;
            busy = false;
            error = event.error;
            _notifyNow();
            break;
        }
      },
      onError: (Object exception) {
        online = false;
        error = exception.toString();
        if (reply.content.isEmpty) {
          reply.content = '……连接不上后端。\n确认 chatvvd 已启动；Android 真机先 adb reverse tcp:8080 tcp:8080。';
        }
        reply.streaming = false;
        busy = false;
        _notifyNow();
      },
      onDone: () {
        reply.streaming = false;
        busy = false;
        _notifyNow();
      },
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    final responseId = activeResponseId;
    await _subscription?.cancel();
    _subscription = null;
    if (responseId != null) {
      await api.cancel(responseId);
    }
    for (final message in messages) {
      message.streaming = false;
    }
    busy = false;
    activeResponseId = null;
    _notifyNow();
  }

  Future<void> reconnect() async {
    error = null;
    online = false;
    _notifyNow();
    await initialize();
  }

  void _addIntro() {
    messages.add(
      ChatMessage(
        id: 'intro',
        role: 'assistant',
        content: 'zako！',
        createdAt: DateTime.now(),
      ),
    );
  }

  void _scheduleNotify() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(Duration(milliseconds: 33), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _subscription?.cancel();
    unawaited(api.dispose());
    super.dispose();
  }
}
