import 'dart:io';

import 'package:flutter/services.dart';
import 'app_paths.dart';
import 'app_settings.dart';

import 'chat_backend.dart';
import 'ffi_chat_api.dart';
import 'remote_chat_api.dart';

Future<ChatBackend> createChatBackend(AppSettings settings) async {
  if (settings.mode == BackendMode.client) {
    return RemoteChatApi(baseUrl: settings.clientBaseUrl);
  }

  final support = await appSupportDirectory();
  await support.create(recursive: true);

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
      'injections_dir': '${support.path}/injections',
      'provider': provider,
      'base_url': settings.fullBaseUrl,
      'endpoint': settings.fullEndpoint,
      'api_key': settings.apiKey,
      'model': settings.model,
      'ca_bundle': caFile.path,
    },
  );
}
