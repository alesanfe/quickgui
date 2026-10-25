@Tags(['golden'])
library;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

Widget _page({required bool dark, bool backendAvailable = true}) =>
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(
          FakeVirtualizationBackend()
            ..available = backendAvailable
            ..capabilities = {
              'schemaVersion': 1,
              'applicationVersion': '4.9.9',
              'capabilities': {'snapshots': true, 'safeDeletePlan': false},
            },
        ),
        hostProbeProvider.overrideWithValue(FakeHostProbe()),
      ],
      child: testApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: const DiagnosticsPage(),
      ),
    );

void main() {
  setUpAll(TestLocalizationsDelegate.preload);
  const scales = {'100%': 1.0, '150%': 1.5, '200%': 2.0};
  const size = BoxConstraints.tightFor(width: 720, height: 900);

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    goldenTest(
      'diagnostics page ($theme) at 100/150/200% text scale',
      fileName: 'diagnostics_page_$theme',
      builder: () => GoldenTestGroup(
        columns: 3,
        children: [
          for (final e in scales.entries)
            GoldenTestScenario.withTextScaleFactor(
              name: e.key,
              textScaler: TextScaler.linear(e.value),
              constraints: size,
              child: _page(dark: dark),
            ),
        ],
      ),
    );
  }

  goldenTest(
    'diagnostics page with backend missing',
    fileName: 'diagnostics_page_backend_missing',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'light',
          constraints: size,
          child: _page(dark: false, backendAvailable: false),
        ),
      ],
    ),
  );
}
