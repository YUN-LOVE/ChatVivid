import 'dart:io';

import 'package:flutter/services.dart';
import 'app_paths.dart';
import 'app_settings.dart';
import 'injection_files.dart';
import 'prompt_injection.dart';

import 'chat_backend.dart';
import 'ffi_chat_api.dart';
import 'remote_chat_api.dart';

Future<ChatBackend> createChatBackend(AppSettings settings) async {
  if (settings.mode == BackendMode.client) {
    final saved = <PromptInjection>[
      if (settings.systemPrompt.trim().isNotEmpty)
        PromptInjection(
          id: 'system-prompt',
          name: 'system-prompt',
          position: 'system',
          mode: 'replace',
          trust: 'instruction',
          content: settings.systemPrompt.trim(),
        ),
      ...settings.injections,
    ];
    return RemoteChatApi(
      baseUrl: settings.clientBaseUrl,
      apiKey: settings.clientToken,
      savedInjections: saved,
    );
  }

  final support = await appSupportDirectory();
  await support.create(recursive: true);

  final injectionsDir = Directory('${support.path}/injections');
  await syncInjectionFiles(injectionsDir, settings.injections);

  final caFile = File('${support.path}/cacert.pem');
  if (!await caFile.exists()) {
    final data = await rootBundle.load('assets/cacert.pem');
    await caFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

  final provider = settings.apiKey.isEmpty ? 'mock' : settings.provider;

  return FfiChatApi(
    libraryPath: const String.fromEnvironment(
      'CHATVV_FFI_LIB',
      defaultValue: '',
    ),
    config: {
      'data_dir': support.path,
      'injections_dir': injectionsDir.path,
      'provider': provider,
      'base_url': settings.fullBaseUrl,
      'endpoint': settings.fullEndpoint,
      'api_key': settings.apiKey,
      'model': settings.model,
      'ca_bundle': caFile.path,
      'system_prompt': settings.systemPrompt,
    },
  );
}
