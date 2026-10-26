import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/create/presentation/create_wizard_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeHostProbe host;

  setUp(() {
    backend = FakeVirtualizationBackend();
    preferences = FakePreferencesRepository();
    host = FakeHostProbe()..dir = Directory.systemTemp.path;
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(host),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          osIconsProvider.overrideWithValue({}),
          osCatalogueProvider.overrideWithValue(
            Future.value(const <OperatingSystem>[]),
          ),
        ],
        child: testApp(home: const CreateWizardPage()),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('renders the five steps with the origin choice', (tester) async {
    await open(tester);
    for (final title in [
      'Origin',
      'System',
      'Resources',
      'Integration',
      'Review',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Download with quickget'), findsOneWidget);
    expect(find.text('Import a disk image'), findsOneWidget);
  });

  testWidgets('import origin advances to the system guidance', (tester) async {
    await open(tester);
    await tester.tap(find.text('Import a disk image'));
    await tester.pump();
    await tester.tap(find.text('Continue').first);
    await tester.pump();
    expect(
      find.text('You will pick the disk image at the end.'),
      findsOneWidget,
    );
  });

  testWidgets('resources step shows profile and conf fields', (tester) async {
    await open(tester);
    await tester.tap(find.text('Import a disk image'));
    await tester.pump();
    await tester.tap(find.text('Continue').first); // → System
    await tester.pump();
    await tester.tap(find.text('Continue').first); // → Resources
    await tester.pump();
    expect(find.text('Profile'), findsWidgets);
    expect(find.text('RAM'), findsOneWidget);
    expect(find.text('CPU cores'), findsOneWidget);
    expect(find.text('Disk size'), findsOneWidget);
  });
}
