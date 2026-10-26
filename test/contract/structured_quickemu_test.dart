import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_process.dart';
import 'package:quickgui/infrastructure/quickemu/structured_quickemu.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.result, {this.delay});
  ProcessResult result;
  Duration? delay;
  List<String>? lastArgs;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) {
    lastArgs = arguments;
    final d = delay;
    return d == null ? Future.value(result) : Future.delayed(d, () => result);
  }

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      throw UnimplementedError();
}

String _envelope({
  bool success = true,
  String data = '{}',
  String errors = '[]',
  String command = 'status',
}) =>
    '{"schemaVersion":1,"command":"$command","success":$success,'
    '"data":$data,"warnings":[],"errors":$errors,'
    '"meta":{"quickemuVersion":"4.9.9","timestamp":"2026-01-01T00:00:00Z"}}';

StructuredQuickemu _exec(ProcessResult r) =>
    StructuredQuickemu(QuickemuProcess(_FakeRunner(r)));

void main() {
  group('StructuredQuickemu coherence', () {
    test('exit 0 + success true returns envelope', () async {
      final r = await _exec(ProcessResult(1, 0, _envelope(), ''))
          .run('status', []);
      expect(r.success, isTrue);
    });

    test('adds --format json automatically', () async {
      final runner = _FakeRunner(ProcessResult(1, 0, _envelope(), ''));
      await StructuredQuickemu(QuickemuProcess(runner))
          .run('status', ['--vm', 'x.conf']);
      expect(runner.lastArgs, containsAll(['--format', 'json']));
    });

    test('exit !=0 + success false throws structured failure', () async {
      try {
        await _exec(
          ProcessResult(
            1,
            2,
            _envelope(
              success: false,
              errors:
                  '[{"code":"VM_NOT_FOUND","message":"nope",'
                  '"severity":"error","retryable":false}]',
            ),
            '',
          ),
        ).run('status', []);
        fail('expected AppFailure');
      } on AppFailure catch (e) {
        expect(e.code, 'VM_NOT_FOUND');
        expect(e.kind, AppFailureKind.vmNotFound);
        expect(e.exitCode, 2);
      }
    });

    test('exit 0 + success false still throws failure', () async {
      expect(
        () => _exec(
          ProcessResult(
            1,
            0,
            _envelope(
              success: false,
              errors:
                  '[{"code":"CONFIG_INVALID","message":"bad",'
                  '"severity":"error","retryable":true}]',
            ),
            '',
          ),
        ).run('status', []),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.code, 'code', 'CONFIG_INVALID')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('success true + non-zero exit is incoherent', () async {
      expect(
        () => _exec(ProcessResult(1, 1, _envelope(), '')).run('status', []),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.code,
            'code',
            'INCOHERENT_RESPONSE',
          ),
        ),
      );
    });

    test('non-zero exit without envelope uses stderr', () async {
      expect(
        () => _exec(ProcessResult(1, 3, '', 'qemu exploded')).run('status', []),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.code, 'code', 'COMMAND_FAILED')
              .having(
                (e) => e.technical,
                'technical',
                contains('qemu exploded'),
              ),
        ),
      );
    });

    test('command mismatch rejected', () async {
      expect(
        () => _exec(ProcessResult(1, 0, _envelope(), '')).run('list-vms', []),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'COMMAND_MISMATCH'),
        ),
      );
    });

    test('namespaced vm.<command> envelopes are accepted', () async {
      // Real quickemu emits vm.status, not status — see schemas/v1/*.json.
      final response = await _exec(
        ProcessResult(1, 0, _envelope(command: 'vm.status'), ''),
      ).run('status', []);
      expect(response.command, 'vm.status');
    });

    test('past-tense lifecycle names are accepted', () async {
      for (final (expected, actual) in [
        ('clone', 'vm.cloned'),
        ('start', 'vm.started'),
        ('pause', 'vm.paused'),
        ('resume', 'vm.resumed'),
        ('delete-vm', 'vm.trashed'),
        ('delete-plan', 'vm.delete-plan'),
        ('snapshot-list', 'vm.snapshot.list'),
      ]) {
        final response = await _exec(
          ProcessResult(1, 0, _envelope(command: actual), ''),
        ).run(expected, []);
        expect(
          response.command,
          actual,
          reason: 'expected $expected to accept $actual',
        );
      }
    });

    test('unrelated namespaced command is still a mismatch', () async {
      expect(
        () =>
            _exec(ProcessResult(1, 0, _envelope(command: 'vm.cloned'), ''))
                .run('status', []),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'COMMAND_MISMATCH'),
        ),
      );
    });

    test('empty stdout without stderr is a contract error', () async {
      expect(
        () => _exec(ProcessResult(1, 0, '', '')).run('status', []),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'EMPTY_RESPONSE'),
        ),
      );
    });

    test('isLegacyBackend only for envelope-absence failures', () {
      expect(
        StructuredQuickemu.isLegacyBackend(
          const AppFailure(
            AppFailureKind.backendContract,
            'MALFORMED_JSON',
            'x',
          ),
        ),
        isTrue,
      );
      expect(
        StructuredQuickemu.isLegacyBackend(
          const AppFailure(
            AppFailureKind.backendContract,
            'INCOHERENT_RESPONSE',
            'x',
          ),
        ),
        isFalse,
      );
      expect(
        StructuredQuickemu.isLegacyBackend(
          const AppFailure(AppFailureKind.internal, 'COMMAND_FAILED', 'x'),
        ),
        isFalse,
      );
    });

    test('timeout produces typed failure', () async {
      final runner = _FakeRunner(
        ProcessResult(1, 0, _envelope(), ''),
        delay: const Duration(seconds: 5),
      );
      await expectLater(
        StructuredQuickemu(
          QuickemuProcess(runner),
          timeout: const Duration(milliseconds: 1),
        ).run('status', []),
        throwsA(
          isA<AppFailure>()
              .having((e) => e.code, 'code', 'BACKEND_TIMEOUT')
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });
  });
  group('output limits', () {
    test('stdout over the limit throws BACKEND_OUTPUT_TOO_LARGE', () async {
      final big = 'x' * 128;
      final e = StructuredQuickemu(
        QuickemuProcess(_FakeRunner(ProcessResult(1, 0, big, ''))),
        maxStdoutBytes: 16,
      );
      await expectLater(
        e.run('status', []),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'BACKEND_OUTPUT_TOO_LARGE')
              .having((f) => f.kind, 'kind', AppFailureKind.backendContract),
        ),
      );
    });

    test('stdout at exactly the limit is parsed normally', () async {
      final envelope = _envelope();
      final e = StructuredQuickemu(
        QuickemuProcess(_FakeRunner(ProcessResult(1, 0, envelope, ''))),
        maxStdoutBytes: envelope.length,
      );
      final r = await e.run('status', []);
      expect(r.success, isTrue);
    });
  });

  group('schema parity (schemas/v1/response.schema.json)', () {
    test('minimal envelope — only required fields — parses', () async {
      // response.schema.json requires schemaVersion/command/success/
      // data/warnings/errors/meta{quickemuVersion,timestamp}; the ids
      // are optional and must not be demanded.
      const minimal =
          '{"schemaVersion":1,"command":"status","success":true,'
          '"data":{},"warnings":[],"errors":[],'
          '"meta":{"quickemuVersion":"4.9.9",'
          '"timestamp":"2026-01-01T00:00:00Z"}}';
      final r = await _exec(ProcessResult(1, 0, minimal, '')).run('status', []);
      expect(r.success, isTrue);
      expect(r.operationId, isNull);
      expect(r.requestId, isNull);
      expect(r.quickemuVersion, '4.9.9');
    });

    test('full meta ids surface for correlation', () async {
      const full =
          '{"schemaVersion":1,"command":"status","success":true,'
          '"data":{},"warnings":[],"errors":[],'
          '"meta":{"quickemuVersion":"4.9.9",'
          '"timestamp":"2026-01-01T00:00:00Z",'
          '"operationId":"op-42","requestId":"req-7"}}';
      final r = await _exec(ProcessResult(1, 0, full, '')).run('status', []);
      expect(r.operationId, 'op-42');
      expect(r.requestId, 'req-7');
    });
  });
}
