import '../../domain/common/result.dart';
import '../../infrastructure/virtualization/virtualization_backend.dart';

/// Use case: load the OS catalogue (structured JSON, CSV fallback).
/// Returns raw rows [displayName, os, release, option, downloader].
class LoadCatalog {
  LoadCatalog(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<List<List<String>>>> call() async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    return Ok(await _backend.listOperatingSystems());
  }
}
