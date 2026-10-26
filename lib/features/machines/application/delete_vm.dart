import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/core/telemetry/legacy_telemetry.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';

/// Result of `--delete-plan`: the files that would be removed plus the
/// `planId` the backend expects to verify the follow-up `--delete-vm`.
typedef DeletePlan = ({List<String> files, String? planId});

/// Use case: safe delete — the plan is shown BEFORE anything is removed.
class DeleteVm {
  DeleteVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<DeletePlan>> plan(String vm) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    try {
      final data = await _backend.runVmJson('delete-plan', [
        '--vm',
        '$vm.conf',
        '--delete-plan',
      ]);
      final files = data['delete'] ?? data['plan'] ?? data['files'];
      if (files is List) {
        return Ok((
          files: [for (final f in files) '$f'],
          planId: data['planId'] as String?,
        ));
      }
      return const Err(
        Failure('vm.delete_plan_failed', 'Unexpected delete-plan payload'),
      );
    } on AppFailure catch (e) {
      // A pre-contract quickemu cannot answer the envelope at all —
      // fall back to the line-oriented plan output; real contract
      // defects still surface as typed failures.
      if (!isBackendEnvelopeMissing(e)) {
        return Err(Failure('vm.delete_plan_failed', e.userMessage));
      }
      LegacyTelemetry.record('delete-plan', e.code);
      final r = await _backend.runAction([
        '--vm',
        '$vm.conf',
        '--delete-plan',
        '--format',
        'json',
      ]);
      if (r.exitCode != 0) {
        return Err(
          Failure('vm.delete_plan_failed', '${r.stderr}${r.stdout}'.trim()),
        );
      }
      return Ok((
        files: [...'${r.stdout}'.split('\n')..removeWhere((f) => f.isEmpty)],
        planId: null,
      ));
    }
  }

  Future<Result<void>> call(
    String vm, {
    bool diskOnly = false,
    String? planId,
  }) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final args = [
      '--vm',
      '$vm.conf',
      if (diskOnly) '--delete-disk' else '--delete-vm',
      // A planId from --delete-plan makes the backend verify the file
      // set has not changed since the plan was shown to the user.
      if (planId != null && planId.isNotEmpty) ...['--plan-id', planId],
    ];
    try {
      final r = await runVmActionOrLegacy(
        _backend,
        diskOnly ? 'delete-disk' : 'delete-vm',
        args,
      );
      if (r.exitCode != 0) {
        return Err(
          Failure('vm.delete_failed', '${r.stderr}${r.stdout}'.trim()),
        );
      }
      return const Ok(null);
    } on AppFailure catch (e) {
      return Err(Failure('vm.delete_failed', e.userMessage));
    }
  }
}
