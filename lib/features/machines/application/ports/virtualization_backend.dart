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
}
