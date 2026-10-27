import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/downloads/providers/download_tasks_provider.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../../../support/fakes/fake_preferences_repository.dart';
import '../../../support/fakes/fake_process.dart';
import '../../../support/fakes/fake_virtualization_backend.dart';

void main() {
  late Directory directory;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeProcess process;
  late ProviderContainer container;

  setUp(() {
    original = Directory.current;
    directory = Directory.systemTemp.createTempSync('qg-download-tasks-');
    Directory.current = directory;
    backend = FakeVirtualizationBackend()..downloadProcess = FakeProcess();
    process = backend.downloadProcess!;
    preferences = FakePreferencesRepository();
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        preferencesRepositoryProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    Directory.current = original;
    directory.deleteSync(recursive: true);
  });

  /// The task body is fire-and-forget inside the provider; real event
  /// loop delays let its awaits complete (plain test zone, not FakeAsync).
  Future<void> drain([int times = 4]) async {
    for (var i = 0; i < times; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  test('streams curl progress, succeeds and records history', () async {
    final op = container
        .read(downloadTasksProvider)
        .start(os: 'ubuntu', release: '24.04');
    await drain();
    expect(backend.downloadCalls, [
      ['ubuntu', '24.04', ''],
    ]);
    // The op stays queued until the first output chunk marks it running.
    expect(op.state, isA<OperationQueued<Object?>>());

    process.emitErr(' 42.5% more\n');
    await drain(1);
    final running = op.state as OperationRunning<Object?>;
    expect(running.progress, closeTo(0.425, 0.001));

    File('${directory.path}/ubuntu-24.04.conf')
        .writeAsStringSync('guest_os="linux"\n');
    process.finish(0);
    await drain();

    expect(op.state, isA<OperationSucceeded<Object?>>());
    expect(preferences.store[prefNewlyInstalledVms], contains('ubuntu-24.04'));
    expect(preferences.store[prefDownloadHistory], isNotEmpty);
  });

  test('applies customConf to the generated .conf on success', () async {
    File('${directory.path}/ubuntu-24.04.conf')
        .writeAsStringSync('guest_os="linux"\nram="4G"\n');
    container
        .read(downloadTasksProvider)
        .start(
          os: 'ubuntu',
          release: '24.04',
          configuration: {'ram': '8G', 'cpu_cores': '4'},
        );
    await drain();
    process.finish(0);
    await drain();

    final written = File('${directory.path}/ubuntu-24.04.conf')
        .readAsStringSync();
    expect(written, contains('ram="8G"'));
    expect(written, contains('cpu_cores="4"'));
  });

  test('a non-zero exit fails the op and keeps output', () async {
    final op = container
        .read(downloadTasksProvider)
        .start(os: 'ubuntu', release: '24.04');
    await drain();
    process.emitErr('curl: (22) The requested URL returned error: 404');
    process.finish(22);
    await drain();

    final failed = op.state as OperationFailed<Object?>;
    expect(failed.code, 'download.exit_22');
    expect(op.output, contains('error: 404'));
  });

  test('cancel kills the process and lands in cancelled', () async {
    final op = container
        .read(downloadTasksProvider)
        .start(os: 'ubuntu', release: '24.04');
    await drain();
    await container.read(activityProvider.notifier).cancel(op);
    await drain();

    expect(process.killed, isTrue);
    expect(op.state, isA<OperationCancelled<Object?>>());
  });

  test('a backend start failure lands in the failed state', () async {
    backend.downloadError = StateError('quickget missing');
    final op = container
        .read(downloadTasksProvider)
        .start(os: 'ubuntu', release: '24.04');
    await drain();

    final failed = op.state as OperationFailed<Object?>;
    expect(failed.code, 'download.failed');
    expect(failed.message, contains('quickget missing'));
  });
}
