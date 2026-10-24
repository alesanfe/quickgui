import 'package:flutter/material.dart';
import 'package:quickgui/core/operations/operation_state.dart';

class DownloadProgressBar extends StatelessWidget {
  const DownloadProgressBar({required this.state, super.key});

  final OperationState<Object?> state;

  @override
  Widget build(BuildContext context) {
    final progress = switch (state) {
      OperationSucceeded() => 1.0,
      OperationRunning(progress: final p?) => p,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        width: 200,
        child: LinearProgressIndicator(value: progress),
      ),
    );
  }
}
