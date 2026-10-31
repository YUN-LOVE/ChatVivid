import '../features/chat/chat_models.dart';
import 'prompt_injection.dart';
import 'memory_entry.dart';

/// Transport-independent chat contract. Full mode uses FFI; client mode uses
/// HTTP/SSE. UI and controller code must only depend on this interface.
abstract interface class ChatBackend {
  String get modeLabel;

  String get endpointLabel;

  Stream<ChatStreamEvent> send(
    String text, {
    List<PromptInjection> injections = const [],
  });

  Future<List<ChatMessage>> history({int limit = 30});

  Future<void> cancel(String responseId);

  Future<List<MemoryEntry>> memories({int limit = 50, String query = ''});

  Future<MemoryArchiveResult> archive({int keepRecent = 20});

  Future<void> deleteMemory(String id);

  Future<MemoryArchiveResult> saveContext();

  Future<void> clearContext();

  Future<void> dispose();
}
