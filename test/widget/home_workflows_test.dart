import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/create/presentation/create_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/home/presentation/dashboard_page.dart';
import 'package:quickgui/features/settings/presentation/settings_page.dart';
import 'package:quickgui/features/machines/presentation/details/vm_config_editor.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/shared/widgets/dependency_warning.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_process.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

import 'package:quickgui/features/machines/application/ports/proc.dart';

OperatingSystem os(
  String name,
  String code, [
  List<Version> versions = const [],
]) => OperatingSystem(name, code)..versions.addAll(versions);

Version ver(String v, [List<Option> options = const []]) =>
    Version(v)..options.addAll(options);

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late Directory directory;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeHostProbe host;

  setUp(() {
    original = Directory.current;
    directory = Directory.systemTemp.createTempSync('qg-home-');
    Directory.current = directory;
    backend = FakeVirtualizationBackend();
    preferences = FakePreferencesRepository();
    host = FakeHostProbe()..dir = directory.path;
  });

  tearDown(() {
    Directory.current = original;
    directory.deleteSync(recursive: true);
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> open(
    WidgetTester tester,
    Widget home, {
    List<OperatingSystem> catalogue = const [],
    bool fullPage = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(host),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          osIconsProvider.overrideWithValue({}),
          osCatalogueProvider.overrideWithValue(Future.value(catalogue)),
        ],
        child: testApp(
          home: fullPage ? home : Scaffold(body: Row(children: [home])),
        ),
      ),
    );
    await flush(tester);
  }

  group('CreatePage — working directory', () {
    testWidgets('honours the stored working directory preference', (
      tester,
    ) async {
      final stored = Directory.systemTemp.createTempSync('qg-pref-');
      addTearDown(stored.deleteSync);
      preferences.store[prefWorkingDirectory] = stored.path;
      await open(tester, const CreatePage(), fullPage: true);
      expect(find.text(stored.path), findsOneWidget);
      expect(Directory.current.path, stored.path);
      Directory.current = directory;
    });

    testWidgets('falls back to a writable directory when cwd is not', (
      tester,
    ) async {
      final fallback = Directory.systemTemp.createTempSync('qg-fallback-');
      addTearDown(fallback.deleteSync);
      host
        ..writable = false
        ..fallbackDir = fallback.path;
      await open(tester, const CreatePage(), fullPage: true);
      expect(Directory.current.path, fallback.path);
      expect(preferences.store[prefWorkingDirectory], fallback.path);
      Directory.current = directory;
    });
  });

  group('DownloadControls', () {
    final catalogue = [
      os('Ubuntu', 'ubuntu', [
        ver('24.04', [Option('', 'curl')]),
        ver('22.04', [Option('', 'curl')]),
      ]),
      os('macOS', 'macos', [
        ver('sonoma', [Option('', 'curl')]),
      ]),
      os('Windows 11', 'windows-11', [
        ver('23h2', [Option('', 'curl')]),
      ]),
    ];

    Future<void> pick(
      WidgetTester tester, {
      String osName = 'Ubuntu',
      String version = '24.04',
    }) async {
      await tester.tap(find.text('Select...').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(osName).last);
      await tester.pumpAndSettle();
      // Single-version operating systems auto-select the version.
      if (find.text('Select...').evaluate().isEmpty) return;
      await tester.tap(find.text('Select...').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(version).last);
      await tester.pumpAndSettle();
    }

    testWidgets('selects an OS and version before enabling download', (
      tester,
    ) async {
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      final download = find.widgetWithText(ElevatedButton, 'Download');
      expect(tester.widget<ElevatedButton>(download).onPressed, isNull);

      await tester.tap(find.text('Select...').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('macOS').last);
      await tester.pumpAndSettle();
      // Single version+option is auto-selected.
      expect(find.textContaining('sonoma'), findsWidgets);
      expect(tester.widget<ElevatedButton>(download).onPressed, isNotNull);
    });

    testWidgets('macOS CPU requirement blocks the download flow', (
      tester,
    ) async {
      host.missingMacos = ['sse4_2', 'avx2'];
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      await tester.tap(find.text('Select...').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('macOS').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('requires a CPU with SSE4 2 and AVX2'),
        findsOneWidget,
      );
      expect(backend.quickgetCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('windows without swtpm shows a TPM requirement error', (
      tester,
    ) async {
      host.tools = {};
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      await pick(tester, osName: 'Windows 11', version: '23h2');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      expect(find.textContaining('swtpm was not found'), findsOneWidget);
      expect(backend.quickgetCalls, isEmpty);
    });

    testWidgets('unwritable directory blocks before any backend call', (
      tester,
    ) async {
      final fallback = Directory.systemTemp.createTempSync('qg-fallback-');
      addTearDown(fallback.deleteSync);
      host
        ..writable = false
        ..fallbackDir = fallback.path;
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      Directory.current = directory;
      await pick(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not write'), findsOneWidget);
      expect(backend.quickgetCalls, isEmpty);
    });

    testWidgets('an unavailable image reports the backend check failure', (
      tester,
    ) async {
      backend.lastActionResult = const ProcResult(4, '', 'gone');
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      await pick(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      expect(backend.quickgetCalls, [
        ['--check', 'ubuntu', '24.04'],
      ]);
      expect(find.textContaining('currently unavailable'), findsOneWidget);
    });

    testWidgets('a passing check offers customisation then hands off to '
        'the activity centre', (tester) async {
      backend.downloadProcess = FakeProcess();
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      await pick(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      expect(find.text('Customise VM (optional)'), findsOneWidget);

      // Empty RAM disables the confirm button (validation).
      await tester.enterText(
        find.widgetWithText(TextFormField, 'RAM'),
        'bogus',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Download'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'RAM'), '8G');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'CPU cores'),
        '4',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Download'));
      // The task starts in the activity centre and the UI navigates to it
      // (plain Navigator fallback when no GoRouter is in the tree).
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(ActivityPage), findsOneWidget);
      expect(backend.downloadCalls, [
        ['ubuntu', '24.04', ''],
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling customisation does not start a download', (
      tester,
    ) async {
      await open(
        tester,
        const CreatePage(),
        catalogue: catalogue,
        fullPage: true,
      );
      await pick(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivityPage), findsNothing);
      expect(backend.downloadCalls, isEmpty);
    });
  });

  group('SettingsPage — versions', () {
    testWidgets('renders application and backend versions', (tester) async {
      backend.backendVersion = '4.9.7';
      await open(tester, const SettingsPage(), fullPage: true);
      // '2.0.0' in the About tile ('Version {0} — Powered by Quickemu')
      // and '4.9.7' in the Backend version tile.
      expect(find.textContaining('2.0.0'), findsWidgets);
      expect(find.textContaining('4.9.7'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('DependencyWarning', () {
    testWidgets('shows a warning when the backend is missing', (tester) async {
      backend.available = false;
      await open(
        tester,
        const SizedBox(width: 800, child: DependencyWarning()),
      );
      expect(find.textContaining('Quickemu was not found'), findsOneWidget);
      expect(find.text('Open diagnostics'), findsOneWidget);
    });

    testWidgets('stays hidden when the backend is available', (tester) async {
      await open(
        tester,
        const SizedBox(width: 800, child: DependencyWarning()),
      );
      expect(find.textContaining('Quickemu was not found'), findsNothing);
    });
  });

  group('DashboardPage navigation', () {
    Future<void> openDashboard(
      WidgetTester tester, {
      required Map<String, GoRouterWidgetBuilder> stubs,
    }) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          for (final e in stubs.entries) GoRoute(path: e.key, builder: e.value),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            hostProbeProvider.overrideWithValue(host),
            preferencesRepositoryProvider.overrideWithValue(preferences),
            osIconsProvider.overrideWithValue({}),
            osCatalogueProvider.overrideWithValue(Future.value([])),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            supportedLocales: const [Locale('en')],
            localizationsDelegates: const [
              TestLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
          ),
        ),
      );
      await flush(tester);
    }

    testWidgets('navigates to the machines library', (tester) async {
      backend
        ..vms = []
        ..capabilities = {'capabilities': <String, dynamic>{}};
      await openDashboard(
        tester,
        stubs: {
          '/machines': (context, state) =>
              const Scaffold(body: Text('ROUTE /machines')),
        },
      );
      await tester.tap(find.byKey(const ValueKey('nav.machines')));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE /machines'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigates to the create flow', (tester) async {
      backend.vms = [];
      await openDashboard(
        tester,
        stubs: {
          '/create': (context, state) =>
              const Scaffold(body: Text('ROUTE /create')),
        },
      );
      await tester.tap(find.byKey(const ValueKey('nav.create-machine')));
      await tester.pumpAndSettle();
      expect(find.text('ROUTE /create'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('VmConfigEditorDialog', () {
    testWidgets('loads the conf file and saves edits back', (tester) async {
      File('${directory.path}/linux-test.conf')
          .writeAsStringSync('guest_os="linux"\nram="4G"\n');
      await open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => VmConfigEditorDialog(
                vmName: 'linux-test',
                confPath: '${directory.path}/linux-test.conf',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // loadRaw is real file I/O chained with FakeAsync microtasks;
      // interleave frame pumps and real event-loop time to drain it.
      for (var i = 0; i < 6; i++) {
        await flush(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      }
      await flush(tester);
      expect(find.text('Edit VM: linux-test'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'guest_os="linux"\nram="8G"\n',
      );
      await tester.tap(find.text('Save'));
      // The atomic save pipeline (temp+verify+backup+rename) is several
      // real file IOs — give it a larger drain budget than the old single
      // write needed.
      for (var i = 0; i < 10; i++) {
        await flush(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      }
      await flush(tester);
      expect(
        File('${directory.path}/linux-test.conf').readAsStringSync(),
        contains('ram="8G"'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects malformed lines and reports the line number', (
      tester,
    ) async {
      final confPath = '${directory.path}/linux-test.conf';
      File(confPath).writeAsStringSync('guest_os="linux"\nram="4G"\n');
      await open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => VmConfigEditorDialog(
                vmName: 'linux-test',
                confPath: confPath,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await flush(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      }
      await flush(tester);
      await tester.enterText(
        find.byType(TextField).first,
        'guest_os="linux"\nnot a conf line\n',
      );
      await tester.tap(find.text('Save'));
      await flush(tester);
      // Save is blocked: the dialog stays open, shows the error and the
      // file on disk is untouched.
      expect(find.text('Line 2: expected key="value".'), findsOneWidget);
      expect(File(confPath).readAsStringSync(), contains('ram="4G"'));
      // Editing the text dismisses the error.
      await tester.enterText(
        find.byType(TextField).first,
        'guest_os="linux"\nram="4G"\n',
      );
      await flush(tester);
      expect(find.textContaining('expected key='), findsNothing);
    });

    testWidgets('an external change offers conflict resolution', (
      tester,
    ) async {
      final confPath = '${directory.path}/linux-test.conf';
      File(confPath).writeAsStringSync('guest_os="linux"\nram="4G"\n');
      await open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => VmConfigEditorDialog(
                vmName: 'linux-test',
                confPath: confPath,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 6; i++) {
        await flush(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      }
      await flush(tester);
      // Simulate an external edit after the editor captured its fingerprint.
      File(confPath).writeAsStringSync('guest_os="linux"\nram="2G"\n');
      await tester.tap(find.text('Save'));
      // The conflict check re-reads the file — real IO needs real event
      // loop time alongside the fake-async pumps.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await flush(tester);
      }
      expect(find.textContaining('changed outside Quickgui'), findsOneWidget);
      await tester.tap(find.text('Reload from disk'));
      await flush(tester);
      // The editor buffer was replaced by the disk version.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, contains('ram="2G"'));
      // The fingerprint was refreshed, so saving now works silently.
      await tester.tap(find.text('Save'));
      for (var i = 0; i < 6; i++) {
        await flush(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      }
      await flush(tester);
      expect(File(confPath).readAsStringSync(), contains('ram="2G"'));
      expect(tester.takeException(), isNull);
    });
  });
}
