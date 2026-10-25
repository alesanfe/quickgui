import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/home/presentation/home_page_button_group.dart';
import 'package:quickgui/features/home/presentation/downloader_page_button.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

OperatingSystem osFixture(String code, {bool multiple = false}) {
  final os = OperatingSystem(code.toUpperCase(), code);
  os.versions.add(Version('24.04')..options.add(Option('desktop', 'curl')));
  if (multiple) {
    os.versions.add(
      Version('22.04')
        ..options.addAll([Option('server', 'curl'), Option('minimal', 'curl')]),
    );
  }
  return os;
}

class CatalogueScreen {
  CatalogueScreen(this.tester);
  final WidgetTester tester;
  Future<void> select(String text) async {
    final button = find.byWidgetPredicate(
      (widget) => widget is DownloaderPageButton && widget.label == text,
    );
    final target = button.evaluate().isNotEmpty
        ? find.descendant(of: button, matching: find.byType(ElevatedButton))
        : find.text(text).last;
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> chooseOs(String name) async {
    await select('Operating system');
    await select(name);
  }
}

void main() {
  setUpAll(TestLocalizationsDelegate.preload);
  late FakeHostProbe host;
  late FakeVirtualizationBackend backend;
  late List<OperatingSystem> catalogue;

  setUp(() {
    host = FakeHostProbe();
    backend = FakeVirtualizationBackend();
    catalogue = [
      osFixture('ubuntu', multiple: true),
      osFixture('windows'),
      osFixture('macos'),
    ];
  });

  Future<CatalogueScreen> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          osCatalogueProvider.overrideWithValue(Future.value(catalogue)),
          osIconsProvider.overrideWithValue({}),
          hostProbeProvider.overrideWithValue(host),
          backendProvider.overrideWithValue(backend),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: testApp(home: const Scaffold(body: HomePageButtonGroup())),
      ),
    );
    await tester.pumpAndSettle();
    return CatalogueScreen(tester);
  }

  testWidgets('OS search is case insensitive and handles no results', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.select('Operating system');
    expect(find.text('UBUNTU'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wIn');
    await tester.pump();
    expect(find.text('WINDOWS'), findsOneWidget);
    expect(find.text('UBUNTU'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nonexistent');
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('multiple versions and editions return the selected pair', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseOs('UBUNTU');
    await screen.select('Version');
    await tester.enterText(find.byType(TextField), '22.');
    await tester.pump();
    expect(find.text('24.04'), findsNothing);
    await screen.select('22.04');
    await screen.select('minimal');
    expect(find.text('22.04 (minimal)'), findsOneWidget);
    expect(find.byType(HomePageButtonGroup), findsOneWidget);
  });

  testWidgets('single edition is selected without another route', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseOs('UBUNTU');
    await screen.select('Version');
    await screen.select('24.04');
    expect(find.text('24.04 (desktop)'), findsOneWidget);
  });

  testWidgets('large edition lists expose a working search field', (
    tester,
  ) async {
    catalogue = [osFixture('ubuntu', multiple: true)];
    catalogue.first.versions.last.options.addAll(
      List.generate(8, (i) => Option('edition-$i', 'curl')),
    );
    final screen = await open(tester);
    await screen.chooseOs('UBUNTU');
    await screen.select('Version');
    await screen.select('22.04');
    await tester.enterText(find.byType(TextField), 'EDITION-7');
    await tester.pump();
    expect(find.text('edition-7'), findsOneWidget);
    expect(find.text('server'), findsNothing);
    await screen.select('edition-7');
    expect(find.text('22.04 (edition-7)'), findsOneWidget);
  });

  testWidgets(
    'nonwritable destination blocks download and explains the error',
    (tester) async {
      host.writable = false;
      final screen = await open(tester);
      await screen.chooseOs('WINDOWS');
      await screen.select('Download');
      expect(find.textContaining('Could not write'), findsOneWidget);
      await screen.select('OK');
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'Windows requires swtpm before opening the customization wizard',
    (tester) async {
      final screen = await open(tester);
      await screen.chooseOs('WINDOWS');
      await screen.select('Download');
      expect(find.textContaining('swtpm was not found'), findsOneWidget);
      expect(find.text('Customise VM (optional)'), findsNothing);
      await screen.select('OK');
    },
  );

  testWidgets('macOS missing CPU features are displayed before download', (
    tester,
  ) async {
    host.missingMacos = ['sse4_2', 'avx2'];
    final screen = await open(tester);
    await screen.chooseOs('MACOS');
    await screen.select('Download');
    expect(find.textContaining('SSE4 2 and AVX2'), findsOneWidget);
    await screen.select('OK');
  });

  testWidgets('unavailable image fails before customization', (tester) async {
    backend.lastActionResult = ProcessResult(0, 1, '', 'unavailable');
    final screen = await open(tester);
    await screen.chooseOs('MACOS');
    await screen.select('Download');
    expect(
      find.text('The selected image is currently unavailable.'),
      findsOneWidget,
    );
    await screen.select('OK');
  });

  testWidgets('customization validates RAM CPU and disk and can be cancelled', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseOs('MACOS');
    await screen.select('Download');
    expect(find.text('Customise VM (optional)'), findsOneWidget);
    final fields = find.byType(TextFormField);
    for (var i = 0; i < 3; i++) {
      await tester.enterText(fields.at(i), 'invalid');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Download').last,
            )
            .onPressed,
        isNull,
      );
    }
    await screen.select('Cancel');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('empty catalogue renders an empty selectable list', (
    tester,
  ) async {
    catalogue = [];
    final screen = await open(tester);
    await screen.select('Operating system');
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending catalogue displays a loading state until it completes', (
    tester,
  ) async {
    final completer = Completer<List<OperatingSystem>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [osCatalogueProvider.overrideWithValue(completer.future)],
        child: testApp(home: const OperatingSystemSelection()),
      ),
    );
    await tester.pump();
    expect(find.text('Loading available downloads'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
