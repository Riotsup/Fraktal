library;

import 'dart:convert';
import 'dart:io';
import '../domain/connection_settings.dart';
import 'connection_settings_store_base.dart';

ConnectionSettingsStore createConnectionSettingsStore() =>
    _FileConnectionSettingsStore();

class _FileConnectionSettingsStore implements ConnectionSettingsStore {
  File get _file {
    final env = Platform.environment;
    final String base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? env['LOCALAPPDATA'] ?? Directory.current.path;
    } else if (Platform.isMacOS) {
      base =
          '${env['HOME'] ?? Directory.current.path}/Library/Application Support';
    } else {
      base = env['XDG_CONFIG_HOME'] ??
          '${env['HOME'] ?? Directory.current.path}/.config';
    }
    return File(
        '$base${Platform.pathSeparator}Fraktal${Platform.pathSeparator}HMI${Platform.pathSeparator}connection.json');
  }

  @override
  Future<ConnectionSettings?> load() async {
    try {
      final file = _file;
      if (!await file.exists()) return null;
      return ConnectionSettings.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null; // corrupt/unreadable settings deliberately return to the wizard
    }
  }

  @override
  Future<void> save(ConnectionSettings settings) async {
    final file = _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) await file.delete();
  }
}
