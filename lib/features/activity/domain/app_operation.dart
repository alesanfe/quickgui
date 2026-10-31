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
  command,
  automation;

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

/// Lifecycle of a failure in the activity centre (QG-013). Distinct
/// from [OperationStatus] — the status records how the operation ended;
/// the lifecycle tracks what the *user* has done with that outcome.
enum OperationLifecycle {
  /// Newly recorded, not yet reviewed.
  newEntry,

  /// User saw it and marked it reviewed.
  acknowledged,

  /// A retry is currently in flight for this failure.
  retrying,

  /// A retry for this failure succeeded.
  recovered,

  /// Failed and not retryable — nothing more to do automatically.
  permanentlyFailed,

  /// Ended by user cancellation.
  cancelled,

  /// User dismissed it without action.
  ignored,

  /// Needs the user's attention (failed-retryable or interrupted).
  requiresAction;

  /// Default lifecycle for a freshly finished operation.
  static OperationLifecycle forStatus(
    OperationStatus status, {
    required bool retryable,
  }) => switch (status) {
    OperationStatus.failed => retryable ? requiresAction : permanentlyFailed,
    OperationStatus.interrupted => requiresAction,
    OperationStatus.cancelled => cancelled,
    OperationStatus.succeeded => newEntry,
  };
}

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
    this.lifecycle = OperationLifecycle.newEntry,
    this.occurrences = 1,
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

  /// Failure lifecycle — tracks user acknowledgement/retry outcome
  /// (QG-013).
  final OperationLifecycle lifecycle;

  /// How many times an identical failure was recorded — identical
  /// failures are merged instead of spamming the list (QG-013).
  final int occurrences;

  /// True when the entry can be re-dispatched directly (typed args and
  /// no plan regeneration required). Destructive retries that need a
  /// fresh plan stay retryable but must go through the plan flow first.
  bool get canRetry =>
      retryable && retrySpec != null && !retrySpec!.regeneratesPlan;

  /// Whether this entry needs the user's attention — the basis of the
  /// "requires action" filter (QG-014).
  bool get requiresAction => lifecycle == OperationLifecycle.requiresAction;

  /// Copy with a new lifecycle/occurrence count — entries are treated
  /// as immutable from the UI's perspective.
  OperationHistoryEntry copyWith({
    OperationLifecycle? lifecycle,
    int? occurrences,
    OperationStatus? status,
    DateTime? completedAt,
  }) => OperationHistoryEntry(
    id: id,
    kind: kind,
    target: target,
    startedAt: startedAt,
    completedAt: completedAt ?? this.completedAt,
    status: status ?? this.status,
    message: message,
    failureCode: failureCode,
    retryable: retryable,
    retrySpec: retrySpec,
    retryOf: retryOf,
    backendOperationId: backendOperationId,
    lifecycle: lifecycle ?? this.lifecycle,
    occurrences: occurrences ?? this.occurrences,
  );

  /// One-line diagnostic for the "copy diagnostic" action (QG-015):
  /// stable code, kind, target, times and backend correlation id —
  /// never includes secrets or raw argv.
  String toDiagnosticLine() {
    final parts = <String>[
      'kind=${kind.wire}',
      'target=$target',
      'status=${status.name}',
      'lifecycle=${lifecycle.name}',
      if (failureCode != null) 'code=$failureCode',
      if (id != null) 'id=$id',
      if (retryOf != null) 'retryOf=$retryOf',
      if (backendOperationId != null) 'backendOp=$backendOperationId',
      'started=${startedAt.toIso8601String()}',
      'completed=${completedAt.toIso8601String()}',
      if (occurrences > 1) 'occurrences=$occurrences',
    ];
    return '${parts.join(' ')}${message.isNotEmpty ? ' — $message' : ''}';
  }

  /// True when [other] is the same failure for dedupe purposes — same
  /// kind, target, terminal status and failure code.
  bool sameFailureAs(OperationHistoryEntry other) =>
      kind == other.kind &&
      target == other.target &&
      status == other.status &&
      failureCode == other.failureCode;

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
    if (lifecycle != OperationLifecycle.newEntry) 'lifecycle': lifecycle.name,
    if (occurrences > 1) 'occurrences': occurrences,
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
      lifecycle:
          OperationLifecycle.values
              .where((l) => l.name == json['lifecycle'])
              .firstOrNull ??
          OperationLifecycle.forStatus(
            OperationStatus.values
                    .where((s) => s.name == json['status'])
                    .firstOrNull ??
                OperationStatus.succeeded,
            retryable: json['retryable'] == true,
          ),
      occurrences: json['occurrences'] is int ? json['occurrences'] as int : 1,
    );
  }
}

/// Composable, persisted filter set for the activity centre (QG-014).
/// Pure — unit-tested without a widget tree.
class ActivityFilter {
  const ActivityFilter({
    this.status,
    this.kind,
    this.target,
    this.retryableOnly = false,
    this.requiresActionOnly = false,
    this.maxAge,
    this.query = '',
  });

  /// Terminal status filter — null means "all statuses".
  final OperationStatus? status;

  /// Operation kind filter.
  final OperationKind? kind;

  /// VM/target filter — exact target name.
  final String? target;

  /// Only entries the backend marked safe to retry.
  final bool retryableOnly;

  /// Only entries whose lifecycle needs user attention.
  final bool requiresActionOnly;

  /// Only entries completed within this window — null means all time.
  final Duration? maxAge;

  /// Free-text search across target, message, kind and failure code.
  final String query;

  bool matches(OperationHistoryEntry e, DateTime now) {
    if (status != null) {
      // The "cancelled" bucket historically groups cancelled and
      // interrupted — mirroring the existing tab semantics.
      final match = status == OperationStatus.cancelled
          ? (e.status == OperationStatus.cancelled ||
                e.status == OperationStatus.interrupted)
          : e.status == status;
      if (!match) return false;
    }
    if (kind != null && e.kind != kind) return false;
    if (target != null && e.target != target) return false;
    if (retryableOnly && !e.retryable) return false;
    if (requiresActionOnly && !e.requiresAction) return false;
    if (maxAge != null && now.difference(e.completedAt) > maxAge!) {
      return false;
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      final hay =
          '${e.target} ${e.message} ${e.kind.wire} '
                  '${e.failureCode ?? ''}'
              .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  /// Whether any filter is active — drives the "clear filters" button.
  bool get isActive =>
      status != null ||
      kind != null ||
      target != null ||
      retryableOnly ||
      requiresActionOnly ||
      maxAge != null ||
      query.isNotEmpty;

  ActivityFilter copyWith({
    OperationStatus? Function()? status,
    OperationKind? Function()? kind,
    String? Function()? target,
    bool? retryableOnly,
    bool? requiresActionOnly,
    Duration? Function()? maxAge,
    String? query,
  }) => ActivityFilter(
    status: status != null ? status() : this.status,
    kind: kind != null ? kind() : this.kind,
    target: target != null ? target() : this.target,
    retryableOnly: retryableOnly ?? this.retryableOnly,
    requiresActionOnly: requiresActionOnly ?? this.requiresActionOnly,
    maxAge: maxAge != null ? maxAge() : this.maxAge,
    query: query ?? this.query,
  );

  Map<String, dynamic> toJson() => {
    if (status != null) 'status': status!.name,
    if (kind != null) 'kind': kind!.wire,
    if (target != null) 'target': target,
    if (retryableOnly) 'retryableOnly': true,
    if (requiresActionOnly) 'requiresActionOnly': true,
    if (maxAge != null) 'maxAgeMinutes': maxAge!.inMinutes,
    if (query.isNotEmpty) 'query': query,
  };

  factory ActivityFilter.fromJson(Map<String, dynamic> json) => ActivityFilter(
    status: OperationStatus.values
        .where((s) => s.name == json['status'])
        .firstOrNull,
    kind: OperationKind.fromWire(json['kind']),
    target: json['target'] is String ? json['target'] as String : null,
    retryableOnly: json['retryableOnly'] == true,
    requiresActionOnly: json['requiresActionOnly'] == true,
    maxAge: json['maxAgeMinutes'] is int
        ? Duration(minutes: json['maxAgeMinutes'] as int)
        : null,
    query: '${json['query'] ?? ''}',
  );
}
