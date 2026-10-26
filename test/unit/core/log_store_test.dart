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

  test('AppLog.event writes to the store and the logger', () {
    final captured = <String>[];
    final sub = Logger.root.onRecord.listen((r) => captured.add(r.message));
    addTearDown(sub.cancel);
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
    expect(captured.single, contains('command=start'));
    expect(captured.single, contains('vm=fedora-45'));
    expect(LogStore.records.single.command, 'start');
    expect(LogStore.records.single.durationMs, 12);
  });
}
