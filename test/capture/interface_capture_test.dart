@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/downloads/presentation/downloader_page.dart';
import 'package:quickgui/features/home/presentation/main_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

/// Real fonts so text and icons render as in the app — every family declared
/// in FontManifest.json (Roboto via alchemist, MaterialIcons, package fonts).
Future<void> _loadAllFonts() async {
  final bundle = rootBundle;
  List<dynamic> manifest;
  try {
    manifest = json.decode(
      await bundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
  } catch (_) {
    manifest = const [];
  }
  for (final e in manifest) {
    final entry = e as Map<String, dynamic>;
    var family = entry['family'] as String;
    if (family.startsWith('packages/alchemist/')) {
      family = family.substring('packages/alchemist/'.length);
    }
    final loader = FontLoader(family);
    for (final f in entry['fonts'] as List<dynamic>) {
      loader.addFont(
        bundle.load((f as Map<String, dynamic>)['asset'] as String),
      );
    }
    try {
      await loader.load();
    } catch (_) {
      // Asset unavailable in the test bundle — fall back below.
    }
  }
  // Explicit fallbacks: Roboto ships with alchemist, MaterialIcons with the
  // framework.
  for (final (family, assets) in [
    (
      'Roboto',
      [
        'Regular',
        'Medium',
        'Bold',
      ].map((w) => 'packages/alchemist/assets/fonts/Roboto/Roboto-$w.ttf'),
    ),
    ('MaterialIcons', ['fonts/MaterialIcons-Regular.otf'].map((p) => p)),
  ]) {
    final loader = FontLoader(family);
    var added = false;
    for (final a in assets) {
      try {
        loader.addFont(bundle.load(a));
        added = true;
      } catch (_) {}
    }
    if (added) {
      try {
        await loader.load();
      } catch (_) {}
    }
  }
}

/// Temp dir with minimal valid .conf files so the Manager lists VMs
/// (it scans Directory.current pointed to by the workingDirectory pref).
final Directory _vmDir = Directory.systemTemp.createTempSync('qg_vms');

Widget _app({
  required Widget home,
  required bool dark,
  bool backendAvailable = true,
}) => ProviderScope(
  overrides: [
    backendProvider.overrideWithValue(
      FakeVirtualizationBackend()
        ..available = backendAvailable
        ..vms = ['ubuntu-24.04', 'windows-11', 'debian-12']
        ..capabilities = {
          'schemaVersion': 1,
          'applicationVersion': '4.9.9',
          'capabilities': {'snapshots': true, 'safeDeletePlan': false},
        },
    ),
    hostProbeProvider.overrideWithValue(FakeHostProbe()),
    preferencesRepositoryProvider.overrideWithValue(
      FakePreferencesRepository()..store['workingDirectory'] = _vmDir.path,
    ),
    initialSettingsProvider.overrideWithValue(SettingsState(darkMode: dark)),
  ],
  child: testApp(theme: dark ? AppTheme.dark() : AppTheme.light(), home: home),
);

Future<void> _capture(WidgetTester t, Widget widget, String name) async {
  t.view.physicalSize = windowSize;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(widget);
  await t.pumpAndSettle(const Duration(seconds: 2));
  // A few extra frames so provider streams and icons finish painting.
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  // matchesGoldenFile rasterizes the whole window via captureImage; run with
  // --update-goldens so the PNG is written next to this file under out/.
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('out/$name.png'),
  );
}

const windowSize = Size(912, 800);

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => null,
        );
    for (final name in ['ubuntu-24.04', 'windows-11', 'debian-12']) {
      File('${_vmDir.path}/$name.conf')
          .writeAsStringSync('guest_os="linux"\ndisk_img="$name/disk.qcow2"\n');
      Directory('${_vmDir.path}/$name').createSync();
    }
    await _loadAllFonts();
  });

  final pages = <String, Widget>{
    '02_machines_manager': const Manager(),
    '01_main_menu': const MainPage(),
    '03_downloader': const DownloaderPage(),
    '04_diagnostics': const DiagnosticsPage(),
  };

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final e in pages.entries) {
      testWidgets('${e.key} ($theme)', (t) async {
        await _capture(t, _app(home: e.value, dark: dark), '${e.key}_$theme');
      });
    }
  }
}
