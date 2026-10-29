import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_parser.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';

/// Fake ProcessRunner recording invocations and returning canned results.
class FakeProcessRunner extends ProcessRunner {
  final Map<String, ProcessResult> responses;
  final List<String> calls = [];
  final List<(String, List<String>)> invocations = [];

  FakeProcessRunner(this.responses, {this.processExceptionOnStart = false});

  /// When true, `start` throws a real `ProcessException` (the failure
  /// mode `watchOperations` degrades on) instead of `UnimplementedError`.
  final bool processExceptionOnStart;

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
    if (processExceptionOnStart) {
      throw ProcessException(executable, arguments);
    }
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
      <(String, List<String>, Future<ProcResult> Function(QuickemuBackend))>[
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
      final r = await invoke(QuickemuBackend(runner));
      expect(r.exitCode, result.exitCode);
      expect(r.stdout, result.stdout);
      expect(r.stderr, result.stderr);
      expectInvocation(runner, executable, arguments);
    });
  }

  group('exportVm contract path', () {
    test('structured envelope preserves argument boundaries', () async {
      final runner = FakeProcessRunner({
        'quickemu --vm a b.conf --export a b.tar.gz --format json':
            ProcessResult(
              0,
              0,
              '{"schemaVersion":1,"command":"vm.export","success":true,"data":{"export":"a b.tar.gz"},"warnings":[],"errors":[],"meta":{}}',
              '',
            ),
      });
      final r = await QuickemuBackend(runner).exportVm('a b');
      expect(r.exitCode, 0);
      expectInvocation(runner, 'quickemu', [
        '--vm',
        'a b.conf',
        '--export',
        'a b.tar.gz',
        '--format',
        'json',
      ]);
    });

    test('pre-contract backend falls back to the raw argv', () async {
      final raw = ProcessResult(123, 17, 'done', '');
      final runner = FakeProcessRunner({
        // Empty stdout on the envelope attempt = no contract support.
        'quickemu --vm a b.conf --export a b.tar.gz --format json':
            ProcessResult(0, 0, '', ''),
        'quickemu --vm a b.conf --export a b.tar.gz': raw,
      });
      final r = await QuickemuBackend(runner).exportVm('a b');
      expect(r.exitCode, raw.exitCode);
      expect(r.stdout, raw.stdout);
      expect(r.stderr, raw.stderr);
      expect(runner.invocations.last.$2, [
        '--vm',
        'a b.conf',
        '--export',
        'a b.tar.gz',
      ]);
    });
  });

  for (final option in ['', 'desktop']) {
    test(
      'download startup forwards option only when present ($option)',
      () async {
        final runner = FakeProcessRunner({});
        await expectLater(
          Future<RunningProc>.sync(
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

  // sshPort lands inside a `sh -c` command string — a non-numeric port
  // from a hostile .ports file would inject shell commands. The sink
  // must reject it before the terminal invocation is even built.
  for (final badPort in [
    '2222;touch /tmp/x',
    '22 -oProxyCommand=x',
    '',
    'port',
  ]) {
    test('connectSsh rejects port "$badPort" before the shell', () async {
      final runner = FakeProcessRunner({});
      final r = await QuickemuBackend(
        runner,
      ).connectSsh(terminalEmulator: 'xterm', user: 'alice', sshPort: badPort);
      expect(r.exitCode, isNot(0));
      expect(runner.calls, isEmpty, reason: 'port must never reach sh -c');
    });
  }

  test('forgetSshHostKey rejects a non-numeric port', () async {
    final runner = FakeProcessRunner({});
    final r = await QuickemuBackend(runner).forgetSshHostKey('22 -F /etc/x');
    expect(r.exitCode, isNot(0));
    expect(runner.calls, isEmpty);
  });

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
        '{"schemaVersion":1,"command":"capabilities","success":true,'
            '"data":{"schemaVersion":1,"applicationVersion":"4.9.9",'
            '"capabilities":{"structuredStatus":true}},'
            '"warnings":[],"errors":[],'
            '"meta":{"quickemuVersion":"4.9.9",'
            '"timestamp":"2026-01-01T00:00:00Z"}}',
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
        '{"schemaVersion":1,"command":"status","success":true,'
            '"data":{"name":"vm1","state":"running","pid":42},'
            '"warnings":[],"errors":[],'
            '"meta":{"quickemuVersion":"4.9.9",'
            '"timestamp":"2026-01-01T00:00:00Z"}}',
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
        '{"schemaVersion":1,"command":"list-vms","success":true,'
            '"data":{"vms":[{"name":"a","guest_os":"linux",'
            '"state":"stopped","pid":null}]},'
            '"warnings":[],"errors":[],'
            '"meta":{"quickemuVersion":"4.9.9",'
            '"timestamp":"2026-01-01T00:00:00Z"}}',
        '',
      ),
    });
    expect(await QuickemuBackend(runner).listVirtualMachines(), ['a']);
  });

  group('structured method argv coverage', () {
    // Every VirtualizationBackend method that translates to a structured
    // v1 command must emit the documented argv (boundary contract).
    String envelope(String command, [String data = '{}']) =>
        '{"schemaVersion":1,"command":"$command","success":true,'
        '"data":$data,"warnings":[],"errors":[],'
        '"meta":{"quickemuVersion":"5.0.0","timestamp":"t"}}';

    final cases =
        <
          (
            String,
            List<String>,
            String,
            Future<dynamic> Function(QuickemuBackend),
          )
        >[
          (
            'trash-restore',
            ['--trash-restore', 'vm1'],
            'vm.trash-restore',
            (b) => b.restoreFromTrash('vm1'),
          ),
          (
            'trash-list',
            ['--trash-list'],
            'vm.trash-list',
            (b) => b.listTrash(),
          ),
          (
            'events',
            ['--vm', 'vm1.conf', '--events', '3'],
            'vm.events',
            (b) => b.readEvents('vm1', cursor: 3),
          ),
          (
            'backup-list',
            ['--vm', 'vm1.conf', '--backup-list'],
            'vm.backup-list',
            (b) => b.listBackups('vm1'),
          ),
          (
            'backup',
            ['--vm', 'vm1.conf', '--backup'],
            'vm.backup',
            (b) => b.createBackup('vm1'),
          ),
          (
            'backup-restore',
            ['--vm', 'vm1.conf', '--backup-restore', 'b.tar.gz'],
            'vm.backup-restore',
            (b) => b.restoreBackup('vm1', 'b.tar.gz'),
          ),
          (
            'backup-prune',
            ['--vm', 'vm1.conf', '--backup-prune', '3'],
            'vm.backup-prune',
            (b) => b.pruneBackups('vm1', keep: 3),
          ),
          (
            'hotplug',
            ['--vm', 'vm1.conf', '--hotplug-usb', '1:2'],
            'vm.hotplug',
            (b) => b.hotplugUsb('vm1.conf', '1:2'),
          ),
          (
            'hotplug',
            ['--vm', 'vm1.conf', '--hotplug-disk', 'd.qcow2'],
            'vm.hotplug',
            (b) => b.hotplugDisk('vm1.conf', 'd.qcow2'),
          ),
          (
            'disk-compact',
            ['--vm', 'vm1.conf', '--disk-compact'],
            'vm.disk-compact',
            (b) => b.diskCompact('vm1.conf'),
          ),
          ('vfio-scan', ['--vfio-scan'], 'host.vfio-scan', (b) => b.vfioScan()),
          (
            'move',
            ['--vm', 'vm1.conf', '--move', '/dst'],
            'vm.move',
            (b) => b.moveVm('vm1.conf', '/dst'),
          ),
          (
            'rename',
            ['--vm', 'vm1.conf', '--rename', 'new'],
            'vm.rename',
            (b) => b.renameVm('vm1.conf', 'new'),
          ),
          (
            'migrate-conf',
            ['--vm', 'vm1.conf', '--migrate-conf'],
            'vm.migrate-conf',
            (b) => b.migrateConfToToml('vm1.conf'),
          ),
          ('host-info', ['--host-info'], 'host-info', (b) => b.hostInfo()),
          (
            'op-list',
            ['--vm', 'vm1.conf', '--op-list'],
            'vm.op-list',
            (b) => b.listOperations('vm1'),
          ),
          (
            'op-cancel',
            ['--vm', 'vm1.conf', '--op-cancel', 'op-9'],
            'vm.op-cancel',
            (b) => b.cancelOperation('vm1', 'op-9'),
          ),
          (
            'op-status',
            ['--vm', 'vm1.conf', '--op-status', 'op-1'],
            'vm.op-status',
            (b) => b.operationStatus('vm1', 'op-1'),
          ),
          (
            'stats',
            ['--vm', 'vm1.conf', '--stats'],
            'vm.stats',
            (b) => b.vmStats('vm1'),
          ),
          (
            'inventory',
            ['--inventory'],
            'vm.inventory',
            (b) => b.listInventory(),
          ),
          (
            'linked-clone',
            ['--vm', 'vm1.conf', '--linked-clone', 'dst'],
            'vm.linked-clone',
            (b) => b.linkedClone('vm1', 'dst'),
          ),
          (
            'profile',
            ['--vm', 'vm1.conf', '--profile', 'dev'],
            'vm.profile',
            (b) => b.startWithProfile('vm1', 'dev'),
          ),
          ('plugins', ['--plugins'], 'host.plugins', (b) => b.listPlugins()),
        ];

    for (final (command, args, envelopeCmd, invoke) in cases) {
      test('$command emits $args', () async {
        final argv = [...args, '--format', 'json'];
        final runner = FakeProcessRunner({
          'quickemu ${argv.join(' ')}': ProcessResult(
            0,
            0,
            envelope(envelopeCmd),
            '',
          ),
        });
        await invoke(QuickemuBackend(runner));
        expectInvocation(runner, 'quickemu', argv);
      });
    }

    test(
      'watchOperations spawns --op-watch and degrades on spawn failure',
      () async {
        final runner = FakeProcessRunner({}, processExceptionOnStart: true);
        final events = await QuickemuBackend(runner)
            .watchOperations('vm1')
            .toList();
        expect(events, isEmpty);
        expectInvocation(runner, 'quickemu', [
          '--vm',
          'vm1.conf',
          '--op-watch',
          '--format',
          'json',
        ]);
      },
    );
  });
}
