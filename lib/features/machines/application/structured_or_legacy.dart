import 'dart:io';

import 'package:quickgui/core/errors/app_failure.dart';
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
  try {
    await backend.runVmJson(command, arguments);
    return ProcessResult(0, 0, '', '');
  } on AppFailure catch (e) {
    if (!isBackendEnvelopeMissing(e)) rethrow;
    LegacyTelemetry.record(command, e.code);
    return await backend.runAction(arguments);
  }
}
