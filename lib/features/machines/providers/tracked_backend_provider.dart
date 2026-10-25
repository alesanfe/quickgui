import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

final trackedBackendProvider = Provider<VirtualizationBackend>(
  (ref) => _TrackedBackend(
    ref.watch(backendProvider),
    (kind, target, action) =>
        ref.read(activityProvider.notifier).run(kind, target, action),
  ),
);

typedef _Track = Future<ProcessResult> Function(
  OperationKind,
  String,
  Future<ProcessResult> Function(),
);

class _TrackedBackend implements VirtualizationBackend {
  _TrackedBackend(this.backend, this.track);
  final VirtualizationBackend backend;
  final _Track track;

  @override
  Future<bool> checkAvailability() => backend.checkAvailability();
  @override
  Future<String> version() => backend.version();
  @override
  Future<Map<String, dynamic>?> getCapabilities() => backend.getCapabilities();
  @override
  Future<List<List<String>>> listOperatingSystems() =>
      backend.listOperatingSystems();
  @override
  Future<List<String>> listVirtualMachines() => backend.listVirtualMachines();
  @override
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm) =>
      backend.inspectVirtualMachine(vm);
  @override
  Future<List<Map<String, dynamic>>> listSnapshots(String confPath) =>
      backend.listSnapshots(confPath);
  @override
  Future<Process> startDownloadImage(
    String os,
    String release,
    String option,
  ) => backend.startDownloadImage(os, release, option);
  @override
  Future<ProcessResult> runAction(List<String> arguments) {
    final index = arguments.indexOf('--vm');
    final target = index >= 0 && index + 1 < arguments.length
        ? p.basenameWithoutExtension(arguments[index + 1])
        : 'Quickemu';
    final kind = arguments.contains('--snapshot')
        ? OperationKind.snapshot
        : arguments.contains('--clone')
        ? OperationKind.clone
        : arguments.contains('--disk-resize')
        ? OperationKind.resize
        : arguments.any((a) => a == '--delete-vm' || a == '--delete-disk')
        ? OperationKind.delete
        : arguments.any(
            (a) => a == '--kill' || a == '--stop' || a == '--powerdown',
          )
        ? OperationKind.stop
        : arguments.length == 2 || arguments.contains('--display')
        ? OperationKind.start
        : OperationKind.command;
    if (arguments.contains('--delete-plan') || arguments.contains('--status')) {
      return backend.runAction(arguments);
    }
    return track(kind, target, () => backend.runAction(arguments));
  }

  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments,
  ) => backend.runVmJson(command, arguments);

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) =>
      arguments.contains('--create-config')
      ? track(
          OperationKind.import,
          arguments.length > 1 ? arguments[1] : '',
          () => backend.runQuickget(arguments),
        )
      : backend.runQuickget(arguments);
  @override
  Future<ProcessResult> exportVm(String vmName) =>
      track(OperationKind.export, vmName, () => backend.exportVm(vmName));
  @override
  Future<ProcessResult> verifyImage(String isoPath) => track(
    OperationKind.verify,
    p.basename(isoPath),
    () => backend.verifyImage(isoPath),
  );
  @override
  Future<ProcessResult> killVmProcess(String vmName) =>
      track(OperationKind.stop, vmName, () => backend.killVmProcess(vmName));
  @override
  Future<ProcessResult> openVmFolder(String vmName) =>
      backend.openVmFolder(vmName);
  @override
  Future<ProcessResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  }) => track(
    OperationKind.command,
    'SPICE :$spicePort',
    () => backend.launchSpiceViewer(
      spicePort,
      viewer: viewer,
      fullscreen: fullscreen,
    ),
  );
  @override
  Future<ProcessResult> forgetSshHostKey(String sshPort) =>
      backend.forgetSshHostKey(sshPort);
  @override
  Future<ProcessResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  }) => track(
    OperationKind.command,
    'SSH :$sshPort',
    () => backend.connectSsh(
      terminalEmulator: terminalEmulator,
      user: user,
      sshPort: sshPort,
    ),
  );
  @override
  Future<ProcessResult> diagnosticsReport() => track(
    OperationKind.command,
    'Quickemu report',
    backend.diagnosticsReport,
  );
  @override
  Future<ProcessResult> convertDiskImage(String inputPath, String outputPath) =>
      track(
        OperationKind.convert,
        p.basename(outputPath),
        () => backend.convertDiskImage(inputPath, outputPath),
      );
}
