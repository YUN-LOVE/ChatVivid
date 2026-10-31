import '../features/chat/chat_models.dart';

/// Transport-independent chat contract. Full mode uses FFI; client mode uses
/// HTTP/SSE. UI and controller code must only depend on this interface.
abstract interface class ChatBackend {
  String get endpointLabel;

  Stream<ChatStreamEvent> send(String text);

  Future<List<ChatMessage>> history({int limit = 30});

  Future<void> cancel(String responseId);

  Future<void> dispose();
}
