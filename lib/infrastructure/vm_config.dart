import 'dart:io';

import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';

/// File-backed [VmConfigStore]: `.conf` files are `key="value"` files.
class VmConfigFileStore implements VmConfigStore {
  const VmConfigFileStore();

  @override
  String? read(String confPath, String key) {
    final file = File(confPath);
    if (!file.existsSync()) return null;
    final re = RegExp('^$key="(.*)"');
    for (final line in file.readAsLinesSync()) {
      final m = re.firstMatch(line);
      if (m != null) return m.group(1);
    }
    return null;
  }

  @override
  void write(String confPath, String key, String value) {
    final file = File(confPath);
    final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    final re = RegExp('^$key=');
    var replaced = false;
    for (var i = 0; i < lines.length; i++) {
      if (re.hasMatch(lines[i])) {
        lines[i] = '$key="$value"';
        replaced = true;
        break;
      }
    }
    if (!replaced) lines.add('$key="$value"');
    file.writeAsStringSync('${lines.join('\n')}\n');
  }

  @override
  Future<String> loadRaw(String confPath) async {
    final file = File(confPath);
    return file.existsSync() ? await file.readAsString() : '';
  }

  @override
  Future<void> saveRaw(String confPath, String content) async {
    await File(confPath).writeAsString(content);
  }
}
