import 'dart:io';

/// Host OS facts for conditional behaviour.
class HostPlatform {
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;
  static bool get isFlatpak =>
      File('/.flatpak-info').existsSync() ||
      Platform.environment.containsKey('FLATPAK_ID');
}
