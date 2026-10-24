import 'dart:io';

import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: start an OS image download via `quickget`. Returns the
/// running process so callers can stream its output, await completion
/// or cancel it.
class DownloadImage {
  DownloadImage(this._backend);
  final VirtualizationBackend _backend;

  Future<Process> call(String os, String release, [String option = '']) =>
      _backend.startDownloadImage(os, release, option);
}
