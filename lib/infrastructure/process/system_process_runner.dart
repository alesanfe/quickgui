import 'dart:io';

import 'package:quickgui/app/globals.dart';

import 'process_runner.dart';

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
