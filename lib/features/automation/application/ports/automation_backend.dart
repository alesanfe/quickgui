import 'package:quickgui/features/machines/application/ports/proc.dart';

/// Contract between quickgui and the automation engine (`quickprovision`).
///
/// The engine is a sibling binary of quickemu/quickget: profiles go in
/// as TOML files, runs come out as a JSONL event stream on stdout and
/// journal entries in the VM's ops store. Presentation only ever sees
/// this interface — the concrete adapter lives in infrastructure.
abstract class AutomationBackend {
  /// True when the `quickprovision` binary is available on this host.
  Future<bool> checkAvailability();

  /// `quickprovision plan --profile <path>` — resolves the profile against
  /// the catalogue and returns the envelope `data` payload (steps,
  /// provider, resources, warnings). Null when the binary or the
  /// envelope is missing.
  Future<Map<String, dynamic>?> plan(String profilePath);

  /// Starts `quickprovision run --profile <path> --dir <workDir>`. The
  /// caller owns the process: stdout carries the JSONL event stream,
  /// exitCode reports completion and kill() is the last-resort stop
  /// (journal cancel via [cancel] is the clean path).
  Future<RunningProc> startRun(String profilePath, String workDir);

  /// `quickprovision resume --vmdir <vmDir>` — re-enters the newest
  /// unfinished run under the VM's `.quickprovision/` at the first step
  /// that never completed, continuing the same event stream.
  Future<RunningProc> resumeRun(String vmDir);

  /// `quickprovision cancel --vmdir <vmDir> --id <op>` — flags the journal
  /// entry; the runner aborts at the next step boundary and cleans up
  /// its own QEMU.
  Future<ProcResult> cancel(String vmDir, String operationId);
}
