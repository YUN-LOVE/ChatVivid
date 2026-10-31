import 'dart:io';

import 'package:flutter/services.dart';
import 'app_paths.dart';

import 'chat_backend.dart';
import 'ffi_chat_api.dart';
import 'remote_chat_api.dart';

const String _backendMode =
    String.fromEnvironment('CHATVV_BACKEND', defaultValue: 'remote');

/// Full mode is opt-in until onboarding/settings can persist the choice.
/// Build with `--dart-define=CHATVV_BACKEND=ffi`.
Future<ChatBackend> createChatBackend() async {
  if (_backendMode != 'ffi') return RemoteChatApi();

  final support = await appSupportDirectory();
  await support.create(recursive: true);

  final caFile = File('${support.path}/cacert.pem');
  if (!await caFile.exists()) {
    final data = await rootBundle.load('assets/cacert.pem');
    await caFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  const configuredProvider =
      String.fromEnvironment('CHATVV_LLM_PROVIDER', defaultValue: '');
  const apiKey = String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: '');
  final provider = configuredProvider.isNotEmpty
      ? configuredProvider
      : (apiKey.isEmpty ? 'mock' : 'deepseek');

  return FfiChatApi(
    libraryPath: const String.fromEnvironment(
      'CHATVV_FFI_LIB',
      defaultValue: '',
    ),
    config: {
      'data_dir': support.path,
      'injections_dir': '${support.path}/injections',
      'provider': provider,
      'base_url': const String.fromEnvironment(
        'CHATVV_LLM_BASE_URL',
        defaultValue: 'https://api.deepseek.com',
      ),
      'endpoint': const String.fromEnvironment(
        'CHATVV_LLM_ENDPOINT',
        defaultValue: '/responses',
      ),
      'api_key': apiKey,
      'model': const String.fromEnvironment(
        'CHATVV_LLM_MODEL',
        defaultValue: 'deepseek-chat',
      ),
      'ca_bundle': caFile.path,
    },
  );
}
