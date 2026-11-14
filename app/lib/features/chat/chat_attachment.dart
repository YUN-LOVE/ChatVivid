import 'dart:typed_data';

/// One file attached to the composer.
///
/// Text attachments carry their decoded [content] so it can be injected into the
/// prompt. Image attachments (sticker/emoji MCP, clipboard paste) carry
/// [imageBytes]/[mimeType] and are rendered as thumbnails in the composer; the
/// actual vision transport is added when the sticker MCP lands.
class ChatAttachment {
  ChatAttachment({
    required this.name,
    required this.content,
    required this.bytes,
    this.imageBytes,
    this.mimeType,
  });

  final String name;
  final String content;
  final int bytes;
  final Uint8List? imageBytes;
  final String? mimeType;

  bool get isImage => imageBytes != null && imageBytes!.isNotEmpty;
}
