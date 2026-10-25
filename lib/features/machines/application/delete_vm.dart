import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: safe delete — the plan is shown BEFORE anything is removed.
class DeleteVm {
  DeleteVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<List<String>>> plan(String vm) async {
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
      final files = data['plan'] ?? data['files'];
      if (files is List) return Ok([for (final f in files) '$f']);
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
      return Ok([...'${r.stdout}'.split('\n')..removeWhere((f) => f.isEmpty)]);
    }
  }

  Future<Result<void>> call(String vm, {bool diskOnly = false}) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final args = [
      '--vm',
      '$vm.conf',
      if (diskOnly) '--delete-disk' else '--delete-vm',
    ];
    try {
      await _backend.runVmJson(diskOnly ? 'delete-disk' : 'delete-vm', args);
      return const Ok(null);
    } on AppFailure catch (e) {
      if (!isBackendEnvelopeMissing(e)) {
        return Err(Failure('vm.delete_failed', e.userMessage));
      }
      final r = await _backend.runAction(args);
      if (r.exitCode != 0) {
        return Err(
          Failure('vm.delete_failed', '${r.stderr}${r.stdout}'.trim()),
        );
      }
      return const Ok(null);
    }
  }
}
