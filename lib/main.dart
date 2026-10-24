import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:tuple/tuple.dart';
import 'package:window_size/window_size.dart';

import 'package:quickgui/app/app.dart';
import 'package:quickgui/app/globals.dart';
import 'package:quickgui/application/app_version.dart';
import 'package:quickgui/domain/common/app_settings.dart';
import 'package:quickgui/domain/catalog/operating_system.dart';
import 'package:quickgui/domain/catalog/option.dart';
import 'package:quickgui/domain/catalog/osicons.dart';
import 'package:quickgui/domain/catalog/version.dart';

Future<List<OperatingSystem>> loadOperatingSystems(bool showUbuntus) async {
  final rows = await backend.listOperatingSystems();
  var stdout = '';
  var output = <OperatingSystem>[];
  OperatingSystem? currentOperatingSystem;
  Version? currentVersion;

  final lines = rows.isEmpty
      ? stdout
            .split('\n')
            .skip(1)
            .where((element) => element.isNotEmpty)
            .map((e) => e.trim())
            .map((e) => e.split(','))
            .toList()
      : rows;
  for (final chunks in lines) {
    Tuple5<String, String, String, String, String> supportedVersion;
    final chunksTyped = chunks.cast<String>();
    if (chunksTyped.length == 4) // Legacy version of quickget
    {
      supportedVersion = Tuple5.fromList([...chunksTyped, "curl"]);
    } else {
      var t5 = [chunks[0], chunks[1], chunks[2], chunks[3], chunks[4]].toList();
      supportedVersion = Tuple5.fromList(t5);
    }

    if (currentOperatingSystem?.code != supportedVersion.item2) {
      currentOperatingSystem = OperatingSystem(
        supportedVersion.item1,
        supportedVersion.item2,
      );
      output.add(currentOperatingSystem);
      currentVersion = null;
    }
    if (currentVersion?.version != supportedVersion.item3) {
      currentVersion = Version(supportedVersion.item3);
      currentOperatingSystem!.versions.add(currentVersion);
    }
    currentVersion!.options.add(
      Option(supportedVersion.item4, supportedVersion.item5),
    );
  }

  return output;
}

Future<void> getIcons() async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final imagePaths = manifest
      .listAssets()
      .where((String key) => key.contains('quickemu-icons/'))
      .where((String key) => key.contains('.svg'))
      .toList();
  for (final imagePath in imagePaths) {
    String filename = imagePath.split('/').last;
    String id = filename.substring(0, filename.lastIndexOf('.'));
    osIcons[id] = imagePath;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only a minimum size is enforced; the window stays resizable so lists,
  // dialogs and the config editor can use larger screens.
  if (Platform.isMacOS) {
    setWindowMinSize(const Size(692 + 2, 580 + 30));
  } else {
    setWindowMinSize(const Size(692, 580));
  }

  var foundQuickGet = await runHost('which', ['quickget']);
  // Apps launched from Finder/desktop environments have a minimal PATH that
  // usually excludes the Homebrew prefixes, so check them explicitly.
  if (foundQuickGet.exitCode != 0) {
    for (final dir in ['/opt/homebrew/bin', '/usr/local/bin']) {
      if (File('$dir/quickget').existsSync()) {
        Platform.environment['PATH'] =
            '$dir:${Platform.environment['PATH'] ?? ''}';
        foundQuickGet = await runHost('which', ['quickget']);
        break;
      }
    }
  }
  // quickget and quickemu ship together; check both in case of a broken
  // or partial installation.
  final foundQuickemu = await runHost('which', ['quickemu']);
  if (foundQuickGet.exitCode == 0 && foundQuickemu.exitCode == 0) {
    gOperatingSystems = loadOperatingSystems(false);
    await getIcons();
    try {
      AppVersion.packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('Warning: Could not get package info: $e');
    }
  }

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppSettings())],
      builder: (context, _) => const App(),
    ),
  );
}
