import 'package:quickgui/domain/operations/operation_state.dart'
    show OperationState;

/// Progress info for an [OperationState.running] operation.
class OperationProgress {
  const OperationProgress({this.percent, this.line});
  final double? percent;
  final String? line;
}
