import 'dart:async';

import 'package:logging/logging.dart';

/// Fire-and-forget wrapper for best-effort futures. A bare
/// `unawaited()` leaves a rejection unhandled — it escapes to the
/// zone as an opaque async error and is logged nowhere useful. This
/// routes the failure to the structured logger instead, so dropped
/// work is at least diagnosable.
void unawaitedLogged(Future<Object?>? future, Logger logger, String what) {
  unawaited(() async {
    try {
      await future;
    } catch (e) {
      logger.warning('$what failed: $e');
    }
  }());
}

/// One structured log record kept in the bounded in-memory store.
class AppLogRecord {
  const AppLogRecord({
    required this.at,
    required this.level,
    required this.logger,
    required this.message,
    this.requestId,
    this.operationId,
    this.vm,
    this.command,
    this.durationMs,
    this.exitCode,
    this.legacy,
    this.failureCode,
  });

  final DateTime at;
  final String level;
  final String logger;
  final String message;
  final String? requestId;
  final String? operationId;
  final String? vm;
  final String? command;
  final int? durationMs;
  final int? exitCode;
  final bool? legacy;
  final String? failureCode;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'level': level,
    'logger': logger,
    'message': message,
    if (requestId != null) 'requestId': requestId,
    if (operationId != null) 'operationId': operationId,
    if (vm != null) 'vm': vm,
    if (command != null) 'command': command,
    if (durationMs != null) 'durationMs': durationMs,
    if (exitCode != null) 'exitCode': exitCode,
    if (legacy != null) 'legacy': legacy,
    if (failureCode != null) 'failureCode': failureCode,
  };
}

/// Bounded in-memory log store — newest first. Local-only: nothing is
/// sent off the machine; records feed the diagnostics export.
class LogStore {
  LogStore._();

  static const _limit = 200;
  static final List<AppLogRecord> _records = [];

  static List<AppLogRecord> get records => List.unmodifiable(_records);

  static void add(AppLogRecord record) {
    _records.insert(0, record);
    if (_records.length > _limit) _records.removeLast();
  }

  static List<Map<String, dynamic>> toJson() => [
    for (final r in _records) r.toJson(),
  ];

  /// Test hook — clears recorded entries.
  static void reset() => _records.clear();
}

/// Logger categories - structured, local-only diagnostics.
abstract class AppLog {
  static final bootstrap = Logger('app.bootstrap');
  static final backendDiscovery = Logger('backend.discovery');
  static final backendProcess = Logger('backend.process');
  static final backendContract = Logger('backend.contract');
  static final filesystem = Logger('filesystem');
  static final preferences = Logger('preferences');
  static final navigation = Logger('ui.navigation');
  static final vmLifecycle = Logger('vm.lifecycle');
  static final download = Logger('download');
  static final diagnostics = Logger('diagnostics');
  static final perf = Logger('ui.perf');

  /// Structured event helper — writes to the logger and the in-memory
  /// store so diagnostics can export correlated records.
  static void event(
    Logger logger,
    Level level,
    String message, {
    String? requestId,
    String? operationId,
    String? vm,
    String? command,
    int? durationMs,
    int? exitCode,
    bool? legacy,
    String? failureCode,
  }) {
    final kv = [
      if (requestId != null) 'requestId=$requestId',
      if (operationId != null) 'operationId=$operationId',
      if (vm != null) 'vm=$vm',
      if (command != null) 'command=$command',
      if (durationMs != null) 'durationMs=$durationMs',
      if (exitCode != null) 'exitCode=$exitCode',
      if (legacy != null) 'legacy=$legacy',
      if (failureCode != null) 'failureCode=$failureCode',
    ].join(' ');
    logger.log(level, kv.isEmpty ? message : '$message $kv');
    LogStore.add(
      AppLogRecord(
        at: DateTime.now(),
        level: level.name,
        logger: logger.name,
        message: message,
        requestId: requestId,
        operationId: operationId,
        vm: vm,
        command: command,
        durationMs: durationMs,
        exitCode: exitCode,
        legacy: legacy,
        failureCode: failureCode,
      ),
    );
  }

  /// Local-only console logging (no remote telemetry, per privacy
  /// policy for a local virtualization app).
  static void init({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((r) {
      // ignore: avoid_print
      print('${r.time} [${r.level.name}] ${r.loggerName}: ${r.message}');
    });
  }
}
