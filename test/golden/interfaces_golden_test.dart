@Tags(['golden'])
library;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/downloads/presentation/downloader_page.dart';
import 'package:quickgui/features/home/presentation/main_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

Widget _app({required Widget home, required bool dark}) => ProviderScope(
  overrides: [
    backendProvider.overrideWithValue(
      FakeVirtualizationBackend()
        ..available = true
        ..vms = ['ubuntu-24.04', 'windows-11', 'debian-12'],
    ),
    hostProbeProvider.overrideWithValue(FakeHostProbe()),
    preferencesRepositoryProvider.overrideWithValue(
      FakePreferencesRepository(),
    ),
    initialSettingsProvider.overrideWithValue(
      SettingsState(darkMode: dark, locale: 'es'),
    ),
  ],
  child: testApp(theme: dark ? AppTheme.dark() : AppTheme.light(), home: home),
);

void main() {
  const size = BoxConstraints.tightFor(width: 852, height: 819);

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => null,
        );
  });
  const pages = <String, Widget>{
    'main_menu': MainPage(),
    'machines_manager': Manager(),
    'downloader': DownloaderPage(),
  };

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    goldenTest(
      'interfaces ($theme)',
      fileName: 'interfaces_$theme',
      builder: () => GoldenTestGroup(
        columns: 1,
        children: [
          for (final e in pages.entries)
            GoldenTestScenario(
              name: e.key,
              constraints: size,
              child: _app(home: e.value, dark: dark),
            ),
        ],
      ),
    );
  }
}
