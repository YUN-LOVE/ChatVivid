import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'chat_attachment.dart';

const MethodChannel _filesChannel = MethodChannel('chatvv/files');

class PickedModelFile {
  const PickedModelFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Native picker for a Rive/Spine model. Returns raw bytes so the caller can
/// copy it into the app support directory and pass an absolute path to Rive.
Future<PickedModelFile?> pickRiveFile() async {
  if (Platform.isAndroid) {
    final raw = await _filesChannel.invokeMethod<Map<dynamic, dynamic>>(
      'pickRiveFile',
    );
    if (raw == null) return null;
    final bytes = raw['bytes'];
    if (bytes is! Uint8List) return null;
    return PickedModelFile(
      name: raw['name']?.toString() ?? 'model.riv',
      bytes: bytes,
    );
  }

  if (Platform.isLinux) {
    final which = await Process.run('sh', ['-c', 'command -v zenity']);
    if (which.exitCode != 0) {
      throw const FileSystemException('缺少 zenity，无法打开文件选择器');
    }
    final result = await Process.run('zenity', [
      '--file-selection',
      '--file-filter=Rive / SVG 模型 | *.riv *.svg',
    ]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return null;
    final file = File(path);
    return PickedModelFile(
      name: file.uri.pathSegments.last,
      bytes: await file.readAsBytes(),
    );
  }

  if (Platform.isWindows) {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = "Rive or SVG|*.riv;*.svg|All files|*.*"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileName
}
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-STA', '-Command', script],
    );
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return null;
    final file = File(path);
    return PickedModelFile(
      name: file.uri.pathSegments.last,
      bytes: await file.readAsBytes(),
    );
  }

  throw const FileSystemException('当前平台暂不支持模型导入');
}
const int _maxFileBytes = 256 * 1024;
const int _maxTotalBytes = 1024 * 1024;

/// Native file selection without a plugin: Android uses ACTION_OPEN_DOCUMENT,
/// Linux uses zenity, Windows uses the WinForms OpenFileDialog.
Future<List<ChatAttachment>> pickTextFiles() async {
  final List<ChatAttachment> picked;
  if (Platform.isAndroid) {
    picked = await _pickAndroid();
  } else if (Platform.isLinux) {
    picked = await _pickLinux();
  } else if (Platform.isWindows) {
    picked = await _pickWindows();
  } else {
    throw const FileSystemException('当前平台暂不支持文件选择');
  }

  final result = <ChatAttachment>[];
  var total = 0;
  for (final file in picked) {
    if (file.bytes > _maxFileBytes) continue;
    if (total + file.bytes > _maxTotalBytes) break;
    result.add(file);
    total += file.bytes;
  }
  return result;
}

Future<List<ChatAttachment>> _pickAndroid() async {
  final raw = await _filesChannel.invokeMethod<List<dynamic>>('pickTextFiles');
  if (raw == null) return [];
  final result = <ChatAttachment>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name']?.toString() ?? 'file';
    final content = item['content']?.toString();
    if (content == null) continue;
    result.add(
      ChatAttachment(name: name, content: content, bytes: utf8.encode(content).length),
    );
  }
  return result;
}

Future<List<ChatAttachment>> _pickLinux() async {
  final which = await Process.run('sh', ['-c', 'command -v zenity']);
  if (which.exitCode != 0) {
    throw const FileSystemException('缺少 zenity，无法打开文件选择器');
  }
  final result = await Process.run('zenity', [
    '--file-selection',
    '--multiple',
    '--separator=\n',
    '--file-filter=文本与代码 | *.txt *.md *.json *.csv *.yaml *.yml *.toml *.xml *.html *.dart *.kt *.java *.c *.h *.cpp *.py *.js *.ts *.sh *.log',
  ]);
  if (result.exitCode != 0) return [];
  final paths = (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return _readPaths(paths);
}

Future<List<ChatAttachment>> _pickWindows() async {
  const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Multiselect = $true
$dialog.Filter = "Text and code|*.txt;*.md;*.json;*.csv;*.yaml;*.yml;*.toml;*.xml;*.html;*.dart;*.kt;*.java;*.c;*.h;*.cpp;*.py;*.js;*.ts;*.sh;*.log|All files|*.*"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  $dialog.FileNames -join "`n"
}
''';
  final result = await Process.run(
    'powershell',
    ['-NoProfile', '-STA', '-Command', script],
  );
  if (result.exitCode != 0) return [];
  final paths = (result.stdout as String)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return _readPaths(paths);
}

Future<List<ChatAttachment>> _readPaths(Iterable<String> paths) async {
  final result = <ChatAttachment>[];
  for (final path in paths) {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxFileBytes) continue;
      result.add(
        ChatAttachment(
          name: file.uri.pathSegments.last,
          content: utf8.decode(bytes),
          bytes: bytes.length,
        ),
      );
    } on FormatException {
      // Skip binary / non-UTF-8 files.
    } on FileSystemException {
      // Skip unreadable files.
    }
  }
  return result;
}
