import 'dart:io';

/// Public contract between quickgui and a virtualization backend.
///
/// The domain/presentation layers only see this interface; the concrete
/// implementation (QuickqemuBackend) adapts the external `quickemu` /
/// `quickget` executables. A FakeVirtualizationBackend exists for tests.
abstract class VirtualizationBackend {
  /// True when the backend executables are available on this host.
  Future<bool> checkAvailability();

  /// Installed backend version string, or empty when unavailable.
  Future<String> version();

  /// Machine-readable capability descriptor (`quickemu --capabilities`)
  /// or null when the backend does not publish one.
  Future<Map<String, dynamic>?> getCapabilities();

  /// OS catalogue entries as raw rows
  /// [displayName, os, release, option, downloader].
  Future<List<List<String>>> listOperatingSystems();

  /// VM names found in the working directory.
  Future<List<String>> listVirtualMachines();

  /// Structured VM state: {name, state, pid}.
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm);

  /// Snapshots of the VM described by [confPath], as normalized maps
  /// {id, name, date (unix seconds), vm-state-size} from the v1
  /// `vm-snapshots` contract. Empty when the backend does not publish
  /// the contract or the VM has no snapshots.
  Future<List<Map<String, dynamic>>> listSnapshots(String confPath);

  /// Starts a `quickget` download process for [os] [release] ([option]
  /// may be empty). The caller owns the process: its streams drive
  /// progress, exitCode reports completion, and kill() cancels it.
  Future<Process> startDownloadImage(String os, String release, String option);

  /// Runs an arbitrary action: start/stop/pause/resume/snapshot/etc.
  /// Arguments are the full quickemu CLI tail (e.g. ['--vm','x.conf',
  /// '--snapshot','create','t1']). Returns exit code and merged output.
  Future<ProcessResult> runAction(List<String> arguments);

  /// Runs [arguments] through the structured `--format json` contract
  /// and returns the envelope `data` payload. [command] is the logical
  /// command name the envelope must declare (e.g. 'delete-plan').
  /// Throws `AppFailure` on contract, coherence or backend failures —
  /// callers get typed errors instead of parsing stdout themselves.
  /// `--format json` is appended by the backend; do not repeat it.
  /// [cancelSignal] completes when the caller wants the underlying
  /// process terminated; the executor then throws a `cancelled`
  /// `AppFailure` after graceful-then-forced termination. [onMeta] is
  /// invoked once the envelope arrives with its `meta.operationId`
  /// (null when the backend did not emit one).
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
    void Function(String? operationId)? onMeta,
  });

  /// Queries the backend async-operation registry for [operationId].
  /// Returns the op state map (`state`, `progress`, `type`…) or null
  /// when the backend does not expose the registry / knows no such op.
  Future<Map<String, dynamic>?> operationStatus(
    String target,
    String operationId,
  );

  /// VMs currently in the backend trash (`--trash-list`) — the
  /// structured delete path moves VMs there instead of unlinking.
  Future<List<Map<String, dynamic>>> listTrash();

  /// Restores a VM from the backend trash (`--trash-restore <vm>`).
  Future<void> restoreFromTrash(String vm);

  /// Verified backups for [target] (`--backup-list`): path, size and
  /// checksum state per archive.
  Future<List<Map<String, dynamic>>> listBackups(String target);

  /// Creates a verified archive of the VM (`--backup`).
  Future<void> createBackup(String target);

  /// Restores the VM from a backup archive (`--backup-restore <file>`).
  Future<void> restoreBackup(String target, String backupFile);

  /// Keeps the newest [keep] archives for the VM (`--backup-prune`).
  Future<void> pruneBackups(String target, {int keep = 5});

  /// Snapshot dependency tree (`--snapshot-tree`): parents/branches so
  /// the UI can show lineage instead of a flat list.
  Future<List<Map<String, dynamic>>> snapshotTree(String confPath);

  /// Host inventory from `--host-info` (kernel, KVM, IOMMU, qemu and
  /// dependency flags in one machine-readable call). Null when the
  /// backend predates the structured contract.
  Future<Map<String, dynamic>?> hostInfo();

  /// Lists every async operation the backend registry holds for
  /// [target] (`{operationId,type,state,progress,startedAt}` entries).
  /// Empty when the backend has no registry.
  Future<List<Map<String, dynamic>>> listOperations(String target);

  /// Cancels a registered async operation — the backend marks it
  /// cancelled and terminates its worker when possible.
  Future<void> cancelOperation(String target, String operationId);

  /// Structured VM event tail (`--events <cursor>`): JSONL records with
  /// `seq > cursor` for resumable reading. Empty when unsupported.
  Future<List<Map<String, dynamic>>> readEvents(
    String target, {
    int cursor = 0,
  });

  /// Runs a quickget action (e.g. ['--create-config','name','/path.iso']).
  Future<ProcessResult> runQuickget(List<String> arguments);

  /// Exports the VM disk and config as `vmName.tar.gz`.
  Future<ProcessResult> exportVm(String vmName);

  /// Verifies the downloaded image at [isoPath] with `chunkcheck`.
  Future<ProcessResult> verifyImage(String isoPath);

  /// Force-stops the VM via `killall`, the legacy fallback for backends
  /// too old for `--kill`.
  Future<ProcessResult> killVmProcess(String vmName);

  /// Opens the VM directory in the host file manager.
  Future<ProcessResult> openVmFolder(String vmName);

  /// Launches the SPICE viewer attached to [spicePort].
  Future<ProcessResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  });

  /// Removes the stale known_hosts entry for the VM's SSH port, e.g.
  /// when a new guest reuses the port of a deleted VM.
  Future<ProcessResult> forgetSshHostKey(String sshPort);

  /// Opens [terminalEmulator] running an ssh session into the VM as
  /// [user] on [sshPort].
  Future<ProcessResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  });

  /// Runs the backend's diagnostics report (`quickreport`).
  Future<ProcessResult> diagnosticsReport();

  /// Converts the disk image at [inputPath] to qcow2 at [outputPath]
  /// (`qemu-img convert`). Used when importing foreign image formats.
  Future<ProcessResult> convertDiskImage(String inputPath, String outputPath);
}
