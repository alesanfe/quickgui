import '../../domain/common/result.dart';
import '../../infrastructure/virtualization/virtualization_backend.dart';

/// Use case: resolve download options for an OS release via `quickget`.
class ResolveRelease {
  ResolveRelease(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<List<String>>> call(String os, String release) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final r = await _backend.runQuickget(['--list-csv']);
    if (r.exitCode != 0) {
      return Err(
        Failure('catalog.resolve_failed', '${r.stderr}${r.stdout}'.trim()),
      );
    }
    final names = '${r.stdout}'
        .split('\n')
        .skip(1)
        .map((l) => l.split(','))
        .where((c) => c.length > 2 && c[1] == os && c[2] == release)
        .map((c) => c.length > 3 ? c[3] : '')
        .where((o) => o.isNotEmpty)
        .toList();
    return Ok(names);
  }
}
