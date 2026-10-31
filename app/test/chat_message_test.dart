import 'package:chatvv/features/chat/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses backend message JSON', () {
    final message = ChatMessage.fromJson({
      'id': '01ABC',
      'role': 'assistant',
      'content': '你好',
      'created_at': 1792907730436,
    });

    expect(message.id, '01ABC');
    expect(message.isUser, isFalse);
    expect(message.content, '你好');
    expect(message.createdAt.millisecondsSinceEpoch, 1792907730436);
  });

  test('stream events carry typed payloads', () {
    const delta = ChatStreamEvent.delta('hi');
    expect(delta.type, ChatStreamEventType.delta);
    expect(delta.delta, 'hi');

    const failed = ChatStreamEvent.failed('boom');
    expect(failed.type, ChatStreamEventType.failed);
    expect(failed.error, 'boom');
  });
}
