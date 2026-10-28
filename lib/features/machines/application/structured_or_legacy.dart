import 'package:logging/logging.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/core/telemetry/legacy_telemetry.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Runs [command]/[arguments] through the structured `--format json`
/// contract ([VirtualizationBackend.runVmJson]) and returns a synthetic
/// successful [ProcResult] so existing callers that inspect exitCode
/// and output keep working unchanged.
///
/// Falls back to [VirtualizationBackend.runAction] only when the backend
/// cannot produce an envelope at all ([isBackendEnvelopeMissing]) — real
/// contract defects and typed failures propagate as [AppFailure].
Future<ProcResult> runVmActionOrLegacy(
  VirtualizationBackend backend,
  String command,
  List<String> arguments,
) async {
  final sw = Stopwatch()..start();
  try {
    await backend.runVmJson(command, arguments);
    AppLog.event(
      AppLog.backendContract,
      Level.FINE,
      'structured command completed',
      command: command,
      durationMs: sw.elapsedMilliseconds,
      exitCode: 0,
      legacy: false,
    );
    return const ProcResult(0, '', '');
  } on AppFailure catch (e) {
    if (!isBackendEnvelopeMissing(e)) {
      AppLog.event(
        AppLog.backendContract,
        Level.WARNING,
        'structured command failed',
        command: command,
        durationMs: sw.elapsedMilliseconds,
        failureCode: e.code,
        legacy: false,
      );
      rethrow;
    }
    LegacyTelemetry.record(command, e.code);
    final result = await backend.runAction(arguments);
    // Legacy failures reach callers as raw ProcResult — classify the
    // stderr text so telemetry still records a typed code.
    final failureCode = result.exitCode == 0
        ? null
        : _classifyStderr('${result.stderr}');
    AppLog.event(
      AppLog.backendContract,
      result.exitCode == 0 ? Level.FINE : Level.WARNING,
      'legacy command completed',
      command: command,
      durationMs: sw.elapsedMilliseconds,
      exitCode: result.exitCode,
      failureCode: failureCode,
      legacy: true,
    );
    return result;
  }
}

/// Maps raw stderr text to the closest typed failure code — a stopgap
/// for pre-contract backends that report errors as strings.
String _classifyStderr(String stderr) {
  final lower = stderr.toLowerCase();
  if (lower.contains('address already in use') || lower.contains('port')) {
    return 'port_busy';
  }
  if (lower.contains('lock')) return 'lock_busy';
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return 'timeout';
  }
  if (lower.contains('permission denied')) return 'permission_denied';
  if (lower.contains('no such file') || lower.contains('not found')) {
    return 'not_found';
  }
  return 'backend.legacy_error';
}
