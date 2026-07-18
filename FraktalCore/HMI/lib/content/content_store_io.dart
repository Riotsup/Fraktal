library;

import 'dart:convert';
import 'dart:io';
import 'content_store_base.dart';

ContentStore createContentStore() => _FileContentStore();

class _FileContentStore implements ContentStore {
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
    return File('$base${Platform.pathSeparator}Fraktal${Platform.pathSeparator}'
        'HMI${Platform.pathSeparator}module_content.json');
  }

  @override
  Future<Map<String, Object?>> load() async {
    try {
      if (!await _file.exists()) return {};
      final value = jsonDecode(await _file.readAsString());
      return value is Map ? Map<String, Object?>.from(value) : {};
    } on Object {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, Object?> value) async {
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    if (await _file.exists()) await _file.delete();
    await temp.rename(_file.path);
  }
}
