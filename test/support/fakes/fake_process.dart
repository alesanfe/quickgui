import 'dart:async';
import 'dart:convert';

import 'package:quickgui/features/machines/application/ports/proc.dart';

/// Controllable [RunningProc] test double: tests push stdout/stderr chunks
/// and complete the exit code explicitly (or via [kill]).
///
/// Streams are synchronous so an `emit` reaches widget listeners
/// immediately; `finish` completes the exit code without awaiting stream
/// closure (which would otherwise race FakeAsync microtask flushes).
class FakeProcess implements RunningProc {
  final _stdout = StreamController<List<int>>(sync: true);
  final _stderr = StreamController<List<int>>(sync: true);
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  void emitOut(String chunk) => _stdout.add(utf8.encode(chunk));

  void emitErr(String chunk) => _stderr.add(utf8.encode(chunk));

  /// Complete [exitCode] with [code] and close the output streams.
  void finish(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    _stdout.close();
    _stderr.close();
  }

  @override
  bool kill() {
    killed = true;
    finish(-9);
    return true;
  }
}
