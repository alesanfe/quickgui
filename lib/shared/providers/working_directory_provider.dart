import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// The VMs working directory — single source of truth for UI and
/// provider path reads (QGUI-M-005).
///
/// `Directory.current` is still applied, but ONLY inside this
/// notifier: spawned backend processes resolve relative paths against
/// the process cwd, so it must keep tracking the chosen directory.
/// Everything else must read this provider (a plain path string that
/// never throws) so a deleted cwd cannot cascade into unrelated code.
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
      // (callers guard with existsSync) until apply() repairs it.
      return '';
    }
  }

  /// Applies a resolved directory without persisting it — startup
  /// resolution (the pref is already stored, or a non-sticky probe
  /// fallback).
  void apply(String dir) {
    if (dir.isEmpty || dir == state) return;
    Directory.current = dir;
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
