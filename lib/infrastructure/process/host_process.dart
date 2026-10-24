import 'dart:io';

import 'package:quickgui/infrastructure/platform/host_platform.dart';

/// Runs [exe] with [args], escaping the Flatpak sandbox when needed so
/// commands execute on the host system.
Future<ProcessResult> runHost(String exe, List<String> args) {
  return HostPlatform.isFlatpak
      ? Process.run('flatpak-spawn', ['--host', exe, ...args])
      : Process.run(exe, args);
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
