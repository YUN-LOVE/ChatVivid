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

  /// Deletes every archived memory (developer mode UI). Implemented by
  /// paginating [memories] + [deleteMemory] so both backends share the logic.
  Future<void> clearAllMemories();

  Future<MemoryArchiveResult> saveContext();

  Future<void> clearContext();

  /// Complete context/tool event log for the developer session log.
  /// Full (embedded core) mode returns the persisted response events (including
  /// chatvv.context.built with the complete instructions/tools/input, memory
  /// queries, injections and tool calls). Remote client mode returns
  /// {"unsupported": true} because the server does not expose it yet.
  Future<Map<String, dynamic>> contextLog({int limit = 400});

  Future<void> dispose();
}


/// Shared implementation of [ChatBackend.clearAllMemories]: delete memories in
/// pages until the store reports none left.
Future<void> clearAllMemoriesPaginated(ChatBackend backend) async {
  for (var batch = 0; batch < 100; batch++) {
    final page = await backend.memories(limit: 200);
    if (page.isEmpty) return;
    for (final memory in page) {
      await backend.deleteMemory(memory.id);
    }
  }
}
