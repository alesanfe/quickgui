import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: collect backend diagnostics for the diagnostics page.
class CollectDiagnostics {
  CollectDiagnostics(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<Map<String, dynamic>>> call() async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    return Ok({'capabilities': await _backend.getCapabilities()});
  }
}
