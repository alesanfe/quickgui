import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_response.dart';

String envelope({
  Object? schemaVersion = 1,
  String command = 'inspect',
  bool success = true,
  Object? data = const {},
  List<Object?> warnings = const [],
  List<Object?> errors = const [],
  String quickemuVersion = '4.9.9',
  String? operationId,
}) {
  final map = {
    'schemaVersion': schemaVersion,
    'command': command,
    'success': success,
    'data': data,
    'warnings': warnings,
    'errors': errors,
    'meta': {
      'quickemuVersion': quickemuVersion,
      'timestamp': '2026-01-01T00:00:00Z',
      'operationId': ?operationId,
    },
  };
  return jsonEncode(map);
}

void main() {
  group('envelope parsing', () {
    test('parses a valid success envelope', () {
      final r = QuickemuResponse.parse(
        envelope(data: {'state': 'running', 'pid': 42}),
        command: 'inspect',
      );
      expect(r.success, isTrue);
      expect(r.command, 'inspect');
      expect(r.dataMap!['state'], 'running');
      expect(r.dataMap!['pid'], 42);
      expect(r.quickemuVersion, '4.9.9');
      expect(r.errors, isEmpty);
    });

    test('tolerates unknown fields (forward compatibility)', () {
      final raw = envelope(data: {'state': 'stopped'})
          .replaceFirst('{', '{"futureField": {"nested": true},');
      final r = QuickemuResponse.parse(raw, command: 'inspect');
      expect(r.success, isTrue);
      expect(r.dataMap!['state'], 'stopped');
    });

    test('parses warnings and errors with severity and retryable', () {
      final r = QuickemuResponse.parse(
        envelope(
          success: false,
          warnings: [
            {
              'code': 'LOW_DISK',
              'message': 'Low disk space',
              'severity': 'warning',
              'retryable': false,
            },
          ],
          errors: [
            {
              'code': 'VM_NOT_FOUND',
              'message': 'No such VM',
              'severity': 'error',
              'retryable': false,
              'details': {'vm': 'ubuntu'},
            },
          ],
        ),
        command: 'inspect',
      );
      expect(r.warnings.single.code, 'LOW_DISK');
      expect(r.errors.single.code, 'VM_NOT_FOUND');
      expect(r.errors.single.details!['vm'], 'ubuntu');
    });

    test('exposes operationId from meta', () {
      final r = QuickemuResponse.parse(
        envelope(operationId: 'op-123'),
        command: 'export',
      );
      expect(r.operationId, 'op-123');
    });

    // Mutation-killers: each test below exists because a manual mutant
    // survived the suite. They pin fail-closed and tolerance behavior.

    test('missing success field fails closed (mutant: != false)', () {
      final raw = envelope().replaceFirst('"success":true,', '');
      final r = QuickemuResponse.parse(raw, command: 'inspect');
      expect(r.success, isFalse);
    });

    test('non-bool success fails closed', () {
      final raw = envelope().replaceFirst('"success":true', '"success":"yes"');
      final r = QuickemuResponse.parse(raw, command: 'inspect');
      expect(r.success, isFalse);
    });

    test('empty stdout reports EMPTY_RESPONSE, not MALFORMED_JSON', () {
      expect(
        () => QuickemuResponse.parse('  ', command: 'inspect', exitCode: 0),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'EMPTY_RESPONSE')
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
    });

    test(
      'fractional schemaVersion is rejected as missing (mutant: is num)',
      () {
        expect(
          () => QuickemuResponse.parse(
            envelope(schemaVersion: 1.5),
            command: 'x',
          ),
          throwsA(
            isA<AppFailure>().having(
              (f) => f.code,
              'code',
              'MISSING_SCHEMA_VERSION',
            ),
          ),
        );
      },
    );

    test('non-map items in warnings/errors are skipped, not fatal', () {
      final r = QuickemuResponse.parse(
        envelope(
          warnings: ['a string', 42, null],
          errors: [
            {'code': 'VM_NOT_FOUND', 'message': 'm', 'severity': 'error'},
            'garbage',
          ],
        ),
        command: 'inspect',
      );
      expect(r.warnings, isEmpty);
      expect(r.errors, hasLength(1));
      expect(r.errors.single.code, 'VM_NOT_FOUND');
    });

    test('non-bool retryable in messages fails closed', () {
      final r = QuickemuResponse.parse(
        envelope(
          errors: [
            {
              'code': 'X',
              'message': 'm',
              'severity': 'error',
              'retryable': 'yes',
            },
          ],
        ),
        command: 'inspect',
      );
      expect(r.errors.single.retryable, isFalse);
    });
  });

  group('contract failures', () {
    test('empty stdout throws EMPTY_RESPONSE', () {
      expect(
        () => QuickemuResponse.parse('  ', command: 'inspect'),
        throwsA(isA<AppFailure>().having((f) => f.code, 'code', isNotEmpty)),
      );
    });

    test('malformed JSON throws MALFORMED_JSON', () {
      expect(
        () => QuickemuResponse.parse('{"schemaVersion":1,', command: 'x'),
        throwsA(
          isA<AppFailure>().having((f) => f.code, 'code', 'MALFORMED_JSON'),
        ),
      );
    });

    test('non-object JSON throws UNEXPECTED_SHAPE', () {
      expect(
        () => QuickemuResponse.parse('[1,2]', command: 'x'),
        throwsA(
          isA<AppFailure>().having((f) => f.code, 'code', 'UNEXPECTED_SHAPE'),
        ),
      );
    });

    test('missing schemaVersion throws MISSING_SCHEMA_VERSION', () {
      expect(
        () => QuickemuResponse.parse(
          '{"command":"x","success":true}',
          command: 'x',
        ),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            'MISSING_SCHEMA_VERSION',
          ),
        ),
      );
    });

    test('future schema version throws CONTRACT_TOO_NEW', () {
      expect(
        () => QuickemuResponse.parse(envelope(schemaVersion: 2), command: 'x'),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'CONTRACT_TOO_NEW')
              .having(
                (f) => f.kind,
                'kind',
                AppFailureKind.versionIncompatible,
              ),
        ),
      );
    });

    test('older schema versions stay parseable', () {
      expect(
        () => QuickemuResponse.parse(envelope(), command: 'x'),
        returnsNormally,
      );
    });
  });

  group('toFailure', () {
    test('maps known error codes to families', () {
      final r = QuickemuResponse.parse(
        envelope(
          success: false,
          errors: [
            {
              'code': 'INSUFFICIENT_SPACE',
              'message': 'Not enough space',
              'severity': 'error',
              'retryable': false,
            },
          ],
        ),
        command: 'export',
      );
      final failure = r.toFailure();
      expect(failure.kind, AppFailureKind.spaceLow);
      expect(failure.code, 'INSUFFICIENT_SPACE');
      expect(failure.retryable, isFalse);
    });

    test('failure without errors produces BACKEND_ERROR', () {
      final r = QuickemuResponse.parse(
        envelope(success: false),
        command: 'export',
      );
      expect(r.toFailure().code, 'BACKEND_ERROR');
    });

    test('toReportLine carries context without leaking details', () {
      const f = AppFailure(
        AppFailureKind.connection,
        'CONNECTION_FAILED',
        'The SPICE connection could not be opened.',
        vm: 'ubuntu',
        exitCode: 3,
        retryable: true,
      );
      final line = f.toReportLine();
      expect(line, contains('CONNECTION_FAILED'));
      expect(line, contains('vm=ubuntu'));
      expect(line, contains('exit=3'));
      expect(line, contains('retryable=true'));
    });
  });
}
