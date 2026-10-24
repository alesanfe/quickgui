import 'dart:io';

var gIsSnap = Platform.environment['SNAP']?.isNotEmpty ?? false;
const String prefWorkingDirectory = 'workingDirectory';
const String prefThemeMode = 'themeMode';
const String prefCurrentLocale = 'currentLocale';
const String prefNewlyInstalledVms = 'newlyInstalledVms';

Future<String> fetchQuickemuVersion() async {
  // Get the version of quickemu
  var result = await Process.run('quickemu', ['--version']);

  // If successful return the trimmed version
  if (result.exitCode == 0) {
    return result.stdout.trim();
  } else {
    return '';
  }
}

/// Returns true if a temporary file can be created in [path].
bool isWritableDirectory(String path) {
  try {
    final file = File(
      '$path${Platform.pathSeparator}.quickgui_write_test',
    );
    file.createSync();
    file.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// A sensible writable fallback for the working directory. The app can be
/// started from a read-only location (e.g. an AppImage mount point).
String fallbackWorkingDirectory() {
  return Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
}

/// Host CPU flags, lower-cased and normalised (e.g. "SSE4.2" -> "sse4_2").
Future<Set<String>> hostCpuFlags() async {
  final flags = <String>{};
  try {
    if (Platform.isMacOS) {
      for (final key in [
        'machdep.cpu.features',
        'machdep.cpu.leaf7_features',
      ]) {
        final result = await Process.run('sysctl', ['-n', key]);
        flags.addAll(
          '${result.stdout}'
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .map((f) => f.replaceAll('.', '_')),
        );
      }
    } else {
      flags.addAll(
        (await File('/proc/cpuinfo').readAsString())
            .toLowerCase()
            .split(RegExp(r'\s+')),
      );
    }
  } catch (_) {
    // Could not determine CPU flags; leave the set empty.
  }
  return flags;
}

/// CPU feature requirements for each macOS release, mirroring quickemu.
/// Returns the missing flags, or an empty list if the host can run it.
Future<List<String>> missingMacosRequirements(String release) async {
  const requirements = {
    'ventura': ['sse4_2', 'avx2'],
    'sonoma': ['sse4_2', 'avx2'],
    'sequoia': ['sse4_2', 'avx2'],
    'tahoe': ['sse4_2', 'avx2'],
    'catalina': ['sse4_2'],
    'big-sur': ['sse4_2'],
    'monterey': ['sse4_2'],
  };
  final flags = await hostCpuFlags();
  if (flags.isEmpty) {
    // CPU flags could not be detected; do not block the user.
    return const [];
  }
  return (requirements[release] ?? const ['sse4_1'])
      .where((flag) => !flags.contains(flag))
      .toList();
}
