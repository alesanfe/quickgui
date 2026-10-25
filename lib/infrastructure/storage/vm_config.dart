import 'dart:io';

import 'package:quickgui/features/machines/domain/vm_config_value.dart';

import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';

/// Error raised when a `.conf` write cannot be committed atomically.
class VmConfigWriteException implements Exception {
  const VmConfigWriteException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'VmConfigWriteException($path): $message';
}

/// File-backed [VmConfigStore]: `.conf` files are `key="value"` files.
///
/// Writes are atomic: content is staged in a sibling temp file, verified,
/// then renamed over the target after the previous file is backed up to
/// `<name>.conf.bak` (last three writes kept: `.bak`, `.bak.1`, `.bak.2`).
/// Symlinked confs are resolved so the link itself is never replaced.
class VmConfigFileStore implements VmConfigStore {
  const VmConfigFileStore();

  static const _maxBackups = 3;

  @override
  String? read(String confPath, String key) {
    final file = File(confPath);
    if (!file.existsSync()) return null;
    final re = RegExp('^$key="(.*)"');
    for (final line in file.readAsLinesSync()) {
      final m = re.firstMatch(line);
      if (m != null) return decodeVmValue(m.group(1)!);
    }
    return null;
  }

  /// Neutralises characters that would break out of the `key="value"`
  /// line: `"` is escaped (the conf is `source`d by bash in quickemu)
  /// and newlines are stripped so a value can never inject extra keys.
  static String _sanitize(String value) => encodeVmValue(value);

  /// Stable fingerprint of the on-disk content (length + FNV-1a). Callers
  /// record it before editing and compare it at save time to detect an
  /// external modification instead of silently overwriting it.
  static String fingerprint(String confPath) {
    final file = File(confPath);
    if (!file.existsSync()) return 'missing';
    return fingerprintOf(file.readAsStringSync());
  }

  /// Fingerprint for an in-memory conf payload.
  static String fingerprintOf(String content) {
    // 32-bit FNV-1a: deterministic, cheap, and avoids 64-bit literals that
    // lose precision when the linter compiles for JS targets.
    var hash = 0x811c9dc5;
    for (final unit in content.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '${content.length}:${hash.toRadixString(16)}';
  }

  /// Rotates `.bak` files so `.bak` is always the newest copy.
  static void _rotateBackups(String confPath) {
    for (var i = _maxBackups - 1; i >= 0; i--) {
      final current = File(i == 0 ? '$confPath.bak' : '$confPath.bak.$i');
      if (!current.existsSync()) continue;
      final next = File('$confPath.bak.${i + 1}');
      if (i + 1 > _maxBackups - 1) {
        current.deleteSync();
      } else {
        current.renameSync(next.path);
      }
    }
  }

  /// Resolves a symlinked conf to its target so the atomic rename swaps
  /// the real file and the link keeps pointing at it.
  static File _resolve(File file) {
    if (!file.existsSync()) return file;
    if (file.statSync().type != FileSystemEntityType.link) return file;
    return File(file.resolveSymbolicLinksSync());
  }

  /// Atomically replaces [confPath] with [content] (async facade over the
  /// synchronous pipeline — confs are small so sync IO is appropriate and
  /// keeps the save path usable inside `testWidgets` fake-async zones).
  static Future<void> writeAtomic(String confPath, String content) async =>
      unawaitedWrite(confPath, content);

  @override
  void write(String confPath, String key, String value) {
    final file = File(confPath);
    final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    final re = RegExp('^$key=');
    final safe = _sanitize(value);
    var replaced = false;
    for (var i = 0; i < lines.length; i++) {
      if (re.hasMatch(lines[i])) {
        lines[i] = '$key="$safe"';
        replaced = true;
        break;
      }
    }
    if (!replaced) lines.add('$key="$safe"');
    unawaitedWrite(confPath, '${lines.join('\n')}\n');
  }

  @override
  void writeAll(String confPath, Map<String, String> entries) {
    if (entries.isEmpty) return;
    final file = File(confPath);
    final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
    final remaining = Map<String, String>.of(entries);
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^([a-zA-Z_][\w-]*)\s*=').firstMatch(lines[i]);
      final key = m?.group(1);
      if (key != null && remaining.containsKey(key)) {
        lines[i] = '$key="${_sanitize(remaining.remove(key)!)}"';
      }
    }
    for (final e in remaining.entries) {
      lines.add('${e.key}="${_sanitize(e.value)}"');
    }
    unawaitedWrite(confPath, '${lines.join('\n')}\n');
  }

  /// Synchronous wrapper used by [write] and `key="value"` editing paths.
  /// The atomic pipeline is cheap enough to run synchronously: confs are
  /// small and the rename happens on the local filesystem.
  static void unawaitedWrite(String confPath, String content) {
    final file = _resolve(File(confPath));
    final tmp = File('${file.path}.quickgui-tmp');
    try {
      tmp.writeAsStringSync(content, flush: true);
      if (tmp.readAsStringSync() != content) {
        throw VmConfigWriteException(
          file.path,
          'staged content failed verification',
        );
      }
      if (file.existsSync()) {
        _rotateBackups(file.path);
        file.copySync('${file.path}.bak');
      }
      // The rename is atomic: a verified temp can only land complete.
      tmp.renameSync(file.path);
    } finally {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } on FileSystemException {
          // Orphan handled on the next write.
        }
      }
    }
  }

  @override
  Future<String> loadRaw(String confPath) async {
    final file = File(confPath);
    return file.existsSync() ? await file.readAsString() : '';
  }

  @override
  Future<void> saveRaw(String confPath, String content) =>
      writeAtomic(confPath, content);
}
