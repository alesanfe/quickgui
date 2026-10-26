import 'dart:async';
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
    <T>(kind, target, action, {retrySpec, onCancel}) => ref
        .read(activityProvider.notifier)
        .run<T>(kind, target, action, retrySpec: retrySpec, onCancel: onCancel),
  ),
);

typedef _Track = Future<T> Function<T>(
  OperationKind,
  String,
  Future<T> Function(AppOperation operation), {
  RetrySpec? retrySpec,
  Future<void> Function()? onCancel,
});

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
    // Derive the logical command name for the retry descriptor: the
    // first action flag after --vm, plus the snapshot sub-action.
    String command(String flag) => flag.replaceFirst('--', '');
    final flag = arguments
        .where((a) => a.startsWith('--') && a != '--vm')
        .firstOrNull;
    final retrySpec = flag == null
        ? null
        : RetrySpec(
            command: flag == '--snapshot'
                ? 'snapshot-${arguments[arguments.indexOf('--snapshot') + 1]}'
                : command(flag),
            arguments: List.of(arguments),
            regeneratesPlan: kind == OperationKind.delete,
            requiresConfirmation: kind == OperationKind.delete,
            idempotent:
                kind == OperationKind.start ||
                kind == OperationKind.stop ||
                kind == OperationKind.command,
          );
    return track(
      kind,
      target,
      (op) => backend.runAction(arguments),
      retrySpec: retrySpec,
    );
  }

  /// Commands that are unsafe to interrupt mid-flight — killing the
  /// process could leave the VM config or disks half-modified.
  static const _nonCancellableCommands = {
    'delete-vm',
    'delete-disk',
    'delete-plan',
    'clone',
  };

  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
    void Function(String? operationId)? onMeta,
  }) {
    // Infer the activity kind/target from the quickemu arg tail — same
    // conventions as runAction.
    final index = arguments.indexOf('--vm');
    final target = index >= 0 && index + 1 < arguments.length
        ? p.basenameWithoutExtension(arguments[index + 1])
        : 'Quickemu';
    final kind = command.startsWith('snapshot-')
        ? OperationKind.snapshot
        : command == 'clone'
        ? OperationKind.clone
        : command == 'disk-resize'
        ? OperationKind.resize
        : command.startsWith('delete-')
        ? OperationKind.delete
        : command == 'kill' || command == 'powerdown' || command == 'stop'
        ? OperationKind.stop
        : command == 'start'
        ? OperationKind.start
        : OperationKind.command;
    final retrySpec = RetrySpec(
      command: command,
      arguments: List.of(arguments),
      regeneratesPlan: kind == OperationKind.delete,
      requiresConfirmation: kind == OperationKind.delete,
      idempotent:
          kind == OperationKind.start ||
          kind == OperationKind.stop ||
          kind == OperationKind.command,
    );
    // Destructive commands get no kill switch — an interrupted delete or
    // clone can leave disks/configs in a worse state than letting it run.
    final cancellable =
        cancelSignal == null && !_nonCancellableCommands.contains(command);
    final cancel = cancellable ? Completer<void>() : null;
    return track<Map<String, dynamic>>(
      kind,
      target,
      (op) => backend.runVmJson(
        command,
        arguments,
        cancelSignal: cancelSignal ?? cancel?.future,
        onMeta: (id) {
          op.backendOperationId = id;
          onMeta?.call(id);
        },
      ),
      retrySpec: retrySpec,
      onCancel: cancel == null ? null : () async => cancel.complete(),
    );
  }

  /// Read-only registry query — not a mutating action, so it is
  /// deliberately NOT tracked as an activity operation.
  @override
  Future<Map<String, dynamic>?> operationStatus(
    String target,
    String operationId,
  ) => backend.operationStatus(target, operationId);

  @override
  Future<List<Map<String, dynamic>>> listTrash() => backend.listTrash();

  @override
  Future<void> restoreFromTrash(String vm) => track<void>(
    OperationKind.restore,
    vm,
    (op) => backend.restoreFromTrash(vm),
  );

  @override
  Future<List<Map<String, dynamic>>> listBackups(String target) =>
      backend.listBackups(target);

  @override
  Future<void> createBackup(String target) => track<void>(
    OperationKind.command,
    '$target backup',
    (op) => backend.createBackup(target),
  );

  @override
  Future<void> restoreBackup(String target, String backupFile) => track<void>(
    OperationKind.restore,
    '$target from ${p.basename(backupFile)}',
    (op) => backend.restoreBackup(target, backupFile),
  );

  @override
  Future<void> pruneBackups(String target, {int keep = 5}) =>
      backend.pruneBackups(target, keep: keep);

  @override
  Future<List<Map<String, dynamic>>> snapshotTree(String confPath) =>
      backend.snapshotTree(confPath);

  @override
  Future<Map<String, dynamic>?> hostInfo() => backend.hostInfo();

  @override
  Future<List<Map<String, dynamic>>> listOperations(String target) =>
      backend.listOperations(target);

  @override
  Future<void> cancelOperation(String target, String operationId) =>
      backend.cancelOperation(target, operationId);

  @override
  Future<List<Map<String, dynamic>>> readEvents(
    String target, {
    int cursor = 0,
  }) => backend.readEvents(target, cursor: cursor);

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) =>
      arguments.contains('--create-config')
      ? track(
          OperationKind.import,
          arguments.length > 1 ? arguments[1] : '',
          (op) => backend.runQuickget(arguments),
        )
      : backend.runQuickget(arguments);
  @override
  Future<ProcessResult> exportVm(String vmName) =>
      track(OperationKind.export, vmName, (op) => backend.exportVm(vmName));
  @override
  Future<ProcessResult> verifyImage(String isoPath) => track(
    OperationKind.verify,
    p.basename(isoPath),
    (op) => backend.verifyImage(isoPath),
  );
  @override
  Future<ProcessResult> killVmProcess(String vmName) =>
      track(OperationKind.stop, vmName, (op) => backend.killVmProcess(vmName));
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
    (op) => backend.launchSpiceViewer(
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
    (op) => backend.connectSsh(
      terminalEmulator: terminalEmulator,
      user: user,
      sshPort: sshPort,
    ),
  );
  @override
  Future<ProcessResult> diagnosticsReport() => track(
    OperationKind.command,
    'Quickemu report',
    (op) => backend.diagnosticsReport(),
  );
  @override
  Future<ProcessResult> convertDiskImage(String inputPath, String outputPath) =>
      track(
        OperationKind.convert,
        p.basename(outputPath),
        (op) => backend.convertDiskImage(inputPath, outputPath),
      );
}
