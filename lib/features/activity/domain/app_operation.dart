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
  restore,
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
    this.state = const OperationState.queued(),
    this.onCancel,
    this.retrySpec,
    this.retryOf,
  });

  final String id;
  final OperationKind kind;
  final String target;
  final DateTime startedAt;
  DateTime? completedAt;
  OperationState<Object?> state;
  String output = '';

  /// Typed retry descriptor forwarded to the history entry on
  /// completion — null means the operation cannot be re-run.
  final RetrySpec? retrySpec;

  /// Id of the original operation when this one is itself a retry.
  final String? retryOf;

  /// Cancellation hook wired by the owner of the process (e.g. the
  /// downloader kills its process). Null = not cancellable.
  final Future<void> Function()? onCancel;

  /// Operation id emitted by the backend envelope (`meta.operationId`)
  /// — set by the executor once the response arrives; used to
  /// correlate retries, interrupted-state reconciliation and reports.
  String? backendOperationId;

  bool get isTerminal => state.isTerminal;
}

/// Terminal status persisted in the activity history.
enum OperationStatus { succeeded, failed, cancelled, interrupted }

/// Typed description of how to re-run an operation — never a raw
/// command-line string. Arguments are the normalised quickemu tail
/// (flags and paths only; no secrets are ever stored).
class RetrySpec {
  const RetrySpec({
    required this.command,
    required this.arguments,
    this.requiresConfirmation = false,
    this.regeneratesPlan = false,
    this.idempotent = false,
  });

  /// Structured command name the envelope must declare, e.g. 'start'.
  final String command;

  /// Normalised argument tail, e.g. ['--vm', 'x.conf', '--pause'].
  final List<String> arguments;

  /// Destructive operations must be confirmed again before retrying.
  final bool requiresConfirmation;

  /// True when the retry must regenerate a fresh plan (e.g. delete)
  /// instead of reusing arguments that embed an expired planId.
  final bool regeneratesPlan;

  /// True when repeating the operation has no additional side effects.
  final bool idempotent;

  Map<String, dynamic> toJson() => {
    'command': command,
    'arguments': arguments,
    if (requiresConfirmation) 'requiresConfirmation': true,
    if (regeneratesPlan) 'regeneratesPlan': true,
    if (idempotent) 'idempotent': true,
  };

  static RetrySpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final command = json['command'];
    final arguments = json['arguments'];
    if (command is! String || arguments is! List) return null;
    return RetrySpec(
      command: command,
      arguments: [for (final a in arguments) '$a'],
      requiresConfirmation: json['requiresConfirmation'] == true,
      regeneratesPlan: json['regeneratesPlan'] == true,
      idempotent: json['idempotent'] == true,
    );
  }
}

/// A finished operation, serialisable for the persisted history.
class OperationHistoryEntry {
  const OperationHistoryEntry({
    required this.kind,
    required this.target,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    this.id,
    this.message = '',
    this.failureCode,
    this.retryable = false,
    this.retrySpec,
    this.retryOf,
    this.backendOperationId,
  });

  final OperationKind kind;
  final String target;
  final DateTime startedAt;
  final DateTime completedAt;
  final OperationStatus status;

  /// Id of the originating [AppOperation] — persisted so retries can
  /// link back to the attempt they re-ran. Null for records written
  /// before correlation existed.
  final String? id;
  final String message;

  /// Stable `AppFailure` code when the operation failed — preserved so
  /// history retries and reports stay meaningful after a restart.
  final String? failureCode;

  /// Whether the failure is safe to retry (transient backend issues
  /// only — never retries for validation/contract/permission errors).
  final bool retryable;

  /// Typed retry descriptor persisted with the entry — null means the
  /// operation cannot be re-run automatically.
  final RetrySpec? retrySpec;

  /// Id of the original operation when this entry is itself a retry.
  final String? retryOf;

  /// Backend-side `meta.operationId` when the structured envelope
  /// provided one — lets a future `operation-status` command resume
  /// or query the async-operation registry.
  final String? backendOperationId;

  /// True when the entry can be re-dispatched directly (typed args and
  /// no plan regeneration required). Destructive retries that need a
  /// fresh plan stay retryable but must go through the plan flow first.
  bool get canRetry =>
      retryable && retrySpec != null && !retrySpec!.regeneratesPlan;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'kind': kind.wire,
    'target': target,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'status': status.name,
    'message': message,
    if (failureCode != null) 'failureCode': failureCode,
    if (retryable) 'retryable': true,
    if (retrySpec != null) 'retrySpec': retrySpec!.toJson(),
    if (retryOf != null) 'retryOf': retryOf,
    if (backendOperationId != null) 'backendOperationId': backendOperationId,
  };

  static OperationHistoryEntry? fromJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse('${json['startedAt']}');
    final completedAt = DateTime.tryParse('${json['completedAt']}');
    if (startedAt == null) return null;
    return OperationHistoryEntry(
      id: json['id'] is String ? json['id'] as String : null,
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
      retrySpec: RetrySpec.fromJson(json['retrySpec']),
      retryOf: json['retryOf'] is String ? json['retryOf'] as String : null,
      backendOperationId: json['backendOperationId'] is String
          ? json['backendOperationId'] as String
          : null,
    );
  }
}
