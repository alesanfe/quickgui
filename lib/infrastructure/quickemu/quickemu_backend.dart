import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// VirtualizationBackend backed by the quickemu/quickget executables.
/// Uses the structured CLI contract (--capabilities, --format json)
/// when present and degrades gracefully on older versions.
class QuickemuBackend implements VirtualizationBackend {
  QuickemuBackend(this._runner);

  final ProcessRunner _runner;

  @override
  Future<bool> checkAvailability() async {
    final get = await _runner.run('quickget', ['--version']);
    final emu = await _runner.run('quickemu', ['--version']);
    return get.exitCode == 0 && emu.exitCode == 0;
  }

  @override
  Future<Map<String, dynamic>?> getCapabilities() async {
    try {
      final r = await _runner.run('quickemu', ['--capabilities']);
      if (r.exitCode != 0) return null;
      final decoded = jsonDecode('${r.stdout}'.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // older quickemu without --capabilities
    }
  }

  @override
  Future<List<List<String>>> listOperatingSystems() async {
    // Prefer the structured JSON catalogue, fall back to CSV.
    final json = await _runner.run('quickget', ['--list-json']);
    if (json.exitCode == 0 && '${json.stdout}'.trim().isNotEmpty) {
      try {
        return [
          for (final e in jsonDecode('${json.stdout}') as List)
            [
              '${e['Display Name']}',
              '${e['OS']}',
              '${e['Release']}',
              '${e['Option']}',
              '${e['Downloader']}',
            ],
        ];
      } catch (_) {}
    }
    final csv = await _runner.run('quickget', ['--list-csv']);
    return '${csv.stdout}'
        .split('\n')
        .skip(1)
        .where((l) => l.isNotEmpty)
        .map((l) => l.trim().split(','))
        .toList();
  }

  @override
  Future<List<String>> listVirtualMachines() async {
    // Structured path first (quickemu --list-vms --format json);
    // fall back to scanning *.conf files.
    final r = await _runner.run('quickemu', ['--list-vms', '--format', 'json']);
    if (r.exitCode == 0) {
      try {
        final decoded = jsonDecode('${r.stdout}'.trim());
        if (decoded is Map) {
          final vms = decoded['vms'];
          if (vms is List) {
            return [for (final v in vms) '${(v as Map)['name']}'];
          }
        }
      } catch (_) {}
    }
    return Directory.current
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.conf'))
        .map(
          (f) =>
              f.path.split(Platform.pathSeparator).last.replaceAll('.conf', ''),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm) async {
    final r = await _runner.run('quickemu', [
      '--vm',
      '$vm.conf',
      '--status',
      '--format',
      'json',
    ]);
    if (r.exitCode == 0) {
      try {
        final decoded = jsonDecode('${r.stdout}'.trim());
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    // Fallback: legacy "running <pid>" / "stopped" text.
    final text = '${r.stdout}'.trim();
    return {
      'name': vm,
      'state': text.startsWith('running') ? 'running' : 'stopped',
      'pid': int.tryParse(text.split(' ').last),
    };
  }

  @override
  Future<Process> startDownloadImage(String os, String release, String option) {
    return _runner.start('quickget', [
      os,
      release,
      if (option.isNotEmpty) option,
    ]);
  }

  @override
  Future<ProcessResult> runAction(List<String> arguments) =>
      _runner.run('quickemu', arguments);

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) =>
      _runner.run('quickget', arguments);

  @override
  Future<ProcessResult> exportVm(String vmName) => _runner.run('quickemu', [
    '--vm',
    '$vmName.conf',
    '--export',
    '$vmName.tar.gz',
  ]);

  @override
  Future<ProcessResult> verifyImage(String isoPath) =>
      _runner.run('chunkcheck', [isoPath]);

  @override
  Future<ProcessResult> killVmProcess(String vmName) =>
      _runner.run('killall', [vmName]);

  @override
  Future<ProcessResult> openVmFolder(String vmName) =>
      _runner.run(Platform.isMacOS ? 'open' : 'xdg-open', [vmName]);

  @override
  Future<ProcessResult> launchSpiceViewer(String spicePort) =>
      _runner.run('spicy', ['-p', spicePort]);

  @override
  Future<ProcessResult> forgetSshHostKey(String sshPort) =>
      _runner.run('ssh-keygen', ['-R', '[localhost]:$sshPort']);

  @override
  Future<ProcessResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  }) {
    var sshArgs = <String>[
      'ssh',
      '-p',
      sshPort,
      if (user.isEmpty) 'localhost' else '$user@localhost',
    ];
    // Set the arguments to execute the ssh command in the default terminal.
    // Strip the extension as x-terminal-emulator may point to a .wrapper
    switch (p.basenameWithoutExtension(terminalEmulator)) {
      case 'osascript':
        sshArgs = [
          '-e \'tell app "Terminal" to do script "${sshArgs.join(' ')}"\'',
        ];
      case 'gnome-terminal':
      case 'mate-terminal':
        sshArgs.insert(0, '--');
      case 'kitty':
      case 'foot':
        // Run the command directly: `kitty ssh ...`
        break;
      case 'wezterm':
        sshArgs.insert(0, 'start');
      case 'alacritty':
      case 'xterm':
      case 'lxterm':
      case 'uxterm':
      case 'konsole':
      case 'uxrvt':
      case 'xrvt':
      case 'sakura':
      case 'cool-retro-term':
      case 'pterm':
      case 'lxterminal':
      case 'tilix':
      case 'kgx':
        sshArgs.insert(0, '-e');
      case 'terminator':
      case 'xfce4-terminal':
        sshArgs.insert(0, '-x');
      case 'guake':
        final String command = sshArgs.join(' ');
        sshArgs = ['-e', command];
    }
    sshArgs.insert(0, terminalEmulator);
    // The argument styles above embed shell quoting on purpose, so the
    // assembled command goes through `sh -c` exactly like before.
    return _runner.run('sh', ['-c', sshArgs.join(' ')]);
  }

  @override
  Future<ProcessResult> diagnosticsReport() => _runner.run('quickreport', []);

  @override
  Future<String> version() async {
    final result = await _runner.run('quickemu', ['--version']);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : '';
  }
}
