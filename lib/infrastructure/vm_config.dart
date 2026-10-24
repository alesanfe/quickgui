import 'dart:io';

class VmConfig {
  final String name;
  final File file;
  String rawContent = '';

  VmConfig({required this.name, required String confPath})
    : file = File(confPath);

  Future<void> load() async {
    if (file.existsSync()) {
      rawContent = await file.readAsString();
    }
  }

  Future<void> save(String updatedContent) async {
    rawContent = updatedContent;
    await file.writeAsString(rawContent);
  }
}

/// Writes a `key="value"` entry to a quickemu .conf file, replacing the
/// existing line or appending a new one.
void writeConfValue(String confPath, String key, String value) {
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

/// Reads a `key="value"` entry from a quickemu .conf file.
String? confValue(String confPath, String key) {
  final file = File(confPath);
  if (!file.existsSync()) return null;
  final re = RegExp('^$key="(.*)"');
  for (final line in file.readAsLinesSync()) {
    final m = re.firstMatch(line);
    if (m != null) return m.group(1);
  }
  return null;
}
