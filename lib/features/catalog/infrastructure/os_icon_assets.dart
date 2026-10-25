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
    final String id = filename.substring(0, filename.lastIndexOf('.'));
    icons[id] = imagePath;
  }
  return icons;
}
