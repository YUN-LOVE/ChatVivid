import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';

/// Resolves (and, if needed, downloads) the whisper.cpp GGML model used by the
/// voice input feature.
///
/// Models are not bundled in the APK (the smallest usable Chinese model is
/// ~57 MB). The first voice press downloads `ggml-base-q5_1.bin` from the
/// Hugging Face mirror into the app support directory; a custom path can be set
/// in 设置 → 语音与 TTS.
class WhisperModelStore {
  static const String fileName = 'ggml-base-q5_1.bin';

  static const List<String> _downloadUrls = [
    'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/$fileName',
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName',
  ];

  static Future<String> defaultPath() async {
    final support = await appSupportDirectory();
    final dir = Directory('${support.path}/models/whisper');
    await dir.create(recursive: true);
    return '${dir.path}/$fileName';
  }

  /// Returns an existing model path, or throws a readable error explaining that
  /// the user has to download it.
  static Future<String?> resolve({
    String overridePath = '',
    bool downloadIfMissing = false,
    void Function(double progress, String label)? onProgress,
  }) async {
    final candidate = overridePath.trim().isNotEmpty
        ? overridePath.trim()
        : await defaultPath();
    final file = File(candidate);
    if (await file.exists() && await file.length() > 10 * 1024 * 1024) {
      return file.path;
    }
    if (!downloadIfMissing) return null;

    final temp = File('${file.path}.part');
    for (final url in _downloadUrls) {
      try {
        onProgress?.call(0, '正在下载语音识别模型');
        await _download(url, temp, onProgress);
        if (!await temp.exists() || await temp.length() < 10 * 1024 * 1024) {
          continue;
        }
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
        onProgress?.call(1, '语音识别模型已就绪');
        return file.path;
      } catch (error) {
        debugPrint('whisper model download failed ($url): $error');
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
    }
    throw StateError(
      '语音识别模型下载失败。可在 设置 → 语音与 TTS 填写已有 ggml Whisper 模型路径。',
    );
  }

  static Future<void> _download(
    String url,
    File target,
    void Function(double progress, String label)? onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final total = response.contentLength;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress?.call(
              (received / total).clamp(0.0, 1.0),
              '正在下载语音识别模型 ${(received / total * 100).round()}%',
            );
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}
