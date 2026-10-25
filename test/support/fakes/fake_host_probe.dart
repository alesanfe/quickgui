import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';

class FakeHostProbe implements HostProbe {
  Set<String> tools = {'quickemu', 'quickget', 'qemu-img'};
  bool kvm = true;
  String dir = '/home/tester/vms';
  int? free = 50 * 1024 * 1024 * 1024;

  @override
  Future<bool> hasTool(String name) async => tools.contains(name);
  @override
  Future<bool> hasKvm() async => kvm;
  @override
  Future<String> workingDirectory() async => dir;
  @override
  Future<int?> freeSpaceBytes(String directory) async => free;
  @override
  String get homeDirectory => '/home/tester';
  @override
  String get appVersion => '1.2.3';

  bool writable = true;
  String? terminal;
  String fallbackDir = '/home/tester';
  List<String> missingMacos = const [];

  @override
  Future<bool> canWriteToDirectory(String path) async => writable;
  @override
  String get fallbackWorkingDirectory => fallbackDir;
  @override
  Future<String?> terminalEmulator() async => terminal;
  @override
  Future<List<String>> missingMacosRequirements(String release) async =>
      missingMacos;

  Set<int> alivePids = const {};

  @override
  Future<bool> isPidAlive(int pid) async => alivePids.contains(pid);
}
