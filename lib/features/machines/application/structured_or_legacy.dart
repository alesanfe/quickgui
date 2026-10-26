import 'dart:io';

import 'package:logging/logging.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/core/telemetry/legacy_telemetry.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Runs [command]/[arguments] through the structured `--format json`
/// contract ([VirtualizationBackend.runVmJson]) and returns a synthetic
/// successful [ProcessResult] so existing callers that inspect exitCode
/// and output keep working unchanged.
///
/// Falls back to [VirtualizationBackend.runAction] only when the backend
/// cannot produce an envelope at all ([isBackendEnvelopeMissing]) — real
/// contract defects and typed failures propagate as [AppFailure].
Future<ProcessResult> runVmActionOrLegacy(
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
    return ProcessResult(0, 0, '', '');
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
    AppLog.event(
      AppLog.backendContract,
      Level.FINE,
      'legacy command completed',
      command: command,
      durationMs: sw.elapsedMilliseconds,
      exitCode: result.exitCode,
      legacy: true,
    );
    return result;
  }
}
