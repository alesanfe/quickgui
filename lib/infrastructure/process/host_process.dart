import 'dart:io';

import 'package:quickgui/infrastructure/process/host_platform.dart';

/// Runs [exe] with [args], escaping the Flatpak sandbox when needed so
/// commands execute on the host system. [workingDirectory] applies to
/// the spawned process — on Flatpak via `--directory`, which sets the
/// cwd on the host side of the spawn.
Future<ProcessResult> runHost(
  String exe,
  List<String> args, {
  String? workingDirectory,
}) {
  return HostPlatform.isFlatpak
      ? Process.run('flatpak-spawn', [
          if (workingDirectory != null) '--directory=$workingDirectory',
          '--host',
          exe,
          ...args,
        ], workingDirectory: workingDirectory)
      : Process.run(exe, args, workingDirectory: workingDirectory);
}

/// Prefix a shell command so it runs on the host when sandboxed.
String hostWrap(String command) {
  return HostPlatform.isFlatpak ? 'flatpak-spawn --host $command' : command;
}

/// True if [binary] is found on PATH.
Future<bool> commandAvailable(String binary) async {
  final result = await runHost('which', [binary]);
  return result.exitCode == 0;
}
