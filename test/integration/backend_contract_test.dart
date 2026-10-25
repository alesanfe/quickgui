import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';

import '../support/fakes/fake_process_runner.dart';

/// Integration test: full infrastructure chain (backend -> process ->
/// contract args -> parser) driven by real schema-v1 fixtures.
void main() {
  test('backend consumes the v1 contract end to end', () async {
    final runner = FakeProcessRunner();
    runner.results['quickemu'] = ProcessResult(
      0,
      0,
      '{"schemaVersion":1,"command":"list-vms","success":true,'
          '"data":{"vms":[{"name":"ubuntu-24.04"},{"name":"win11"}]},'
          '"warnings":[],"errors":[],'
          '"meta":{"quickemuVersion":"4.9.9",'
          '"timestamp":"2026-01-01T00:00:00Z"}}',
      '',
    );
    final backend = QuickemuBackend(runner);

    expect(await backend.listVirtualMachines(), ['ubuntu-24.04', 'win11']);
    expect(runner.calls.last, ['quickemu', '--list-vms', '--format', 'json']);
  });

  test('falls back to legacy text status on non-json output', () async {
    final runner = FakeProcessRunner();
    runner.results['quickemu'] = ProcessResult(0, 0, 'running 4242', '');
    final backend = QuickemuBackend(runner);

    final status = await backend.inspectVirtualMachine('ubuntu-24.04');
    expect(status['state'], 'running');
    expect(status['pid'], 4242);
  });
}
