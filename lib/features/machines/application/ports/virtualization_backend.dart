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

  /// Starts a `quickget` download process for [os] [release] ([option]
  /// may be empty). The caller owns the process: its streams drive
  /// progress, exitCode reports completion, and kill() cancels it.
  Future<Process> startDownloadImage(String os, String release, String option);

  /// Runs an arbitrary action: start/stop/pause/resume/snapshot/etc.
  /// Arguments are the full quickemu CLI tail (e.g. ['--vm','x.conf',
  /// '--snapshot','create','t1']). Returns exit code and merged output.
  Future<ProcessResult> runAction(List<String> arguments);

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
  Future<ProcessResult> launchSpiceViewer(String spicePort);

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
}
