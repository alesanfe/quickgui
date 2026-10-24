import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: list the VMs known to the backend (structured when the
/// backend supports it, directory scan otherwise).
class ListVms {
  ListVms(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<List<String>>> call() async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    return Ok(await _backend.listVirtualMachines());
  }
}
