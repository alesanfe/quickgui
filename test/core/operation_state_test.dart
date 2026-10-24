import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/operations/operation_state.dart';

void main() {
  test('busy and terminal flags are mutually consistent', () {
    const states = <OperationState<int>>[
      OperationState.idle(),
      OperationState.validating(),
      OperationState.waitingForConfirmation(),
      OperationState.running(progress: 0.5),
      OperationState.cancelling(),
      OperationState.cancelled(),
      OperationState.succeeded(1),
      OperationState.failed(code: 'X', message: 'boom'),
    ];
    for (final s in states) {
      expect(s.isBusy && s.isTerminal, isFalse, reason: '$s');
    }
    expect(states.where((s) => s.isBusy), hasLength(3));
    expect(states.where((s) => s.isTerminal), hasLength(3));
  });

  test('value equality and copyWith come from Freezed', () {
    const a = OperationState<int>.running(progress: 0.1);
    expect(a, const OperationState<int>.running(progress: 0.1));
    expect((a as OperationRunning<int>).copyWith(progress: 0.2).progress, 0.2);
  });
}
