import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/telemetry/legacy_policy.dart';
import 'package:quickgui/core/telemetry/legacy_telemetry.dart';

void main() {
  tearDown(LegacyTelemetry.reset);

  group('isBackendEnvelopeMissing', () {
    for (final code in [
      'EMPTY_RESPONSE',
      'MALFORMED_JSON',
      'UNEXPECTED_SHAPE',
      'MISSING_SCHEMA_VERSION',
    ]) {
      test('envelope-absence code $code allows legacy fallback', () {
        expect(
          isBackendEnvelopeMissing(
            AppFailure(AppFailureKind.backendContract, code, ''),
          ),
          isTrue,
        );
      });
    }

    for (final code in [
      'INCOHERENT_RESPONSE',
      'COMMAND_MISMATCH',
      'COMMAND_FAILED',
      'BACKEND_TIMEOUT',
      'BACKEND_OUTPUT_TOO_LARGE',
    ]) {
      test('modern defect $code never falls back', () {
        expect(
          isBackendEnvelopeMissing(
            AppFailure(AppFailureKind.backendContract, code, ''),
          ),
          isFalse,
        );
      });
    }
  });

  group('LegacyTelemetry', () {
    test('records bounded entries newest first', () {
      for (var i = 0; i < 60; i++) {
        LegacyTelemetry.record('cmd$i', 'EMPTY_RESPONSE');
      }
      expect(LegacyTelemetry.count, 50);
      expect(LegacyTelemetry.last?.command, 'cmd59');
      expect(LegacyTelemetry.commands, contains('cmd0'));
    });

    test('toJson exports redacted entries', () {
      LegacyTelemetry.record(
        'start',
        'MALFORMED_JSON',
        backendVersion: '4.9.6',
      );
      final json = LegacyTelemetry.toJson();
      expect(json.single['command'], 'start');
      expect(json.single['backendVersion'], '4.9.6');
    });
  });

  test('LegacyPolicy lists the structured minimum version', () {
    expect(LegacyPolicy.minStructuredQuickemuVersion, isNotEmpty);
    expect(LegacyPolicy.allowedCommands, isNot(contains('capabilities')));
    expect(LegacyPolicy.neverFallback, contains('capabilities'));
  });
}
