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
  final skills = settings.skills.where((skill) => skill.enabled).toList();
  final skillPrompt = skills
      .map((skill) =>
          '## Skill: ${skill.name}\n${skill.description}\n${skill.instructions}')
      .join('\n\n');
  final combinedSystem = [
    if (settings.systemPrompt.trim().isNotEmpty) settings.systemPrompt.trim(),
    if (skillPrompt.isNotEmpty) '[技能]\n$skillPrompt',
    if (settings.agentEnabled)
      '[Agent] 当前处于 Agent 模式。优先使用已接入的工具；没有工具时明确说明。',
  ].join('\n\n');

  if (settings.mode == BackendMode.client) {
    final saved = <PromptInjection>[
      if (combinedSystem.isNotEmpty)
        PromptInjection(
          id: 'system-prompt',
          name: 'system-prompt',
          position: 'system',
          mode: 'replace',
          trust: 'instruction',
          content: combinedSystem,
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

  final modelFile = File(
    '${support.path}/models/bge-small-zh-v1.5-q8_0.gguf',
  );
  if (!await modelFile.exists()) {
    await modelFile.parent.create(recursive: true);
    final data = await rootBundle.load(
      'assets/models/bge-small-zh-v1.5-q8_0.gguf',
    );
    await modelFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
  }

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
      'system_prompt': combinedSystem,
      'embedding_model': modelFile.path,
      'embedding_threads': 2,
    },
  );
}
