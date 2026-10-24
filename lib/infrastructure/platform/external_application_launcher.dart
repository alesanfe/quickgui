import 'dart:io';

/// Launches external desktop tools (file manager, terminal, viewer).
class ExternalApplicationLauncher {
  static Future<bool> openFolder(String path) async {
    final cmd = Platform.isMacOS ? 'open' : 'xdg-open';
    return (await Process.run(cmd, [path])).exitCode == 0;
  }
}
