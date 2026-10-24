import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/virtualization/quickemu_backend.dart';

/// Fake ProcessRunner recording invocations and returning canned results.
class FakeProcessRunner extends ProcessRunner {
  final Map<String, ProcessResult> responses;
  final List<String> calls = [];

  FakeProcessRunner(this.responses);

  String _key(String exe, List<String> args) => '$exe ${args.join(' ')}';

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add(_key(executable, arguments));
    return Future.value(
      responses[_key(executable, arguments)] ??
          ProcessResult(0, 1, '', 'not stubbed'),
    );
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    calls.add(_key(executable, arguments));
    throw UnimplementedError();
  }
}

void main() {
  test('parses capabilities descriptor', () async {
    final runner = FakeProcessRunner({
      'quickemu --capabilities': ProcessResult(
        0,
        0,
        '{"schemaVersion":1,"applicationVersion":"4.9.9",'
            '"capabilities":{"structuredStatus":true}}',
        '',
      ),
    });
    final caps = await QuickemuBackend(runner).getCapabilities();
    expect(caps?['schemaVersion'], 1);
    expect(caps?['capabilities']['structuredStatus'], isTrue);
  });

  test('getCapabilities returns null on older quickemu', () async {
    final backend = QuickemuBackend(FakeProcessRunner({}));
    expect(await backend.getCapabilities(), isNull);
  });

  test('inspectVirtualMachine parses JSON status', () async {
    final runner = FakeProcessRunner({
      'quickemu --vm vm1.conf --status --format json': ProcessResult(
        0,
        0,
        '{"schemaVersion":1,"name":"vm1","state":"running","pid":42}',
        '',
      ),
    });
    final s = await QuickemuBackend(runner).inspectVirtualMachine('vm1');
    expect(s['state'], 'running');
    expect(s['pid'], 42);
  });

  test('inspectVirtualMachine falls back to text status', () async {
    final runner = FakeProcessRunner({
      'quickemu --vm vm1.conf --status --format json': ProcessResult(
        0,
        0,
        'stopped',
        '',
      ),
    });
    final s = await QuickemuBackend(runner).inspectVirtualMachine('vm1');
    expect(s['state'], 'stopped');
  });

  test('listVirtualMachines prefers JSON list', () async {
    final runner = FakeProcessRunner({
      'quickemu --list-vms --format json': ProcessResult(
        0,
        0,
        '{"schemaVersion":1,"vms":[{"name":"a","guest_os":"linux",'
            '"state":"stopped","pid":null}]}',
        '',
      ),
    });
    expect(await QuickemuBackend(runner).listVirtualMachines(), ['a']);
  });
}
