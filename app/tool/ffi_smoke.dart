// ignore_for_file: avoid_print

import 'dart:io';

import 'package:chatvv/data/ffi_chat_api.dart';
import 'package:chatvv/features/chat/chat_models.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('chatvv-ffi-dart-');
  final api = FfiChatApi(
    libraryPath: const String.fromEnvironment('CHATVV_FFI_LIB', defaultValue: 'build/dev/libchatvv_ffi.so'),
    config: {
      'data_dir': dir.path,
      'provider': 'mock',
      'model': 'mock',
    },
  );

  var text = '';
  var completed = false;
  await for (final event in api.send('dart ffi smoke')) {
    switch (event.type) {
      case ChatStreamEventType.completed:
        completed = true;
      case ChatStreamEventType.delta:
        text += event.delta ?? '';
      default:
        break;
    }
  }
  final history = await api.history(limit: 10);
  print('completed=$completed deltas=${text.length} history=${history.length}');
  print(text);
  await api.dispose();
  await dir.delete(recursive: true);
}
