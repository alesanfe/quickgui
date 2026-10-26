import 'package:freezed_annotation/freezed_annotation.dart';

part 'operation_state.freezed.dart';

/// Explicit state machine for long-running operations (download, delete,
/// import, start/stop). Replaces contradictory boolean combinations.
@freezed
sealed class OperationState<T> with _$OperationState<T> {
  const OperationState._();

  const factory OperationState.idle() = OperationIdle<T>;
  const factory OperationState.validating() = OperationValidating<T>;
  const factory OperationState.waitingForConfirmation() =
      OperationWaitingForConfirmation<T>;

  /// Accepted but not started yet (e.g. behind a concurrency limit or an
  /// explicit queue). No fake progress is reported in this state.
  const factory OperationState.queued() = OperationQueued<T>;
  const factory OperationState.running({double? progress, String? line}) =
      OperationRunning<T>;

  /// Temporarily suspended by the user or the backend while still
  /// occupying the resource. Distinct from a paused *VM*.
  const factory OperationState.paused({double? progress, String? line}) =
      OperationPaused<T>;
  const factory OperationState.cancelling() = OperationCancelling<T>;
  const factory OperationState.cancelled() = OperationCancelled<T>;
  const factory OperationState.succeeded(T value) = OperationSucceeded<T>;
  const factory OperationState.failed({
    required String code,
    required String message,
    @Default(false) bool retryable,
  }) = OperationFailed<T>;

  /// The app was closed or the backend was lost before the result could
  /// be confirmed. Terminal for UI purposes but NOT a definitive failure
  /// — the outcome must be reconciled or the operation retried safely.
  const factory OperationState.interrupted() = OperationInterrupted<T>;

  /// True while the operation occupies the VM / resource.
  bool get isBusy => switch (this) {
    OperationValidating() ||
    OperationQueued() ||
    OperationRunning() ||
    OperationPaused() ||
    OperationCancelling() => true,
    _ => false,
  };

  /// True once no further transition is expected. `interrupted` counts
  /// as terminal for UI purposes even though its real outcome is
  /// unknown until reconciled.
  bool get isTerminal => switch (this) {
    OperationSucceeded() ||
    OperationFailed() ||
    OperationCancelled() ||
    OperationInterrupted() => true,
    _ => false,
  };
}
