import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider_pkg;
import 'package:tuple/tuple.dart';
import 'package:window_manager/window_manager.dart';

import 'package:quickgui/app/app.dart';
import 'package:quickgui/app/globals.dart';
import 'package:quickgui/infrastructure/app_info/app_version.dart';
import 'package:quickgui/app/settings/app_settings.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/shared/presentation/os_assets/osicons.dart';
import 'package:quickgui/features/catalog/domain/version.dart';

Future<List<OperatingSystem>> loadOperatingSystems(bool showUbuntus) async {
  final rows = await backend.listOperatingSystems();
  const stdout = '';
  final output = <OperatingSystem>[];
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
      final t5 = [
        chunks[0],
        chunks[1],
        chunks[2],
        chunks[3],
        chunks[4],
      ].toList();
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
    final String filename = imagePath.split('/').last;
    final String id = filename.substring(0, filename.lastIndexOf('.'));
    osIcons[id] = imagePath;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only a minimum size is enforced; the window stays resizable so lists,
  // dialogs and the config editor can use larger screens.
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    minimumSize: Platform.isMacOS ? const Size(692 + 2, 580 + 30) : const Size(692, 580),
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

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
    ProviderScope(
      child: provider_pkg.MultiProvider(
        providers: [provider_pkg.ChangeNotifierProvider(create: (_) => AppSettings())],
        builder: (context, _) => const App(),
      ),
    ),
  );
}
