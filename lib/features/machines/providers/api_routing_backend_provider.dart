import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/quickemu/api/quickemu_api_client.dart';

/// The backend the UI should prefer: CLI implementation upgraded with
/// the quickemu API for the calls the daemon covers (QG-020). When the
/// service probe is not usable the wrapper is a pure pass-through, so
/// nothing depends on the daemon existing.
final apiRoutingBackendProvider = Provider<VirtualizationBackend>((ref) {
  final cli = ref.watch(backendProvider);
  final discovery = ref.watch(apiServiceProvider).asData?.value;
  final probe = discovery?.probe;
  final transport = discovery?.transport;
  if (probe == null || !probe.usable || transport == null) return cli;
  return ApiRoutingBackend(
    cli,
    transport,
    token: discovery?.token,
    writesEnabled: probe.writesEnabled,
  );
});

/// Routes API-covered calls to the daemon and everything else to the
/// CLI backend. Read paths (state, operations, vm list) go to the API
/// — they are the hot polling paths where spawns hurt most (QG-022);
/// writes keep the CLI boundary that owns locks/plans.
class ApiRoutingBackend implements VirtualizationBackend {
  ApiRoutingBackend(
    this._cli,
    ApiTransport transport, {
    String? token,
    this.writesEnabled = false,
  }) : _api = QuickemuApiClient(transport, token: token);

  final VirtualizationBackend _cli;
  final QuickemuApiClient _api;

  /// Whether the daemon authorises `POST /v1/vm-cmd` (token configured
  /// and accepted). Read routing works without it; mutations fall back
  /// to the CLI when false.
  final bool writesEnabled;

  /// Structured commands that have an equivalent daemon verb.
  /// `powerdown` (ACPI) maps to the API's `shutdown`; `monitor-cmd`
  /// is handled separately since only two HMP commands are safe.
  static const _apiVerbs = {
    'start': 'start',
    'stop': 'stop',
    'powerdown': 'shutdown',
    'shutdown': 'shutdown',
    'pause': 'pause',
    'resume': 'resume',
    'kill': 'kill',
    'reset': 'reset',
  };

  /// Maps a structured [command]/[arguments] pair to a daemon verb,
  /// or returns null when the API cannot express it.
  static String? _apiVerbFor(String command, List<String> arguments) {
    if (command == 'monitor-cmd') {
      if (arguments.contains('system_reset')) return 'reset';
      if (arguments.contains('system_powerdown')) return 'shutdown';
      return null;
    }
    return _apiVerbs[command];
  }

  /// The daemon addresses VMs by name; the CLI carries
  /// `--vm <confPath>` — basename minus `.conf` is the name.
  static String? _vmNameFrom(List<String> arguments) {
    final i = arguments.indexOf('--vm');
    if (i < 0 || i + 1 >= arguments.length) return null;
    final conf = arguments[i + 1];
    return p.basenameWithoutExtension(conf);
  }

  /// API reads are best-effort upgrades: any failure falls back to the
  /// authoritative CLI path rather than surfacing a new error class.
  Future<T> _preferApi<T>(
    Future<T> Function() apiCall,
    Future<T> Function() cliCall,
  ) async {
    try {
      return await apiCall();
    } catch (_) {
      return await cliCall();
    }
  }

  @override
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm) =>
      _preferApi(() async {
        final data = await _api.vmState(vm);
        final runtime = data['runtime'];
        return <String, dynamic>{
          'name': vm,
          'state': data['state'] ?? 'stopped',
          if (runtime is Map<String, dynamic>) ...runtime,
        };
      }, () => _cli.inspectVirtualMachine(vm));

  @override
  Future<List<String>> listVirtualMachines() => _preferApi(() async {
    final registry = await _api.vms();
    final names = <String>[];
    for (final entry in registry.values) {
      if (entry is Map && entry['vm'] is String) {
        names.add(entry['vm'] as String);
      }
    }
    names.sort();
    return names;
  }, _cli.listVirtualMachines);

  @override
  Future<List<Map<String, dynamic>>> listOperations(String target) =>
      _preferApi(() async {
        final ops = await _api.vmOperations(target);
        return [
          for (final op in ops)
            if (op is Map<String, dynamic>) op,
        ];
      }, () => _cli.listOperations(target));

  @override
  Future<bool> checkAvailability() => _cli.checkAvailability();
  @override
  Future<String> version() => _cli.version();
  @override
  Future<Map<String, dynamic>?> getCapabilities() => _cli.getCapabilities();
  @override
  Future<List<List<String>>> listOperatingSystems() =>
      _cli.listOperatingSystems();
  @override
  Future<List<Map<String, dynamic>>> listSnapshots(String confPath) =>
      _cli.listSnapshots(confPath);
  @override
  Future<RunningProc> startDownloadImage(
    String os,
    String release,
    String option, {
    List<String> flags = const [],
  }) => _cli.startDownloadImage(os, release, option, flags: flags);
  @override
  Future<ProcResult> runAction(List<String> arguments) =>
      _cli.runAction(arguments);
  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
    void Function(String? operationId)? onMeta,
  }) {
    final verb = writesEnabled ? _apiVerbFor(command, arguments) : null;
    final vm = verb == null ? null : _vmNameFrom(arguments);
    if (verb == null || vm == null) {
      return _cli.runVmJson(
        command,
        arguments,
        cancelSignal: cancelSignal,
        onMeta: onMeta,
      );
    }
    // Lifecycle verbs are idempotent at the QEMU layer (starting a
    // running VM, pausing a paused VM) — retrying through the CLI
    // after an API transport failure cannot double-execute anything
    // destructive, so the fallback is safe here.
    return _preferApi(
      () => _api.vmCommand(vm, verb),
      () => _cli.runVmJson(
        command,
        arguments,
        cancelSignal: cancelSignal,
        onMeta: onMeta,
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> operationStatus(
    String target,
    String operationId,
  ) => _cli.operationStatus(target, operationId);
  @override
  Future<List<Map<String, dynamic>>> listTrash() => _cli.listTrash();
  @override
  Future<void> restoreFromTrash(String vm) => _cli.restoreFromTrash(vm);
  @override
  Future<void> emptyTrash() => _cli.emptyTrash();
  @override
  Future<List<Map<String, dynamic>>> listBackups(String target) =>
      _cli.listBackups(target);
  @override
  Future<void> createBackup(String target) => _cli.createBackup(target);
  @override
  Future<void> restoreBackup(String target, String backupFile) =>
      _cli.restoreBackup(target, backupFile);
  @override
  Future<void> pruneBackups(String target, {int keep = 5}) =>
      _cli.pruneBackups(target, keep: keep);
  @override
  Future<void> verifyBackup(String target, String backupFile) =>
      _cli.verifyBackup(target, backupFile);
  @override
  Future<List<Map<String, dynamic>>> snapshotTree(String confPath) =>
      _cli.snapshotTree(confPath);
  @override
  Future<void> verifySnapshots(String confPath) =>
      _cli.verifySnapshots(confPath);
  @override
  Future<void> hotplugUsb(
    String confPath,
    String device, {
    bool persist = false,
  }) => _cli.hotplugUsb(confPath, device, persist: persist);
  @override
  Future<void> hotplugDisk(
    String confPath,
    String diskPath, {
    bool persist = false,
  }) => _cli.hotplugDisk(confPath, diskPath, persist: persist);
  @override
  Future<void> hotunplug(String confPath, String device) =>
      _cli.hotunplug(confPath, device);
  @override
  Future<void> diskCompact(String confPath) => _cli.diskCompact(confPath);
  @override
  Future<List<Map<String, dynamic>>> vfioScan() => _cli.vfioScan();
  @override
  Future<void> moveVm(String confPath, String destination) =>
      _cli.moveVm(confPath, destination);
  @override
  Future<void> renameVm(String confPath, String newName) =>
      _cli.renameVm(confPath, newName);
  @override
  Future<Map<String, dynamic>> migrateConfToToml(String confPath) =>
      _cli.migrateConfToToml(confPath);
  @override
  Future<Map<String, dynamic>?> hostInfo() => _cli.hostInfo();
  @override
  Future<void> cancelOperation(String target, String operationId) =>
      _cli.cancelOperation(target, operationId);
  @override
  Future<List<Map<String, dynamic>>> readEvents(
    String target, {
    int cursor = 0,
  }) => _cli.readEvents(target, cursor: cursor);
  @override
  Future<ProcResult> runQuickget(List<String> arguments) =>
      _cli.runQuickget(arguments);
  @override
  Future<ProcResult> exportVm(String vmName) => _cli.exportVm(vmName);
  @override
  Future<ProcResult> verifyImage(String isoPath) => _cli.verifyImage(isoPath);
  @override
  Future<ProcResult> killVmProcess(String vmName) => _cli.killVmProcess(vmName);
  @override
  Future<ProcResult> openVmFolder(String vmName) => _cli.openVmFolder(vmName);
  @override
  Future<ProcResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  }) =>
      _cli.launchSpiceViewer(spicePort, viewer: viewer, fullscreen: fullscreen);
  @override
  Future<ProcResult> forgetSshHostKey(String sshPort) =>
      _cli.forgetSshHostKey(sshPort);
  @override
  Future<ProcResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
    String? host,
  }) => _cli.connectSsh(
    terminalEmulator: terminalEmulator,
    user: user,
    sshPort: sshPort,
    host: host,
  );
  @override
  Future<ProcResult> diagnosticsReport() => _cli.diagnosticsReport();
  @override
  Future<ProcResult> convertDiskImage(String inputPath, String outputPath) =>
      _cli.convertDiskImage(inputPath, outputPath);
  @override
  Stream<Map<String, dynamic>> watchOperations(String target) =>
      _cli.watchOperations(target);
  @override
  Future<ProcResult> monitorCommand(String target, String command) =>
      _cli.monitorCommand(target, command);
  @override
  Future<Map<String, dynamic>?> vmStats(String target) => _cli.vmStats(target);

  @override
  Future<Map<String, dynamic>?> guestIpInfo(String confPath) =>
      _cli.guestIpInfo(confPath);

  @override
  Future<Map<String, dynamic>?> guestPing(String confPath) =>
      _cli.guestPing(confPath);

  @override
  Future<Map<String, dynamic>?> guestInfo(String confPath) =>
      _cli.guestInfo(confPath);

  @override
  Future<Map<String, dynamic>?> guestExec(String confPath, List<String> argv) =>
      _cli.guestExec(confPath, argv);

  @override
  Future<Map<String, dynamic>?> guestTransfer(
    String confPath, {
    required bool push,
    required String localPath,
    required String guestPath,
    bool force = false,
  }) => _cli.guestTransfer(
    confPath,
    push: push,
    localPath: localPath,
    guestPath: guestPath,
    force: force,
  );

  @override
  Future<ProcResult> guestPower(String confPath, String action) =>
      _cli.guestPower(confPath, action);

  @override
  Future<Map<String, dynamic>?> guestFsFreeze(String confPath, String sub) =>
      _cli.guestFsFreeze(confPath, sub);

  @override
  Future<ProcResult> launchVmToolInTerminal(
    String terminalEmulator,
    String tool,
    String confPath,
  ) => _cli.launchVmToolInTerminal(terminalEmulator, tool, confPath);

  @override
  Future<ProcResult> sshConfig(String confPath) => _cli.sshConfig(confPath);
  @override
  // The daemon's `/v1/vms` is the same `vms.json` registry the CLI
  // reads — one HTTP call replaces a process spawn.
  Future<Map<String, dynamic>> listInventory() =>
      _preferApi(_api.vms, _cli.listInventory);
  @override
  Future<void> linkedClone(String target, String destination) =>
      _cli.linkedClone(target, destination);
  @override
  Future<void> startWithProfile(String target, String profile) =>
      _cli.startWithProfile(target, profile);
  @override
  Future<List<String>> listPlugins() => _cli.listPlugins();
}
