import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_parser.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_process.dart';
import 'package:quickgui/infrastructure/quickemu/structured_quickemu.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// VirtualizationBackend backed by the quickemu/quickget executables.
/// Uses the structured CLI contract (--capabilities, --format json)
/// when present and degrades gracefully on older versions.
class QuickemuBackend implements VirtualizationBackend {
  QuickemuBackend(ProcessRunner runner)
    : _runner = runner,
      _process = QuickemuProcess(runner),
      _structured = StructuredQuickemu(QuickemuProcess(runner));

  final ProcessRunner _runner;
  final QuickemuProcess _process;
  final StructuredQuickemu _structured;

  @override
  Future<bool> checkAvailability() async {
    final get = await _process.quickget(['--version']);
    final emu = await _process.quickemu(['--version']);
    return get.exitCode == 0 && emu.exitCode == 0;
  }

  @override
  Future<Map<String, dynamic>?> getCapabilities() async {
    final r = await _process.quickemu(capabilitiesArgs);
    if (r.exitCode != 0) return null;
    try {
      final response = _structured.resolve('capabilities', r);
      return response.dataMap;
    } on AppFailure catch (e) {
      if (!StructuredQuickemu.isLegacyBackend(e)) rethrow;
      AppLog.backendContract.info(
        'capabilities: legacy backend, envelope unavailable (${e.code})',
      );
      return parseCapabilitiesPayload('${r.stdout}');
    }
  }

  @override
  Future<List<List<String>>> listOperatingSystems() async {
    // Prefer the structured JSON catalogue, fall back to CSV.
    final json = await _process.quickget(['--list-json']);
    if (json.exitCode == 0) {
      final parsed = parseOsCatalogueJson('${json.stdout}');
      if (parsed != null) return parsed;
    }
    final csv = await _process.quickget(['--list-csv']);
    return parseOsCatalogueCsv('${csv.stdout}');
  }

  @override
  Future<List<String>> listVirtualMachines() async {
    // Structured path first (quickemu --list-vms --format json);
    // fall back to scanning *.conf files.
    final r = await _process.quickemu([...listVmsArgs, ...formatJsonArgs]);
    if (r.exitCode == 0) {
      try {
        final response = _structured.resolve('list-vms', r);
        final vms = response.dataMap?['vms'];
        if (vms is List) {
          return [
            for (final v in vms)
              if (v is Map && v['name'] is String)
                v['name'] as String
              else if (v is String)
                v,
          ];
        }
      } on AppFailure catch (e) {
        if (!StructuredQuickemu.isLegacyBackend(e)) rethrow;
        AppLog.backendContract.info(
          'list-vms: legacy backend, envelope unavailable (${e.code})',
        );
      }
      final parsed = parseVmListPayload('${r.stdout}');
      if (parsed != null) return parsed;
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
    final r = await _process.quickemu([
      '--vm',
      '$vm.conf',
      '--status',
      ...formatJsonArgs,
    ]);
    if (r.exitCode == 0) {
      try {
        final response = _structured.resolve('status', r, vm: vm);
        final map = response.dataMap;
        if (map != null) return map;
      } on AppFailure catch (e) {
        if (!StructuredQuickemu.isLegacyBackend(e)) rethrow;
        AppLog.backendContract.info(
          'status: legacy backend, envelope unavailable (${e.code})',
        );
      }
      final parsed = parseVmStatusPayload('${r.stdout}');
      if (parsed != null) return parsed;
    }
    return parseLegacyVmStatus(vm, '${r.stdout}');
  }

  @override
  Future<List<Map<String, dynamic>>> listSnapshots(String confPath) async {
    final r = await _process.quickemu([
      '--vm',
      confPath,
      '--snapshot',
      'list',
      ...formatJsonArgs,
    ]);
    if (r.exitCode != 0) return const [];
    try {
      final response = _structured.resolve('snapshot-list', r);
      final snaps = response.dataList;
      if (snaps != null) {
        return [
          for (final s in snaps)
            if (s is Map<String, dynamic>) s,
        ];
      }
    } on AppFailure catch (e) {
      if (!StructuredQuickemu.isLegacyBackend(e)) rethrow;
      AppLog.backendContract.info(
        'snapshot-list: legacy backend, envelope unavailable (${e.code})',
      );
    }
    return parseVmSnapshotsPayload('${r.stdout}') ?? const [];
  }

  @override
  Future<Process> startDownloadImage(String os, String release, String option) {
    return _process.startQuickget([os, release, if (option.isNotEmpty) option]);
  }

  @override
  Future<ProcessResult> runAction(List<String> arguments) =>
      _process.quickemu(arguments);

  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
  }) async {
    final response = await _structured.run(
      command,
      arguments,
      cancelSignal: cancelSignal,
    );
    final data = response.dataMap;
    if (data == null) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'UNEXPECTED_DATA',
        'The backend returned data in an unexpected shape.',
        technical: 'command=$command data=${response.data.runtimeType}',
      );
    }
    return data;
  }

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) =>
      _process.quickget(arguments);

  @override
  Future<ProcessResult> exportVm(String vmName) =>
      _process.quickemu(['--vm', '$vmName.conf', '--export', '$vmName.tar.gz']);

  @override
  Future<ProcessResult> verifyImage(String isoPath) =>
      _process.chunkcheck(isoPath);

  @override
  Future<ProcessResult> killVmProcess(String vmName) {
    // Kill by pid from <vm>/<vm>.pid — `killall <name>` matches by process
    // name and can hit unrelated processes.
    final pidFile = File('$vmName/$vmName.pid');
    if (pidFile.existsSync()) {
      final pid = pidFile.readAsStringSync().trim();
      if (pid.isNotEmpty) return _runner.run('kill', ['-9', pid]);
    }
    return _runner.run('killall', [vmName]);
  }

  @override
  Future<ProcessResult> openVmFolder(String vmName) =>
      _runner.run(Platform.isMacOS ? 'open' : 'xdg-open', [vmName]);

  @override
  Future<ProcessResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  }) {
    if (!{'spicy', 'remote-viewer'}.contains(viewer) ||
        int.tryParse(spicePort) == null ||
        int.parse(spicePort) < 1 ||
        int.parse(spicePort) > 65535) {
      return Future.value(
        ProcessResult(0, 2, '', 'Invalid viewer or SPICE port'),
      );
    }
    return viewer == 'remote-viewer'
        ? _runner.run(viewer, [
            if (fullscreen) '--full-screen',
            'spice://127.0.0.1:$spicePort',
          ])
        : _runner.run(viewer, [
            '-h',
            '127.0.0.1',
            '-p',
            spicePort,
            if (fullscreen) '--full-screen',
          ]);
  }

  @override
  Future<ProcessResult> forgetSshHostKey(String sshPort) =>
      _runner.run('ssh-keygen', ['-R', '[localhost]:$sshPort']);

  @override
  Future<ProcessResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  }) {
    // The ssh user comes from the VM .conf and is interpolated into a
    // `sh -c` string — reject anything that is not a plain login name.
    final safeUser = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]*$').hasMatch(user)
        ? user
        : '';
    var sshArgs = <String>[
      'ssh',
      '-p',
      sshPort,
      if (safeUser.isEmpty) 'localhost' else '$safeUser@localhost',
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
  Future<ProcessResult> diagnosticsReport() => _process.quickreport();

  @override
  Future<ProcessResult> convertDiskImage(String inputPath, String outputPath) =>
      _runner.run('qemu-img', [
        'convert',
        '-O',
        'qcow2',
        inputPath,
        outputPath,
      ]);

  @override
  Future<String> version() async {
    final result = await _process.quickemu(['--version']);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : '';
  }
}
