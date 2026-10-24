import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:quickgui/app/app.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/app_info/app_version.dart';
import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/features/catalog/application/load_catalog.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/settings/application/load_settings.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/infrastructure/persistence/shared_preferences_repository.dart';
import 'package:quickgui/infrastructure/process/host_process.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/shared/presentation/os_assets/osicons.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only a minimum size is enforced; the window stays resizable so lists,
  // dialogs and the config editor can use larger screens.
  await windowManager.ensureInitialized();
  final windowOptions = WindowOptions(
    minimumSize: Platform.isMacOS
        ? const Size(692 + 2, 580 + 30)
        : const Size(692, 580),
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
  final backend = QuickemuBackend(SystemProcessRunner());
  final foundQuickemu = await runHost('which', ['quickemu']);
  Future<List<OperatingSystem>>? osCatalogue;
  var osIcons = const <String, String>{};
  if (foundQuickGet.exitCode == 0 && foundQuickemu.exitCode == 0) {
    osCatalogue = loadOperatingSystems(backend);
    osIcons = await loadOsIcons();
    try {
      AppVersion.packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      debugPrint('Warning: Could not get package info: $e');
    }
  }

  // Load persisted settings before the first frame so theme and locale
  // are correct immediately (no FutureBuilder flash in App).
  final prefs = SharedPreferencesRepository();
  final loaded = await LoadSettings(
    prefs,
    supportedLocales: supportedLocales,
    systemLocale: Platform.localeName,
  )();
  final initialSettings = switch (loaded) {
    Ok(:final value) => value,
    _ => const SettingsState(),
  };
  runApp(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        osCatalogueProvider.overrideWithValue(osCatalogue),
        osIconsProvider.overrideWithValue(osIcons),
        preferencesRepositoryProvider.overrideWithValue(prefs),
        initialSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const App(),
    ),
  );
}
