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
    return Ok([...'${r.stdout}'.split('\n')..removeWhere((e) => e.isEmpty)]);
  }

  Future<Result<void>> call(String vm, {bool diskOnly = false}) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final r = await _backend.runAction([
      '--vm',
      '$vm.conf',
      if (diskOnly) '--delete-disk' else '--delete-vm',
    ]);
    if (r.exitCode != 0) {
      return Err(Failure('vm.delete_failed', '${r.stderr}${r.stdout}'.trim()));
    }
    return const Ok(null);
  }
}
