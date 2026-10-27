import 'package:flutter/services.dart';

/// Loads the bundled `assets/icons/quickemu/*.svg` paths keyed by the OS
/// code derived from the filename.
Future<Map<String, String>> loadOsIcons() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final imagePaths = manifest
      .listAssets()
      .where((String key) => key.contains('icons/quickemu/'))
      .where((String key) => key.contains('.svg'));
  final icons = <String, String>{};
  for (final imagePath in imagePaths) {
    final String filename = imagePath.split('/').last;
    final int dot = filename.lastIndexOf('.');
    final String id = dot == -1 ? filename : filename.substring(0, dot);
    icons[id] = imagePath;
  }
  return icons;
}
