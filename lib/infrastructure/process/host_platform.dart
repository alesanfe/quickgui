import 'dart:io';

/// Host OS facts for conditional behaviour.
class HostPlatform {
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isFlatpak =>
      File('/.flatpak-info').existsSync() ||
      Platform.environment.containsKey('FLATPAK_ID');
}

/// Returns true if a temporary file can be created in [path].
bool isWritableDirectory(String path) {
  try {
    final probe = Directory(path).createTempSync('.quickgui-write-');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// A sensible writable fallback for the working directory. The app can be
/// started from a read-only location (e.g. an AppImage mount point).
String fallbackWorkingDirectory() {
  return Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
}
