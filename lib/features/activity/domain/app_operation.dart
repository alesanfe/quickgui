import 'package:quickgui/shared/models/operation_state.dart';

/// Kind of tracked operation. Used for icons and grouping in the
/// activity centre.
enum OperationKind {
  download,
  start,
  stop,
  clone,
  export,
  verify,
  resize,
  snapshot,
  delete,
  import,
  convert,
  command;

  /// Stable wire name for persistence.
  String get wire => name;

  static OperationKind fromWire(Object? value) =>
      OperationKind.values.where((k) => k.name == value).firstOrNull ??
      OperationKind.command;
}

/// A long-running operation tracked by the activity centre: downloads,
/// exports, clones, deletions... Anything the backend runs that the user
/// should be able to monitor (and cancel when safe).
class AppOperation {
  AppOperation({
    required this.id,
    required this.kind,
    required this.target,
    required this.startedAt,
    this.state = const OperationState.running(),
    this.onCancel,
  });

  final String id;
  final OperationKind kind;
  final String target;
  final DateTime startedAt;
  DateTime? completedAt;
  OperationState<Object?> state;
  String output = '';

  /// Cancellation hook wired by the owner of the process (e.g. the
  /// downloader kills its process). Null = not cancellable.
  final Future<void> Function()? onCancel;

  bool get isTerminal => state.isTerminal;
}

/// Terminal status persisted in the activity history.
enum OperationStatus { succeeded, failed, cancelled, interrupted }

/// A finished operation, serialisable for the persisted history.
class OperationHistoryEntry {
  const OperationHistoryEntry({
    required this.kind,
    required this.target,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    this.message = '',
    this.failureCode,
    this.retryable = false,
  });

  final OperationKind kind;
  final String target;
  final DateTime startedAt;
  final DateTime completedAt;
  final OperationStatus status;
  final String message;

  /// Stable `AppFailure` code when the operation failed — preserved so
  /// history retries and reports stay meaningful after a restart.
  final String? failureCode;

  /// Whether the failure is safe to retry (transient backend issues
  /// only — never retries for validation/contract/permission errors).
  final bool retryable;

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    'target': target,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'status': status.name,
    'message': message,
    if (failureCode != null) 'failureCode': failureCode,
    if (retryable) 'retryable': true,
  };

  static OperationHistoryEntry? fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse('${json['startedAt']}');
    final completedAt = DateTime.tryParse('${json['completedAt']}');
    if (startedAt == null) return null;
    return OperationHistoryEntry(
      kind: OperationKind.fromWire(json['kind']),
      target: '${json['target']}',
      startedAt: startedAt,
      completedAt: completedAt ?? startedAt,
      status:
          OperationStatus.values
              .where((s) => s.name == json['status'])
              .firstOrNull ??
          OperationStatus.succeeded,
      message: '${json['message'] ?? ''}',
      failureCode: json['failureCode'] is String
          ? json['failureCode'] as String
          : null,
      retryable: json['retryable'] == true,
    );
  }
}
