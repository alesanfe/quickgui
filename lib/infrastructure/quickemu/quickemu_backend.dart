import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_parser.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_process.dart';
import 'package:quickgui/infrastructure/quickemu/structured_quickemu.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/infrastructure/process/running_proc.dart';

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

  /// Wraps an infra `ProcessResult` into the domain `ProcResult` —
  /// the port boundary must not expose dart:io types.
  static Future<ProcResult> _proc(Future<ProcessResult> r) async {
    final x = await r;
    return ProcResult(x.exitCode, x.stdout, x.stderr);
  }

  @override
  Future<RunningProc> startDownloadImage(
    String os,
    String release,
    String option,
  ) async => SystemRunningProc(
    await _process.startQuickget([os, release, if (option.isNotEmpty) option]),
  );

  @override
  Future<ProcResult> runAction(List<String> arguments) =>
      _proc(_process.quickemu(arguments));

  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
    void Function(String? operationId)? onMeta,
  }) async {
    final response = await _structured.run(
      command,
      arguments,
      cancelSignal: cancelSignal,
    );
    onMeta?.call(response.operationId);
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
  Future<Map<String, dynamic>?> operationStatus(
    String target,
    String operationId,
  ) async {
    try {
      final response = await _structured.run('op-status', [
        '--vm',
        '$target.conf',
        '--op-status',
        operationId,
      ]);
      return response.dataMap;
    } on AppFailure catch (e) {
      // Registry absent or op unknown — caller falls back to heuristics.
      if (isBackendEnvelopeMissing(e) || e.code == 'OPERATION_NOT_FOUND') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listTrash() async {
    try {
      final response = await _structured.run('trash-list', ['--trash-list']);
      final items = response.dataMap?['items'] ?? response.dataMap?['trash'];
      return items is List
          ? [for (final i in items) Map<String, dynamic>.from(i as Map)]
          : const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<void> restoreFromTrash(String vm) async {
    await _structured.run('trash-restore', ['--trash-restore', vm]);
  }

  @override
  Future<List<Map<String, dynamic>>> readEvents(
    String target, {
    int cursor = 0,
  }) async {
    try {
      final response = await _structured.run('events', [
        '--vm',
        '$target.conf',
        '--events',
        '$cursor',
      ]);
      final events = response.dataMap?['events'];
      if (events is List) {
        return [for (final e in events) Map<String, dynamic>.from(e as Map)];
      }
      return const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listBackups(String target) async {
    try {
      final response = await _structured.run('backup-list', [
        '--vm',
        '$target.conf',
        '--backup-list',
      ]);
      final items = response.dataMap?['backups'] ?? response.dataMap?['items'];
      return items is List
          ? [for (final i in items) Map<String, dynamic>.from(i as Map)]
          : const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<void> createBackup(String target) async {
    await _structured.run('backup', ['--vm', '$target.conf', '--backup']);
  }

  @override
  Future<void> restoreBackup(String target, String backupFile) async {
    await _structured.run('backup-restore', [
      '--vm',
      '$target.conf',
      '--backup-restore',
      backupFile,
    ]);
  }

  @override
  Future<void> pruneBackups(String target, {int keep = 5}) async {
    await _structured.run('backup-prune', [
      '--vm',
      '$target.conf',
      '--backup-prune',
      '$keep',
    ]);
  }

  @override
  Future<List<Map<String, dynamic>>> snapshotTree(String confPath) async {
    try {
      final response = await _structured.run('snapshot-tree', [
        '--vm',
        confPath,
        '--snapshot-tree',
      ]);
      final items = response.dataMap?['snapshots'] ?? response.dataMap?['tree'];
      return items is List
          ? [for (final i in items) Map<String, dynamic>.from(i as Map)]
          : const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<void> hotplugUsb(String confPath, String device) async {
    await _structured.run('hotplug', [
      '--vm',
      confPath,
      '--hotplug-usb',
      device,
    ]);
  }

  @override
  Future<void> hotplugDisk(String confPath, String diskPath) async {
    await _structured.run('hotplug', [
      '--vm',
      confPath,
      '--hotplug-disk',
      diskPath,
    ]);
  }

  @override
  Future<void> diskCompact(String confPath) async {
    await _structured.run('disk-compact', ['--vm', confPath, '--disk-compact']);
  }

  @override
  Future<List<Map<String, dynamic>>> vfioScan() async {
    try {
      final response = await _structured.run('vfio-scan', ['--vfio-scan']);
      final items = response.dataMap?['devices'] ?? response.dataMap?['gpus'];
      return items is List
          ? [for (final i in items) Map<String, dynamic>.from(i as Map)]
          : const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<void> moveVm(String confPath, String destination) async {
    await _structured.run('move', ['--vm', confPath, '--move', destination]);
  }

  @override
  Future<void> renameVm(String confPath, String newName) async {
    await _structured.run('rename', ['--vm', confPath, '--rename', newName]);
  }

  @override
  Future<Map<String, dynamic>> migrateConfToToml(String confPath) async {
    final response = await _structured.run('migrate-conf', [
      '--vm',
      confPath,
      '--migrate-conf',
    ]);
    return response.dataMap ?? const {};
  }

  @override
  Future<Map<String, dynamic>?> hostInfo() async {
    try {
      final response = await _structured.run('host-info', ['--host-info']);
      return response.dataMap;
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return null;
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listOperations(String target) async {
    try {
      final response = await _structured.run('op-list', [
        '--vm',
        '$target.conf',
        '--op-list',
      ]);
      final ops = response.dataMap?['operations'];
      return ops is List
          ? [for (final o in ops) Map<String, dynamic>.from(o as Map)]
          : const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }

  @override
  Future<void> cancelOperation(String target, String operationId) async {
    await _structured.run('op-cancel', [
      '--vm',
      '$target.conf',
      '--op-cancel',
      operationId,
    ]);
  }

  @override
  Future<ProcResult> runQuickget(List<String> arguments) =>
      _proc(_process.quickget(arguments));

  /// Export via the v1 envelope (`vm.export`) — typed failures reach
  /// callers as stderr-shaped ProcessResult to keep the signature;
  /// a pre-contract backend falls back to the raw text path.
  @override
  Future<ProcResult> exportVm(String vmName) async {
    final args = ['--vm', '$vmName.conf', '--export', '$vmName.tar.gz'];
    try {
      final response = await _structured.run('export', args);
      return ProcResult(0, '${response.dataMap ?? ''}', '');
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) {
        return await _proc(_process.quickemu(args));
      }
      return ProcResult(1, '', e.userMessage);
    }
  }

  @override
  Future<ProcResult> verifyImage(String isoPath) =>
      _proc(_process.chunkcheck(isoPath));

  /// A .pid file is untrusted content: "-1" turns `kill -9` into a
  /// signal for every process of the user, and non-numeric values are
  /// meaningless. Digits only, then a positive pid.
  static int? _safePid(String raw) {
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    final pid = int.tryParse(raw);
    return pid != null && pid > 0 ? pid : null;
  }

  /// On Linux the VM's qemu always carries its state dir in argv — a
  /// recycled pid running something else must not be killed. When the
  /// kernel hides cmdline (non-linux, permissions) the caller keeps
  /// the previous liveness-only behavior.
  static bool _pidLooksLikeVm(int pid, String vmName) {
    try {
      final cl = File('/proc/$pid/cmdline')
          .readAsStringSync()
          .replaceAll('\x00', ' ');
      if (cl.isEmpty) return true;
      return cl.contains('/$vmName/') ||
          cl.contains('process=$vmName,') ||
          cl.endsWith('process=$vmName');
    } catch (_) {
      return true;
    }
  }

  @override
  Future<ProcResult> killVmProcess(String vmName) {
    // Kill by pid from <vm>/<vm>.pid — `killall <name>` matches by process
    // name and can hit unrelated processes.
    final pidFile = File('$vmName/$vmName.pid');
    if (pidFile.existsSync()) {
      final pid = _safePid(pidFile.readAsStringSync().trim());
      if (pid != null) {
        if (!_pidLooksLikeVm(pid, vmName)) {
          return Future.value(
            const ProcResult(1, '', 'pid does not belong to this VM'),
          );
        }
        return _proc(_runner.run('kill', ['-9', '$pid']));
      }
      // Malformed pidfile (torn write or hostile content): the pid
      // never reaches kill argv — fall through to the name-based
      // recovery path instead.
    }
    // killall treats a leading-dash name as an option — spaces are
    // fine (single argv element), an option-looking name is not.
    if (vmName.isEmpty || vmName.startsWith('-')) {
      return Future.value(const ProcResult(1, '', 'invalid vm name'));
    }
    return _proc(_runner.run('killall', [vmName]));
  }

  @override
  Future<ProcResult> openVmFolder(String vmName) =>
      _proc(_runner.run(Platform.isMacOS ? 'open' : 'xdg-open', [vmName]));

  @override
  Future<ProcResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  }) {
    if (!{'spicy', 'remote-viewer'}.contains(viewer) ||
        int.tryParse(spicePort) == null ||
        int.parse(spicePort) < 1 ||
        int.parse(spicePort) > 65535) {
      return Future.value(
        const ProcResult(2, '', 'Invalid viewer or SPICE port'),
      );
    }
    return viewer == 'remote-viewer'
        ? _proc(
            _runner.run(viewer, [
              if (fullscreen) '--full-screen',
              'spice://127.0.0.1:$spicePort',
            ]),
          )
        : _proc(
            _runner.run(viewer, [
              '-h',
              '127.0.0.1',
              '-p',
              spicePort,
              if (fullscreen) '--full-screen',
            ]),
          );
  }

  /// sshPort comes from the VM's .ports file — untrusted content that
  /// lands in a `sh -c` string (connectSsh) or an argv element
  /// (forgetSshHostKey). Only a plain numeric port is ever valid.
  static bool _validPort(String port) =>
      RegExp(r'^\d{1,5}$').hasMatch(port) && (int.tryParse(port) ?? 0) <= 65535;

  @override
  Future<ProcResult> forgetSshHostKey(String sshPort) {
    if (!_validPort(sshPort)) {
      return Future.value(const ProcResult(1, '', 'invalid ssh port'));
    }
    return _proc(_runner.run('ssh-keygen', ['-R', '[localhost]:$sshPort']));
  }

  @override
  Future<ProcResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  }) {
    // The ssh user comes from the VM .conf and is interpolated into a
    // `sh -c` string — reject anything that is not a plain login name.
    // sshPort is likewise file content interpolated into that string.
    final safeUser = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]*$').hasMatch(user)
        ? user
        : '';
    if (!_validPort(sshPort)) {
      return Future.value(const ProcResult(1, '', 'invalid ssh port'));
    }
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
    return _proc(_runner.run('sh', ['-c', sshArgs.join(' ')]));
  }

  @override
  Future<ProcResult> diagnosticsReport() => _proc(_process.quickreport());

  @override
  Future<ProcResult> convertDiskImage(String inputPath, String outputPath) =>
      _proc(
        _runner.run('qemu-img', [
          'convert',
          '-O',
          'qcow2',
          inputPath,
          outputPath,
        ]),
      );

  @override
  Future<String> version() async {
    final result = await _process.quickemu(['--version']);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : '';
  }

  /// Streams op-state changes as JSONL (`--op-watch`). Push replaces
  /// the --op-list polling loop for long-running ops (clone/export).
  /// The structured runner is a bounded call — a watch needs a live
  /// process, so we spawn quickemu directly on the same contract.
  @override
  Stream<Map<String, dynamic>> watchOperations(String target) async* {
    // A missing/unspawnable backend makes the watch a no-op rather than a
    // stream error — callers fall back to --op-list polling as designed.
    final Process proc;
    try {
      proc = await _process.startQuickemu([
        '--vm',
        '$target.conf',
        '--op-watch',
        '--format',
        'json',
      ]);
    } on ProcessException {
      return;
    }
    yield* proc.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .where((l) => l.trimLeft().startsWith('{'))
        .map((l) {
          try {
            return Map<String, dynamic>.from(
              jsonDecode(l) as Map<dynamic, dynamic>,
            );
          } on FormatException {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty);
  }

  /// Sends an HMP command to the VM monitor socket (`--monitor-cmd`)
  /// — text path, there is no structured envelope for it.
  @override
  Future<ProcResult> monitorCommand(String target, String command) => _proc(
    _process.quickemu(['--vm', '$target.conf', '--monitor-cmd', command]),
  );

  /// Per-VM runtime metrics via `--stats` (QMP cpus/block/balloon).
  @override
  Future<Map<String, dynamic>?> vmStats(String target) async {
    try {
      final response = await _structured.run('stats', [
        '--vm',
        '$target.conf',
        '--stats',
      ]);
      return response.dataMap;
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e) || e.code == 'VM_MUST_BE_RUNNING') {
        return null;
      }
      rethrow;
    }
  }

  /// Global VM inventory (`--inventory` -> vms.json shaped map).
  @override
  Future<Map<String, dynamic>> listInventory() async {
    try {
      final response = await _structured.run('inventory', ['--inventory']);
      return response.dataMap ?? const {};
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const {};
      rethrow;
    }
  }

  /// COW clone via `--linked-clone` (qcow2 backing-file).
  @override
  Future<void> linkedClone(String target, String destination) async {
    await _structured.run('linked-clone', [
      '--vm',
      '$target.conf',
      '--linked-clone',
      destination,
    ]);
  }

  /// Boot with a reusable profile preset (`--profile`).
  @override
  Future<void> startWithProfile(String target, String profile) async {
    await _structured.run('profile', [
      '--vm',
      '$target.conf',
      '--profile',
      profile,
    ]);
  }

  /// Plugins installed on PATH (`--plugins` -> space-separated names).
  @override
  Future<List<String>> listPlugins() async {
    try {
      final response = await _structured.run('plugins', ['--plugins']);
      final items = response.dataMap?['plugins'] ?? response.data;
      if (items is List) return items.map((e) => '$e').toList();
      return const [];
    } on AppFailure catch (e) {
      if (isBackendEnvelopeMissing(e)) return const [];
      rethrow;
    }
  }
}
