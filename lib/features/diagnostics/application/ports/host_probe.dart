/// Port for host facts the diagnostics use case needs; implemented in
/// infrastructure, faked in tests.
abstract class HostProbe {
  Future<bool> hasTool(String name);
  Future<bool> hasKvm();
  Future<String> workingDirectory();
  Future<int?> freeSpaceBytes(String directory);
  String get homeDirectory;
  String get appVersion;

  /// Whether the app can create files in [path].
  Future<bool> canWriteToDirectory(String path);

  /// A writable directory to fall back to when the current one is
  /// read-only (e.g. an AppImage mount point).
  String get fallbackWorkingDirectory;

  /// The detected terminal emulator, or null when none of the supported
  /// ones is installed.
  Future<String?> terminalEmulator();

  /// Host CPU/OS requirements missing to run the macOS [release] guest.
  /// Empty when the host satisfies them or cannot be determined.
  Future<List<String>> missingMacosRequirements(String release);
}
