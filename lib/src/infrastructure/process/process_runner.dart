import 'dart:io';

import '../../globals.dart';

/// Abstraction over external process execution so the backend can be
/// tested with fakes and so all quickemu invocations honour the Flatpak
/// sandbox escape.
abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
  Future<Process> start(String executable, List<String> arguments);
}

/// Real runner: escapes the Flatpak sandbox via flatpak-spawn when needed.
class SystemProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      runHost(executable, arguments);

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(inFlatpak ? 'flatpak-spawn' : executable, [
        if (inFlatpak) '--host',
        executable,
        ...arguments,
      ]);
}
