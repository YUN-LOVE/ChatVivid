enum ChatStreamEventType { started, delta, completed, failed }

class ChatStreamEvent {
  const ChatStreamEvent({
    required this.type,
    this.responseId,
    this.delta,
    this.error,
  });

  const ChatStreamEvent.started(String id)
      : type = ChatStreamEventType.started,
        responseId = id,
        delta = null,
        error = null;

  const ChatStreamEvent.delta(String text)
      : type = ChatStreamEventType.delta,
        responseId = null,
        delta = text,
        error = null;

  const ChatStreamEvent.completed()
      : type = ChatStreamEventType.completed,
        responseId = null,
        delta = null,
        error = null;

  const ChatStreamEvent.failed(String message)
      : type = ChatStreamEventType.failed,
        responseId = null,
        delta = null,
        error = message;

  final ChatStreamEventType type;
  final String? responseId;
  final String? delta;
  final String? error;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.streaming = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'];
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: createdAt is num
          ? DateTime.fromMillisecondsSinceEpoch(createdAt.toInt())
          : DateTime.now(),
    );
  }

  final String id;
  final String role;
  String content;
  final DateTime createdAt;
  bool streaming;

  bool get isUser => role == 'user';
}

class ChatApiException implements Exception {
  const ChatApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
