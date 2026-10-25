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
  const factory OperationState.running({double? progress, String? line}) =
      OperationRunning<T>;
  const factory OperationState.cancelling() = OperationCancelling<T>;
  const factory OperationState.cancelled() = OperationCancelled<T>;
  const factory OperationState.succeeded(T value) = OperationSucceeded<T>;
  const factory OperationState.failed({
    required String code,
    required String message,
    @Default(false) bool retryable,
  }) = OperationFailed<T>;

  /// True while the operation occupies the VM / resource.
  bool get isBusy => switch (this) {
    OperationValidating() ||
    OperationRunning() ||
    OperationCancelling() => true,
    _ => false,
  };

  /// True once no further transition is expected.
  bool get isTerminal => switch (this) {
    OperationSucceeded() || OperationFailed() || OperationCancelled() => true,
    _ => false,
  };
}
