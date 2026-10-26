import 'dart:convert';

import 'package:quickgui/core/errors/app_failure.dart';

/// Parsed wire error from the response envelope `errors[]`/`warnings[]`.
class ContractMessage {
  const ContractMessage({
    required this.code,
    required this.message,
    required this.severity,
    required this.retryable,
    this.details,
  });

  final String code;
  final String message;
  final String severity; // 'error' | 'warning' | 'info'
  final bool retryable;
  final Map<String, dynamic>? details;

  factory ContractMessage.fromJson(Map<String, dynamic> json) {
    return ContractMessage(
      code: json['code'] is String ? json['code'] as String : 'UNKNOWN',
      message: json['message'] is String ? json['message'] as String : '',
      severity: json['severity'] is String
          ? json['severity'] as String
          : 'error',
      retryable: json['retryable'] == true,
      details: json['details'] is Map<String, dynamic>
          ? json['details'] as Map<String, dynamic>
          : null,
    );
  }
}

/// Structured response of a quickemu `--format json` command.
///
/// Follows `schemas/v1/response.schema.json`: every command shares the
/// same envelope — `schemaVersion`, `command`, `success`, `data`,
/// `warnings`, `errors`, `meta{quickemuVersion,timestamp,operationId}`.
/// Unknown fields are tolerated so a newer contract stays compatible.
class QuickemuResponse {
  const QuickemuResponse({
    required this.command,
    required this.success,
    required this.data,
    required this.warnings,
    required this.errors,
    required this.quickemuVersion,
    required this.timestamp,
    this.operationId,
    this.requestId,
  });

  final String command;
  final bool success;
  final dynamic data;
  final List<ContractMessage> warnings;
  final List<ContractMessage> errors;
  final String quickemuVersion;
  final String timestamp;
  final String? operationId;
  final String? requestId;

  /// Highest envelope version this parser understands.
  static const supportedSchemaVersion = 1;

  /// Parses the raw stdout of a `--format json` call.
  ///
  /// Throws [AppFailure] with `backendContract` kind when the payload is
  /// not the expected envelope — empty output, malformed JSON, missing
  /// required fields, wrong types or an incompatible schema version.
  factory QuickemuResponse.parse(
    String stdout, {
    required String command,
    int? exitCode,
    String? stderr,
  }) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'EMPTY_RESPONSE',
        'The backend returned no structured response.',
        technical: 'command=$command exit=$exitCode stderr=$stderr',
        retryable: exitCode == 0,
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'MALFORMED_JSON',
        'The backend response could not be parsed.',
        technical: 'command=$command exit=$exitCode error=$e\nstdout=$trimmed',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'UNEXPECTED_SHAPE',
        'The backend response is not a JSON object.',
        technical: 'command=$command type=${decoded.runtimeType}',
      );
    }
    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'MISSING_SCHEMA_VERSION',
        'The backend response lacks a schema version.',
        technical: 'command=$command keys=${decoded.keys.toList()}',
      );
    }
    if (schemaVersion > supportedSchemaVersion) {
      throw AppFailure(
        AppFailureKind.versionIncompatible,
        'CONTRACT_TOO_NEW',
        'This Quickemu release uses a newer output contract than Quickgui '
            'understands.',
        technical:
            'schemaVersion=$schemaVersion supported=$supportedSchemaVersion',
        suggestion:
            'Update Quickgui to a version that supports contract '
            'v$schemaVersion, or downgrade Quickemu.',
      );
    }
    List<ContractMessage> messages(String key) {
      final raw = decoded[key];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map<String, dynamic>) ContractMessage.fromJson(item),
      ];
    }

    final meta = decoded['meta'];
    final metaMap = meta is Map<String, dynamic>
        ? meta
        : const <String, dynamic>{};
    return QuickemuResponse(
      command: decoded['command'] is String
          ? decoded['command'] as String
          : command,
      success: decoded['success'] == true,
      data: decoded['data'],
      warnings: messages('warnings'),
      errors: messages('errors'),
      quickemuVersion: metaMap['quickemuVersion'] is String
          ? metaMap['quickemuVersion'] as String
          : '',
      timestamp: metaMap['timestamp'] is String
          ? metaMap['timestamp'] as String
          : '',
      operationId: metaMap['operationId'] is String
          ? metaMap['operationId'] as String
          : null,
      requestId: metaMap['requestId'] is String
          ? metaMap['requestId'] as String
          : decoded['request_id'] is String
          ? decoded['request_id'] as String
          : null,
    );
  }

  /// Data as a map, or null when it is missing or has a different shape —
  /// commands that expect an object should handle both safely.
  Map<String, dynamic>? get dataMap =>
      data is Map<String, dynamic> ? data as Map<String, dynamic> : null;

  /// Data as a list, or null — for commands returning arrays.
  List<dynamic>? get dataList => data is List ? data as List : null;

  /// Converts the first structured error into an [AppFailure] — for
  /// `success == false` callers that want a typed throw.
  AppFailure toFailure({String? vm, String? operation}) {
    final first = errors.isNotEmpty ? errors.first : null;
    return AppFailure(
      first != null ? _kindFor(first.code) : AppFailureKind.internal,
      first?.code ?? 'BACKEND_ERROR',
      first?.message ?? 'The backend reported a failure.',
      technical: first?.details?.toString(),
      vm: vm ?? first?.details?['vm']?.toString(),
      operation: operation ?? operationId,
      retryable: first?.retryable ?? false,
    );
  }

  static AppFailureKind _kindFor(String code) => switch (code) {
    'VM_NOT_FOUND' => AppFailureKind.vmNotFound,
    'CONFIG_INVALID' => AppFailureKind.configInvalid,
    'STATE_INCOMPATIBLE' => AppFailureKind.stateIncompatible,
    'DEPENDENCY_MISSING' => AppFailureKind.dependencyMissing,
    'PERMISSION_DENIED' => AppFailureKind.permission,
    'PORT_BUSY' => AppFailureKind.portBusy,
    // Registry/lock/plan codes the Go-migrated backend can emit —
    // a busy lock is a busy-port sibling, stale plans are contract
    // state violations, a missing op is an interrupted-operation gap.
    'LOCK_BUSY' => AppFailureKind.portBusy,
    'LOCK_TIMEOUT' => AppFailureKind.timeout,
    'PLAN_EXPIRED' => AppFailureKind.stateIncompatible,
    'PLAN_MISMATCH' => AppFailureKind.backendContract,
    'OPERATION_NOT_FOUND' => AppFailureKind.internal,
    'CONNECTION_FAILED' => AppFailureKind.connection,
    'TIMEOUT' => AppFailureKind.timeout,
    'DOWNLOAD_FAILED' => AppFailureKind.download,
    'CHECKSUM_MISMATCH' => AppFailureKind.checksum,
    'INSUFFICIENT_SPACE' => AppFailureKind.spaceLow,
    'SNAPSHOT_NOT_FOUND' => AppFailureKind.snapshotMissing,
    'OPERATION_CANCELLED' => AppFailureKind.cancelled,
    'PARTIAL_RESULT' => AppFailureKind.partial,
    'VERSION_INCOMPATIBLE' => AppFailureKind.versionIncompatible,
    _ => AppFailureKind.internal,
  };
}
