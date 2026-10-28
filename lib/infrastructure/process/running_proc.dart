import 'dart:io';

import '../../features/machines/application/ports/proc.dart';

/// Adapts a dart:io [Process] to the domain [RunningProc] port type —
/// the single place where the raw type crosses the boundary.
class SystemRunningProc implements RunningProc {
  const SystemRunningProc(this._process);
  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;
  @override
  Stream<List<int>> get stderr => _process.stderr;
  @override
  Future<int> get exitCode => _process.exitCode;
  @override
  bool kill() => _process.kill();
}
