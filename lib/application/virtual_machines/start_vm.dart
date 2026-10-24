import '../../domain/common/result.dart';
import '../../infrastructure/virtualization/virtualization_backend.dart';

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
    final r = await _backend.runAction([
      '--vm',
      '$vm.conf',
      if (display != null && display.isNotEmpty) ...['--display', display],
    ]);
    if (r.exitCode != 0) {
      return Err(Failure('vm.start_failed', '${r.stderr}${r.stdout}'.trim()));
    }
    return const Ok(null);
  }
}
