import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: create a VM by downloading an OS image.
class CreateVm {
  CreateVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<void>> call(String os, String release, [String? option]) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final r = await _backend.runQuickget([
      os,
      release,
      if (option != null && option.isNotEmpty) option,
    ]);
    if (r.exitCode != 0) {
      return Err(Failure('vm.create_failed', '${r.stderr}${r.stdout}'.trim()));
    }
    return const Ok(null);
  }
}
