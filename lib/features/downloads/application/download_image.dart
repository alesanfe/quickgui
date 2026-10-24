import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: download an OS image via `quickget` (streaming output).
class DownloadImage {
  DownloadImage(this._backend);
  final VirtualizationBackend _backend;

  Stream<String> lines(String os, String release, String option) =>
      _backend.downloadImage(os, release, option);

  Future<Result<void>> call(
    String os,
    String release, [
    String option = '',
  ]) async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    final r = await _backend.runQuickget([
      os,
      release,
      if (option.isNotEmpty) option,
    ]);
    if (r.exitCode != 0) {
      return Err(Failure('download.failed', '${r.stderr}${r.stdout}'.trim()));
    }
    return const Ok(null);
  }
}
