import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/downloads/presentation/downloader.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_process.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late Directory directory;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeProcess process;

  final ubuntu = OperatingSystem('Ubuntu', 'ubuntu');
  final version = Version('24.04');
  final option = Option('', 'curl');

  setUp(() {
    original = Directory.current;
    directory = Directory.systemTemp.createTempSync('qg-download-');
    Directory.current = directory;
    backend = FakeVirtualizationBackend();
    preferences = FakePreferencesRepository();
  });

  tearDown(() {
    Directory.current = original;
    directory.deleteSync(recursive: true);
  });

  /// Advance frames without pumpAndSettle: the indeterminate progress
  /// indicator animates forever, so the tree never fully "settles".
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> open(WidgetTester tester, {Map<String, String>? conf}) async {
    // The fake must be created inside the FakeAsync test zone (not in
    // setUp) so its future completions flush with tester.pump().
    process = FakeProcess();
    backend.downloadProcess = process;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          preferencesRepositoryProvider.overrideWithValue(preferences),
        ],
        child: testApp(
          home: Downloader(
            operatingSystem: ubuntu,
            version: version,
            option: option,
            customConf: conf,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  testWidgets('reports curl progress and success, then records history', (
    tester,
  ) async {
    await open(tester);
    expect(backend.downloadCalls, [
      ['ubuntu', '24.04', ''],
    ]);
    expect(find.textContaining('no progress available'), findsOneWidget);

    process.emitErr(' 42.5% more\n');
    await flush(tester);
    expect(find.textContaining('Downloading... 42%'), findsOneWidget);

    Directory('${directory.path}/ubuntu-24.04').createSync();
    process.finish(0);
    // History/pref writes chain real file I/O with FakeAsync microtasks;
    // interleave frame pumps and real event-loop time to drain them.
    for (var i = 0; i < 6; i++) {
      await flush(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await flush(tester);

    expect(find.text('Download finished.'), findsOneWidget);
    expect(find.text('Manage existing machines'), findsOneWidget);
    expect(preferences.store[prefNewlyInstalledVms], contains('ubuntu-24.04'));
    expect(preferences.store[prefDownloadHistory], isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applies customConf to the newest .conf on success', (
    tester,
  ) async {
    File('${directory.path}/vm.conf')
        .writeAsStringSync('guest_os="linux"\nram="4G"\n');
    await open(tester, conf: {'ram': '8G', 'cpu_cores': '4'});
    process.finish(0);
    await flush(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await flush(tester);

    final written = File('${directory.path}/vm.conf').readAsStringSync();
    expect(written, contains('ram="8G"'));
    expect(written, contains('cpu_cores="4"'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-zero exit reports failure and keeps output visible', (
    tester,
  ) async {
    await open(tester);
    process.emitErr('curl: (22) The requested URL returned error: 404');
    process.finish(22);
    await flush(tester);

    expect(find.text('Download failed'), findsWidgets);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Manage existing machines'), findsNothing);

    await tester.tap(find.text('Show terminal output'));
    await flush(tester);
    expect(find.textContaining('error: 404'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel kills the process and reports cancellation', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await flush(tester);

    expect(process.killed, isTrue);
    expect(find.textContaining('cancel'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backend start failure lands in the failed state', (
    tester,
  ) async {
    backend.downloadError = StateError('quickget missing');
    await open(tester);
    await flush(tester);

    expect(find.text('Download failed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
