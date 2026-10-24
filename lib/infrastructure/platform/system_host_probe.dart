import 'dart:io';

import 'package:quickgui/infrastructure/platform/host_platform.dart';
import 'package:quickgui/infrastructure/process/host_process.dart';
import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';
import 'package:quickgui/infrastructure/app_info/app_version.dart';
import 'package:quickgui/infrastructure/persistence/preferences_repository.dart';

/// Real host probe. Tool and disk checks go through [runHost] so they
/// also work from inside the Flatpak sandbox.
class SystemHostProbe implements HostProbe {
  SystemHostProbe(this._prefs);
  final PreferencesRepository _prefs;

  @override
  Future<bool> hasTool(String name) => commandAvailable(name);

  @override
  Future<bool> hasKvm() async =>
      Platform.isMacOS || File('/dev/kvm').existsSync();

  @override
  Future<String> workingDirectory() async {
    final v = await _prefs.get(prefWorkingDirectory);
    return v is String && v.isNotEmpty ? v : fallbackWorkingDirectory();
  }

  @override
  Future<int?> freeSpaceBytes(String directory) async {
    final r = await runHost('df', ['-Pk', directory]);
    if (r.exitCode != 0) return null;
    final lines = '${r.stdout}'.trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.split(RegExp(r'\s+'));
    final kb = cols.length > 3 ? int.tryParse(cols[3]) : null;
    return kb == null ? null : kb * 1024;
  }

  @override
  String get homeDirectory => Platform.environment['HOME'] ?? '';

  @override
  String get appVersion => AppVersion.packageInfo?.version ?? 'unknown';
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
        (await File(
          '/proc/cpuinfo',
        ).readAsString()).toLowerCase().split(RegExp(r'\s+')),
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
