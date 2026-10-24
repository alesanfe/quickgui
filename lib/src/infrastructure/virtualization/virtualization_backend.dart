import 'dart:io';

/// Public contract between quickgui and a virtualization backend.
///
/// The domain/presentation layers only see this interface; the concrete
/// implementation (QuickqemuBackend) adapts the external `quickemu` /
/// `quickget` executables. A FakeVirtualizationBackend exists for tests.
abstract class VirtualizationBackend {
  /// True when the backend executables are available on this host.
  Future<bool> checkAvailability();

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

  /// Streams quickget's stdout/stderr while downloading [os] [release]
  /// ([option] may be empty). Yields raw output lines.
  Stream<String> downloadImage(String os, String release, String option);

  /// Runs an arbitrary action: start/stop/pause/resume/snapshot/etc.
  /// Arguments are the full quickemu CLI tail (e.g. ['--vm','x.conf',
  /// '--snapshot','create','t1']). Returns exit code and merged output.
  Future<ProcessResult> runAction(List<String> arguments);

  /// Runs a quickget action (e.g. ['--create-config','name','/path.iso']).
  Future<ProcessResult> runQuickget(List<String> arguments);
}
