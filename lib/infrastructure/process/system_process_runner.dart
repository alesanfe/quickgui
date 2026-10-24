import 'dart:io';

import 'package:quickgui/infrastructure/platform/host_platform.dart';
import 'package:quickgui/infrastructure/process/host_process.dart';

import 'process_runner.dart';

/// Real runner: escapes the Flatpak sandbox via flatpak-spawn when needed.
class SystemProcessRunner implements ProcessRunner {
  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      runHost(executable, arguments);

  @override
  Future<Process> start(String executable, List<String> arguments) =>
      Process.start(HostPlatform.isFlatpak ? 'flatpak-spawn' : executable, [
        if (HostPlatform.isFlatpak) '--host',
        executable,
        ...arguments,
      ]);
}
