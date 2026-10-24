import 'dart:io';

/// Thin filesystem wrapper for testability.
class SystemFilesystem {
  bool fileExists(String p) => File(p).existsSync();
  bool dirExists(String p) => Directory(p).existsSync();
  Stream<FileSystemEntity> list(String p) => Directory(p).list();
}
