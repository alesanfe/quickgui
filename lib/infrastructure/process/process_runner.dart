import 'dart:io';

export 'system_process_runner.dart';

/// Abstraction over external process execution so the backend can be
/// tested with fakes and so all quickemu invocations honour the Flatpak
/// sandbox escape.
abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
  Future<Process> start(String executable, List<String> arguments);
}
