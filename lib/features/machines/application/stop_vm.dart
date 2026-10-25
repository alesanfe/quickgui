import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: stop a running VM.
class StopVm {
  StopVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<void>> call(String vm) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final r = await _backend.runAction(['--vm', '$vm.conf', '--kill']);
    if (r.exitCode != 0) {
      return Err(Failure('vm.stop_failed', '${r.stderr}${r.stdout}'.trim()));
    }
    return const Ok(null);
  }
}
