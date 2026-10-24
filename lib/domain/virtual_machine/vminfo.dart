/// Store info about a running vm, such as connection ports.
class VmInfo {
  String? sshPort;
  String? spicePort;
  final List<String> other = [];
}
