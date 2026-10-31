import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'app_settings.dart';

class SettingsStore {
  SettingsStore._(this._file);

  final File _file;

  static Future<SettingsStore> open() async {
    final dir = await appSupportDirectory();
    return SettingsStore._(File('${dir.path}/settings.json'));
  }

  Future<AppSettings> load() async {
    try {
      if (!await _file.exists()) return AppSettings.defaults();
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return AppSettings.defaults();
      return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }

  String get path => _file.path;
}
