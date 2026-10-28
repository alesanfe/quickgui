@Tags(['golden'])
library;

import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/create/presentation/create_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/home/presentation/dashboard_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

/// Fixed machine library for the dashboard scenario — the real provider
/// scans the process working directory, which is not deterministic on CI.
final _goldMachines = <LibraryMachine>[
  const LibraryMachine(
    name: 'ubuntu-24.04',
    confPath: '/vms/ubuntu-24.04.conf',
    state: 'running',
    values: {'cpu_cores': '4', 'ram': '4G'},
    pid: 42424,
  ),
  const LibraryMachine(
    name: 'windows-11',
    confPath: '/vms/windows-11.conf',
    state: 'stopped',
    values: {'cpu_cores': '8', 'ram': '8G'},
  ),
  const LibraryMachine(
    name: 'debian-12',
    confPath: '/vms/debian-12.conf',
    state: 'paused',
    values: {'cpu_cores': '2', 'ram': '2G'},
  ),
];

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
    vmLibraryProvider.overrideWith((ref) async => _goldMachines),
  ],
  child: testApp(theme: dark ? AppTheme.dark() : AppTheme.light(), home: home),
);

/// Fixed machines directory so `Directory.current.path` labels (Manager
/// footer, Settings working-dir row) render identically on every host —
/// the goldens are checkout-location independent.
final Directory _goldVmDir = Directory('/tmp/qg_golden_vms');

void _resetVmDir() {
  if (_goldVmDir.existsSync()) _goldVmDir.deleteSync(recursive: true);
  _goldVmDir.createSync(recursive: true);
  for (final name in ['ubuntu-24.04', 'windows-11', 'debian-12']) {
    File('${_goldVmDir.path}/$name.conf')
        .writeAsStringSync('guest_os="linux"\ndisk_img="$name/disk.qcow2"\n');
    Directory('${_goldVmDir.path}/$name').createSync();
  }
  Directory.current = _goldVmDir;
}

void main() {
  const size = BoxConstraints.tightFor(width: 852, height: 819);

  setUpAll(() async {
    _resetVmDir();
    await TestLocalizationsDelegate.preload();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => null,
        );
  });
  const pages = <String, Widget>{
    'dashboard': DashboardPage(),
    'machines_manager': Manager(),
    'create': CreatePage(),
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
