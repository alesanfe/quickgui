import '../../domain/common/result.dart';
import '../../infrastructure/virtualization/virtualization_backend.dart';

/// Use case: structured state of a single VM.
class InspectVm {
  InspectVm(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<Map<String, dynamic>>> call(String vm) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    return Ok(await _backend.inspectVirtualMachine(vm));
  }
}
