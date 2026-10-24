import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/virtual_machine.dart';
import 'package:quickgui/features/machines/domain/vm_status.dart';

void main() {
  const dir = 'test/support/fixtures/backend-responses/quickqemu-v1';

  test('parses the vm-status v1 fixture', () {
    final json = jsonDecode(
      File('$dir/vm-status.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final vm = VirtualMachine.fromJson(json);
    expect(
      vm,
      const VirtualMachine(name: 'vm1', status: VmStatus.running, pid: 42),
    );
    expect(vm.isRunning, isTrue);
  });

  test('parses a vm-list v1 item with guest_os and stale state', () {
    final vm = VirtualMachine.fromJson({
      'name': 'win11',
      'guest_os': 'windows',
      'state': 'stale',
      'pid': null,
    });
    expect(vm.guestOs, 'windows');
    expect(vm.status, VmStatus.stale);
    expect(vm.isRunning, isFalse);
  });

  test('unknown states map to VmStatus.unknown instead of throwing', () {
    final vm = VirtualMachine.fromJson({'name': 'x', 'state': 'hibernating'});
    expect(vm.status, VmStatus.unknown);
  });

  test('round-trips through JSON using wire names', () {
    const vm = VirtualMachine(
      name: 'a',
      guestOs: 'linux',
      status: VmStatus.stopped,
    );
    final json = vm.toJson();
    expect(json['guest_os'], 'linux');
    expect(json['state'], 'stopped');
    expect(VirtualMachine.fromJson(json), vm);
  });
}
