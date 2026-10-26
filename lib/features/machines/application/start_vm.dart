import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';

/// Use case: start a VM, optionally with a display override.
class StartVm {
  StartVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<void>> call(String vm, {String? display}) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final args = [
      '--vm',
      '$vm.conf',
      if (display != null && display.isNotEmpty) ...['--display', display],
    ];
    try {
      final r = await runVmActionOrLegacy(_backend, 'start', args);
      if (r.exitCode != 0) {
        return Err(Failure('vm.start_failed', '${r.stderr}${r.stdout}'.trim()));
      }
      return const Ok(null);
    } on AppFailure catch (e) {
      return Err(Failure('vm.start_failed', e.userMessage));
    }
  }
}
