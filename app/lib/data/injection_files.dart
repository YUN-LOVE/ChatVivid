import 'dart:io';

import 'prompt_injection.dart';

/// Materializes the managed injections as the Markdown + frontmatter files the
/// C++ InjectionStore already understands. This keeps Full mode file-native
/// and the client/API mode JSON-native without duplicating prompt logic.
Future<void> syncInjectionFiles(
  Directory directory,
  List<PromptInjection> injections,
) async {
  await directory.create(recursive: true);
  await for (final entity in directory.list()) {
    if (entity is File && entity.path.endsWith('.md')) {
      await entity.delete();
    }
  }

  var index = 0;
  for (final injection in injections) {
    if (!injection.enabled || injection.content.trim().isEmpty) continue;
    final file = File(
      '${directory.path}/${index.toString().padLeft(2, '0')}-'
      '${_safeName(injection.id)}.md',
    );
    index++;
    final description = injection.description
        .replaceAll('\n', ' ')
        .replaceAll('"', "'");
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('position: ${injection.position}')
      ..writeln('mode: ${injection.mode}')
      ..writeln('trust: ${injection.trust}')
      ..writeln('priority: ${injection.priority}')
      ..writeln('depth: ${injection.depth}')
      ..writeln('enabled: true')
      ..writeln('description: "$description"')
      ..writeln('---')
      ..writeln(injection.content);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(buffer.toString(), flush: true);
    await tmp.rename(file.path);
  }
}

String _safeName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return sanitized.isEmpty ? 'injection' : sanitized;
}
