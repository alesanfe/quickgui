import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// The VMs working directory — single source of truth for UI and
/// provider path reads (QGUI-M-005).
///
/// This provider does NOT mutate `Directory.current`: spawned backend
/// processes receive the directory explicitly via `ProcessRunner`'s
/// `workingDirectory` parameter, and file IO resolves through this
/// provider or `VmConfigFileStore`'s injected baseDir. Everything must
/// read this provider (a plain path string that never throws) so a
/// deleted cwd cannot cascade into unrelated code.
final workingDirectoryProvider = NotifierProvider<WorkingDirectory, String>(
  WorkingDirectory.new,
);

class WorkingDirectory extends Notifier<String> {
  @override
  String build() {
    try {
      return Directory.current.path;
    } on FileSystemException {
      // The process cwd was deleted under us — report an empty root
      // (callers guard with existsSync) until apply() is called.
      return '';
    }
  }

  /// Applies a resolved directory without persisting it — startup
  /// resolution (the pref is already stored, or a non-sticky probe
  /// fallback). State only: the process cwd is intentionally left
  /// untouched.
  void apply(String dir) {
    if (dir.isEmpty || dir == state) return;
    state = dir;
  }

  /// User-chosen directory: applies and persists the pref atomically.
  Future<void> set(String dir) async {
    apply(dir);
    await ref
        .read(preferencesRepositoryProvider)
        .set(prefWorkingDirectory, dir);
  }
}
