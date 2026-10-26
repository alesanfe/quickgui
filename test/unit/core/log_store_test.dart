import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:quickgui/core/logging/app_logging.dart';

void main() {
  tearDown(LogStore.reset);

  group('LogStore', () {
    test('keeps bounded records newest first', () {
      for (var i = 0; i < 250; i++) {
        LogStore.add(
          AppLogRecord(
            at: DateTime(2025).add(Duration(seconds: i)),
            level: 'INFO',
            logger: 'test',
            message: 'm$i',
          ),
        );
      }
      expect(LogStore.records, hasLength(200));
      expect(LogStore.records.first.message, 'm249');
    });

    test('toJson exports structured fields', () {
      LogStore.add(
        AppLogRecord(
          at: DateTime(2025, 6),
          level: 'WARNING',
          logger: 'backend.contract',
          message: 'failed',
          command: 'delete-vm',
          failureCode: 'COMMAND_FAILED',
          legacy: false,
        ),
      );
      final json = LogStore.toJson().single;
      expect(json['command'], 'delete-vm');
      expect(json['failureCode'], 'COMMAND_FAILED');
      expect(json['legacy'], false);
    });
  });

  test('AppLog.event writes a structured record to the store', () {
    AppLog.event(
      AppLog.backendContract,
      Level.FINE,
      'structured command completed',
      command: 'start',
      vm: 'fedora-45',
      durationMs: 12,
      exitCode: 0,
      legacy: false,
    );
    final record = LogStore.records.single;
    expect(record.command, 'start');
    expect(record.vm, 'fedora-45');
    expect(record.durationMs, 12);
    expect(record.exitCode, 0);
    expect(record.legacy, false);
    expect(record.logger, 'contract');
  });
}
