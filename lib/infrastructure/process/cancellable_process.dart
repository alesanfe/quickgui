import 'dart:io';

/// Wraps a running process with kill-on-cancel semantics.
class CancellableProcess {
  CancellableProcess(this._process);
  final Process _process;

  void cancel() => _process.kill();
}
