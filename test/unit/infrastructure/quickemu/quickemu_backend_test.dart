import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_parser.dart';

/// Fake ProcessRunner recording invocations and returning canned results.
class FakeProcessRunner extends ProcessRunner {
  final Map<String, ProcessResult> responses;
  final List<String> calls = [];
  final List<(String, List<String>)> invocations = [];

  FakeProcessRunner(this.responses);

  String _key(String exe, List<String> args) => '$exe ${args.join(' ')}';

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    calls.add(_key(executable, arguments));
    invocations.add((executable, List.of(arguments)));
    return Future.value(
      responses[_key(executable, arguments)] ??
          ProcessResult(0, 1, '', 'not stubbed'),
    );
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    calls.add(_key(executable, arguments));
    invocations.add((executable, List.of(arguments)));
    throw UnimplementedError();
  }
}

void expectInvocation(
  FakeProcessRunner runner,
  String executable,
  List<String> arguments,
) {
  expect(runner.invocations, hasLength(1));
  expect(runner.invocations.single.$1, executable);
  expect(runner.invocations.single.$2, arguments);
}

void main() {
  final commandCases =
      <(String, List<String>, Future<ProcessResult> Function(QuickemuBackend))>[
        (
          'quickemu',
          ['--vm', 'a b.conf', '--export', 'a b.tar.gz'],
          (b) => b.exportVm('a b'),
        ),
        (
          'quickemu',
          ['--vm', 'a b.conf', '--stop'],
          (b) => b.runAction(['--vm', 'a b.conf', '--stop']),
        ),
        (
          'quickget',
          ['ubuntu', '24.04', 'desktop'],
          (b) => b.runQuickget(['ubuntu', '24.04', 'desktop']),
        ),
        (
          'chunkcheck',
          ['image ; echo bad.iso'],
          (b) => b.verifyImage('image ; echo bad.iso'),
        ),
        ('killall', ['a b'], (b) => b.killVmProcess('a b')),
        (
          Platform.isMacOS ? 'open' : 'xdg-open',
          ['a b'],
          (b) => b.openVmFolder('a b'),
        ),
        (
          'spicy',
          ['-h', '127.0.0.1', '-p', '5930'],
          (b) => b.launchSpiceViewer('5930'),
        ),
        (
          'ssh-keygen',
          ['-R', '[localhost]:2222'],
          (b) => b.forgetSshHostKey('2222'),
        ),
        ('quickreport', [], (b) => b.diagnosticsReport()),
      ];
  for (final (executable, arguments, invoke) in commandCases) {
    test('$executable preserves argument boundaries for $arguments', () async {
      final result = ProcessResult(123, 17, 'output', 'error');
      final runner = FakeProcessRunner({
        '$executable ${arguments.join(' ')}': result,
      });
      expect(await invoke(QuickemuBackend(runner)), same(result));
      expectInvocation(runner, executable, arguments);
    });
  }

  for (final option in ['', 'desktop']) {
    test(
      'download startup forwards option only when present ($option)',
      () async {
        final runner = FakeProcessRunner({});
        await expectLater(
          Future<Process>.sync(
            () =>
                QuickemuBackend(runner)
                    .startDownloadImage('ubuntu', '24.04', option),
          ),
          throwsUnimplementedError,
        );
        expectInvocation(runner, 'quickget', [
          'ubuntu',
          '24.04',
          if (option.isNotEmpty) option,
        ]);
      },
    );
  }

  for (final (terminal, prefix) in <(String, List<String>)>[
    ('gnome-terminal', ['--']),
    ('mate-terminal', ['--']),
    ('kitty', []),
    ('foot', []),
    ('wezterm', ['start']),
    ('alacritty', ['-e']),
    ('xterm', ['-e']),
    ('konsole', ['-e']),
    ('terminator', ['-x']),
    ('xfce4-terminal', ['-x']),
  ]) {
    for (final user in ['', 'alice']) {
      test('SSH uses $terminal convention with user "$user"', () async {
        final runner = FakeProcessRunner({});
        await QuickemuBackend(
          runner,
        ).connectSsh(terminalEmulator: terminal, user: user, sshPort: '2222');
        expectInvocation(runner, 'sh', [
          '-c',
          [
            terminal,
            ...prefix,
            'ssh',
            '-p',
            '2222',
            if (user.isEmpty) 'localhost' else 'alice@localhost',
          ].join(' '),
        ]);
      });
    }
  }

  test('structured catalogue avoids the legacy subprocess', () async {
    final runner = FakeProcessRunner({
      'quickget --list-json': ProcessResult(0, 0, '[]', ''),
    });
    expect(await QuickemuBackend(runner).listOperatingSystems(), isEmpty);
    expect(runner.calls, ['quickget --list-json']);
  });

  group('contract decoder resilience', () {
    for (final payload in ['', '{', 'null', '[]', '42', '"text"']) {
      test('map decoders reject $payload without throwing', () {
        expect(parseCapabilitiesPayload(payload), isNull);
        expect(parseVmStatusPayload(payload), isNull);
      });
    }
    for (final payload in [
      '',
      '{',
      'null',
      '{}',
      '{"vms":42}',
      '{"vms":[1]}',
    ]) {
      test('VM list rejects malformed payload $payload', () {
        expect(parseVmListPayload(payload), isNull);
      });
    }
    test('VM list preserves Unicode names and ordering', () {
      expect(
        parseVmListPayload('{"vms":[{"name":"máquina"},{"name":"a b"}]}'),
        ['máquina', 'a b'],
      );
      expect(parseVmListPayload('{"vms":[]}'), isEmpty);
    });
    for (final payload in ['', '{', 'null', '{}', '[1]']) {
      test('catalogue rejects malformed payload $payload', () {
        expect(parseOsCatalogueJson(payload), isNull);
      });
    }
    test('catalogue JSON decodes wire fields in display order', () {
      expect(
        parseOsCatalogueJson(
          '[{"Display Name":"Ubuntu","OS":"ubuntu","Release":"24.04","Option":"desktop","Downloader":"quickget"}]',
        ),
        [
          ['Ubuntu', 'ubuntu', '24.04', 'desktop', 'quickget'],
        ],
      );
      expect(parseOsCatalogueJson('[]'), isEmpty);
    });
    test('legacy CSV drops header and empty rows', () {
      expect(parseOsCatalogueCsv('name,os\nUbuntu,ubuntu\n\n'), [
        ['Ubuntu', 'ubuntu'],
      ]);
      expect(parseOsCatalogueCsv('name,os\n'), isEmpty);
    });
    test('legacy running status retains VM name and PID', () {
      expect(parseLegacyVmStatus('a b', ' running 42\n'), {
        'name': 'a b',
        'state': 'running',
        'pid': 42,
      });
    });
    test('legacy stopped status has no PID', () {
      expect(parseLegacyVmStatus('vm', 'stopped'), {
        'name': 'vm',
        'state': 'stopped',
        'pid': null,
      });
    });
  });

  for (final available in [true, false]) {
    test('availability requires both executables ($available)', () async {
      final runner = FakeProcessRunner({
        'quickget --version': ProcessResult(0, 0, '1', ''),
        'quickemu --version': ProcessResult(0, available ? 0 : 1, ' 4.9\n', ''),
      });
      final backend = QuickemuBackend(runner);
      expect(await backend.checkAvailability(), available);
      expect(await backend.version(), available ? '4.9' : '');
      expect(runner.calls.take(2), [
        'quickget --version',
        'quickemu --version',
      ]);
    });
  }

  test('catalogue falls back to CSV when JSON is corrupt', () async {
    final runner = FakeProcessRunner({
      'quickget --list-json': ProcessResult(0, 0, '{', ''),
      'quickget --list-csv': ProcessResult(
        0,
        0,
        'name,os\nUbuntu,ubuntu\n',
        '',
      ),
    });
    expect(await QuickemuBackend(runner).listOperatingSystems(), [
      ['Ubuntu', 'ubuntu'],
    ]);
    expect(runner.calls, ['quickget --list-json', 'quickget --list-csv']);
  });

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
