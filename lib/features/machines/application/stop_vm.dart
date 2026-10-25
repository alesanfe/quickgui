import 'package:quickgui/core/errors/app_failure.dart';
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
    const args = ['--kill'];
    try {
      await _backend.runVmJson('kill', ['--vm', '$vm.conf', ...args]);
      return const Ok(null);
    } on AppFailure catch (e) {
      if (!isBackendEnvelopeMissing(e)) {
        return Err(Failure('vm.stop_failed', e.userMessage));
      }
      final r = await _backend.runAction(['--vm', '$vm.conf', ...args]);
      if (r.exitCode != 0) {
        return Err(Failure('vm.stop_failed', '${r.stderr}${r.stdout}'.trim()));
      }
      return const Ok(null);
    }
  }
}
