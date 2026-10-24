/// Port for host facts the diagnostics use case needs; implemented in
/// infrastructure, faked in tests.
abstract class HostProbe {
  Future<bool> hasTool(String name);
  Future<bool> hasKvm();
  Future<String> workingDirectory();
  Future<int?> freeSpaceBytes(String directory);
  String get homeDirectory;
  String get appVersion;
}
