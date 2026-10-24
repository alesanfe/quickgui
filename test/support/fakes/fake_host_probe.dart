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
}
