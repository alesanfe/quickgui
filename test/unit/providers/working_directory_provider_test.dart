import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/shared/providers/working_directory_provider.dart';

import '../../support/fakes/fake_preferences_repository.dart';

void main() {
  late Directory original;
  late Directory sandbox;
  late FakePreferencesRepository prefs;
  late ProviderContainer container;

  setUp(() {
    original = Directory.current;
    sandbox = Directory.systemTemp.createTempSync('qg-wd-');
    prefs = FakePreferencesRepository();
    container = ProviderContainer(
      overrides: [preferencesRepositoryProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() {
    container.dispose();
    Directory.current = original;
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('initial state is the process cwd', () {
    expect(container.read(workingDirectoryProvider), Directory.current.path);
  });

  test('apply updates state and cwd without persisting the pref', () {
    container.read(workingDirectoryProvider.notifier).apply(sandbox.path);
    expect(container.read(workingDirectoryProvider), sandbox.path);
    expect(Directory.current.path, sandbox.path);
    expect(prefs.store.containsKey(prefWorkingDirectory), isFalse);
  });

  test('set persists the pref and applies', () async {
    await container.read(workingDirectoryProvider.notifier).set(sandbox.path);
    expect(container.read(workingDirectoryProvider), sandbox.path);
    expect(Directory.current.path, sandbox.path);
    expect(prefs.store[prefWorkingDirectory], sandbox.path);
  });

  // QGUI-M-005: the cwd can be deleted under the process (tmp purges,
  // external cleanup) — reads must degrade to an empty root instead of
  // throwing PathNotFoundException, and apply() must still be able to
  // repair the process cwd afterwards.
  test('deleted cwd degrades to empty root and apply() repairs it', () {
    final gone = Directory.systemTemp.createTempSync('qg-wd-gone-');
    Directory.current = gone;
    gone.deleteSync();
    final c = ProviderContainer(
      overrides: [preferencesRepositoryProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    expect(c.read(workingDirectoryProvider), '');
    c.read(workingDirectoryProvider.notifier).apply(sandbox.path);
    expect(Directory.current.path, sandbox.path);
  });
}
