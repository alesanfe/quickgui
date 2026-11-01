import 'dart:io';

import 'package:quickgui/infrastructure/process/host_platform.dart';
import 'package:quickgui/infrastructure/process/host_process.dart';

import 'process_runner.dart';

/// Real runner: escapes the Flatpak sandbox via flatpak-spawn when needed.
class SystemProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => runHost(executable, arguments, workingDirectory: workingDirectory);

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => Process.start(HostPlatform.isFlatpak ? 'flatpak-spawn' : executable, [
    if (HostPlatform.isFlatpak) ...[
      // --directory applies the cwd on the HOST side of the spawn,
      // where the ambient process cwd cannot reach.
      if (workingDirectory != null) '--directory=$workingDirectory',
      '--host',
      executable,
    ],
    ...arguments,
  ], workingDirectory: workingDirectory);
}
