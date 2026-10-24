import 'dart:io';

/// Finds executables on PATH (used to detect missing backends/tools).
class ExecutableLocator {
  static bool exists(String name) =>
      Process.runSync('which', [name]).exitCode == 0;
}
