class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.content,
    required this.bytes,
  });

  final String name;
  final String content;
  final int bytes;
}
