import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _paths = MethodChannel('chatvv/paths');

/// Persistent app-private directory for the embedded core (DB, logs, CA).
/// Keeping this tiny avoids pulling path_provider's jni/NDK dependency on
/// Android; iOS can add its own branch later.
Future<Directory> appSupportDirectory() async {
  final Directory base;
  if (Platform.isAndroid) {
    final path = await _paths.invokeMethod<String>('supportDir');
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Android supportDir is unavailable');
    }
    base = Directory('$path/chatvv');
  } else if (Platform.isLinux) {
    final env = Platform.environment;
    final root = env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share';
    base = Directory('$root/chatvv');
  } else if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw const FileSystemException('APPDATA is unavailable');
    }
    base = Directory('$appData\\chatvv');
  } else if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    base = Directory('$home/Library/Application Support/chatvv');
  } else {
    throw const FileSystemException('Unsupported platform for local storage');
  }
  await base.create(recursive: true);
  return base;
}
