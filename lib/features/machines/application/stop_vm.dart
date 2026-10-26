import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';

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
      final r = await runVmActionOrLegacy(_backend, 'kill', [
        '--vm',
        '$vm.conf',
        ...args,
      ]);
      if (r.exitCode != 0) {
        return Err(Failure('vm.stop_failed', '${r.stderr}${r.stdout}'.trim()));
      }
      return const Ok(null);
    } on AppFailure catch (e) {
      return Err(Failure('vm.stop_failed', e.userMessage));
    }
  }
}
