/// Typed failure hierarchy for Quickgui.
///
/// Every user-visible error carries a stable machine code, a
/// human-readable message, an optional technical detail kept for
/// logs/reports, and enough context (vm/operation/phase) to present an
/// actionable message instead of a raw Dart exception.
library;

/// Broad error family — drives iconography and recommended actions.
enum AppFailureKind {
  validation,
  vmNotFound,
  configInvalid,
  stateIncompatible,
  dependencyMissing,
  permission,
  virtualizationUnavailable,
  portBusy,
  connection,
  processGone,
  timeout,
  download,
  checksum,
  spaceLow,
  diskFormat,
  snapshotMissing,
  cancelled,
  partial,
  versionIncompatible,
  fileWrite,
  externalModification,
  backendContract,
  internal,
}

/// A user-facing failure with stable code and recovery metadata.
class AppFailure implements Exception {
  const AppFailure(
    this.kind,
    this.code,
    this.userMessage, {
    this.technical,
    this.vm,
    this.operation,
    this.phase,
    this.exitCode,
    this.retryable = false,
    this.partialChanges = false,
    this.suggestion,
    this.cause,
  });

  /// Family used for icons, filtering and suggested remediation.
  final AppFailureKind kind;

  /// Stable machine code, e.g. `VM_NOT_FOUND`, `CONF_WRITE_FAILED`.
  final String code;

  /// Localized user-facing message (already resolved — callers pass the
  /// `context.t(...)` result or a plain string for non-UI layers).
  final String userMessage;

  /// Technical detail kept for logs and expandable report sections —
  /// never shown raw in the primary message.
  final String? technical;

  /// VM this failure relates to, when any.
  final String? vm;

  /// Activity/operation id this failure belongs to, when any.
  final String? operation;

  /// Phase in which it happened (validation, download, verify, ...).
  final String? phase;

  /// Process exit code when the failure came from a backend call.
  final int? exitCode;

  /// Whether retrying is likely to succeed.
  final bool retryable;

  /// Whether the operation left partial changes on disk before failing.
  final bool partialChanges;

  /// Recommended next action for the user (localized, plain text).
  final String? suggestion;

  /// Underlying exception/error for log correlation.
  final Object? cause;

  /// Map a `VmConfigWriteException`-style file failure to a typed error.
  factory AppFailure.fileWrite(
    String path,
    Object cause, {
    String? userMessage,
  }) => AppFailure(
    AppFailureKind.fileWrite,
    'CONF_WRITE_FAILED',
    userMessage ?? 'The virtual machine configuration could not be saved.',
    technical: 'path: $path\ncause: $cause',
    retryable: true,
    suggestion: 'Check permissions and free space, then retry.',
    cause: cause,
  );

  /// External modification detected while editing a .conf.
  factory AppFailure.externalModification(String path) => AppFailure(
    AppFailureKind.externalModification,
    'CONF_EXTERNAL_MODIFICATION',
    'The configuration file was modified outside Quickgui.',
    technical: 'path: $path',
    retryable: true,
    suggestion: 'Reload from disk or save a copy of your changes.',
  );

  /// Process-level failure from a backend call (non-zero exit, spawn
  /// error, etc.) keeping the exit code and stderr for diagnostics.
  factory AppFailure.process(
    String code,
    String userMessage, {
    int? exitCode,
    String? stderr,
    String? vm,
    String? operation,
    bool retryable = false,
    Object? cause,
  }) => AppFailure(
    AppFailureKind.processGone,
    code,
    userMessage,
    technical: stderr,
    exitCode: exitCode,
    vm: vm,
    operation: operation,
    retryable: retryable,
    cause: cause,
  );

  /// Cooperative cancellation — not really an error state for the user.
  factory AppFailure.cancelled({String? operation, String? vm}) =>
      const AppFailure(
        AppFailureKind.cancelled,
        'OPERATION_CANCELLED',
        'The operation was cancelled.',
      )._with(operation: operation, vm: vm);

  AppFailure _with({String? operation, String? vm}) => AppFailure(
    kind,
    code,
    userMessage,
    technical: technical,
    vm: vm ?? this.vm,
    operation: operation ?? this.operation,
    phase: phase,
    exitCode: exitCode,
    retryable: retryable,
    partialChanges: partialChanges,
    suggestion: suggestion,
    cause: cause,
  );

  /// Short one-line summary for activity tiles/log lines.
  String get summary => '$code: $userMessage';

  /// Safe report line with technical detail but no stack trace — callers
  /// keep `cause` for internal logs, never in user reports.
  String toReportLine() {
    final parts = <String>[
      'code=$code',
      'kind=${kind.name}',
      if (vm != null) 'vm=$vm',
      if (operation != null) 'operation=$operation',
      if (phase != null) 'phase=$phase',
      if (exitCode != null) 'exit=$exitCode',
      'retryable=$retryable',
      if (partialChanges) 'partialChanges=true',
    ];
    return '${parts.join(' ')} — $userMessage';
  }

  @override
  String toString() => 'AppFailure($code): $userMessage';
}

/// True when [failure] means the backend cannot produce the structured
/// response envelope at all — the only codes that may trigger a legacy
/// fallback. Real contract defects (incoherence, wrong command, wrong
/// types) stay failures and must never fall back silently.
bool isBackendEnvelopeMissing(AppFailure failure) =>
    failure.kind == AppFailureKind.backendContract &&
    {
      'EMPTY_RESPONSE',
      'MALFORMED_JSON',
      'UNEXPECTED_SHAPE',
      'MISSING_SCHEMA_VERSION',
    }.contains(failure.code);
