import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quickgui/infrastructure/process/host_platform.dart'
    as host_platform;
import 'package:quickgui/infrastructure/process/host_process.dart';
import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';
import 'package:quickgui/app/app_version.dart';
import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';
import 'package:quickgui/core/constants/preference_keys.dart';

/// Signature of a host command runner (`exe`, `args`) -> result.
typedef HostRun = Future<ProcessResult> Function(String exe, List<String> args);

/// Real host probe. Tool and disk checks go through [runHost] so they
/// also work from inside the Flatpak sandbox.
class SystemHostProbe implements HostProbe {
  SystemHostProbe(this._prefs, {HostRun? run}) : _run = run ?? runHost;
  final PreferencesRepository _prefs;
  final HostRun _run;

  @override
  Future<bool> hasTool(String name) async =>
      (await _run('which', [name])).exitCode == 0;

  @override
  Future<bool> hasKvm() async =>
      Platform.isMacOS || File('/dev/kvm').existsSync();

  @override
  Future<String> workingDirectory() async {
    final v = await _prefs.get(prefWorkingDirectory);
    return v is String && v.isNotEmpty
        ? v
        : host_platform.fallbackWorkingDirectory();
  }

  @override
  Future<int?> freeSpaceBytes(String directory) async {
    final r = await _run('df', ['-Pk', directory]);
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

  @override
  Future<bool> canWriteToDirectory(String path) async =>
      host_platform.isWritableDirectory(path);

  @override
  String get fallbackWorkingDirectory =>
      host_platform.fallbackWorkingDirectory();

  @override
  Future<String?> terminalEmulator() async {
    // Prefer the distribution's x-terminal-emulator alternative when it
    // resolves to a supported emulator.
    final which = await _run('which', ['x-terminal-emulator']);
    final candidate = '${which.stdout}'.trim();
    if (which.exitCode == 0 && candidate.isNotEmpty) {
      final resolved = await _run('readlink', ['-f', candidate]);
      final target = resolved.exitCode == 0
          ? '${resolved.stdout}'.trim()
          : candidate;
      final name = p.basenameWithoutExtension(target);
      return _supportedTerminalEmulators.contains(name) ? name : null;
    }
    for (final terminal in _supportedTerminalEmulators) {
      if (await hasTool(terminal)) return terminal;
    }
    return null;
  }

  @override
  Future<bool> isPidAlive(int pid) async =>
      (await _run('kill', ['-0', '$pid'])).exitCode == 0;

  @override
  Future<List<String>> missingMacosRequirements(String release) async {
    final flags = await _hostCpuFlags();
    if (flags.isEmpty) {
      // CPU flags could not be detected; do not block the user.
      return const [];
    }
    return (requirements[release] ?? const ['sse4_1'])
        .where((flag) => !flags.contains(flag))
        .toList();
  }
}

/// Terminal emulators quickgui knows how to pass a command to.
final _supportedTerminalEmulators = [
  if (Platform.isMacOS) 'osascript',
  'alacritty',
  'cool-retro-term',
  'foot',
  'gnome-terminal',
  'guake',
  'kgx',
  'kitty',
  'mate-terminal',
  'konsole',
  'lxterm',
  'lxterminal',
  'pterm',
  'sakura',
  'terminator',
  'tilix',
  'uxterm',
  'uxrvt',
  'wezterm',
  'xfce4-terminal',
  'xrvt',
];

/// CPU feature requirements for each macOS release, mirroring quickemu.
const requirements = {
  'ventura': ['sse4_2', 'avx2'],
  'sonoma': ['sse4_2', 'avx2'],
  'sequoia': ['sse4_2', 'avx2'],
  'tahoe': ['sse4_2', 'avx2'],
  'catalina': ['sse4_2'],
  'big-sur': ['sse4_2'],
  'monterey': ['sse4_2'],
};

/// Host CPU flags, lower-cased and normalised (e.g. "SSE4.2" -> "sse4_2").
Future<Set<String>> _hostCpuFlags() async {
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
