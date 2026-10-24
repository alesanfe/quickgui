/// A managed virtual machine as known to the presentation layer.
class VirtualMachine {
  const VirtualMachine(this.name, {this.guestOs, this.state = 'stopped'});
  final String name;
  final String? guestOs;
  final String state;
  bool get isRunning => state == 'running';
}
