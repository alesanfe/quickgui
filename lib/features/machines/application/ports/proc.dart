/// Domain-level process primitives for the `VirtualizationBackend`
/// port.
///
/// dart:io `Process`/`ProcessResult` must not leak into the
/// application layer (`test/architecture/arch_test.dart` enforces it):
/// these types carry the same shape — same member names — so callers
/// migrate by changing the declared type, not the call sites. The
/// infrastructure layer adapts real processes via `SystemRunningProc`.
library;

/// Finished-process result: exit code plus captured output. The
/// fields mirror `ProcessResult` minus the pid (callers never used
/// it); `stdout`/`stderr` stay untyped because runners may decode to
/// String or leave bytes.
class ProcResult {
  const ProcResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;
}

/// A started, still-running process. The caller owns it: [stdout] and
/// [stderr] streams drive progress, [exitCode] reports completion and
/// [kill] cancels. Same member names as `dart:io` `Process`.
abstract class RunningProc {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill();
}
