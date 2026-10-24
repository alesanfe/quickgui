import 'dart:io';

/// Where the app is allowed to read/write VM artefacts.
class PathPolicy {
  static String get vmRoot => Directory.current.path;
  static bool isInsideVmDir(String path) => path.startsWith(vmRoot);
}
