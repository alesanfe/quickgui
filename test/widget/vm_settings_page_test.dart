import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';
import 'package:quickgui/features/machines/presentation/details/vm_settings_page.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/harness/test_app.dart';

class _Store implements VmConfigStore {
  final loads = <Completer<String>>[];
  final saves = <String>[];
  bool failSave = false;

  @override
  Future<String> loadRaw(String confPath) {
    final pending = Completer<String>();
    loads.add(pending);
    return pending.future;
  }

  @override
  String? read(String confPath, String key) => null;

  @override
  void write(String confPath, String key, String value) =>
      throw UnimplementedError();

  @override
  void writeAll(String confPath, Map<String, String> entries) =>
      throw UnimplementedError();

  @override
  Future<void> saveRaw(String confPath, String content) async {
    if (failSave) throw StateError('read only');
    saves.add(content);
  }
}

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  Future<void> open(WidgetTester tester, _Store store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vmConfigStoreProvider.overrideWithValue(store),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          // The page probes the host for installed display viewers;
          // without a fake it would spawn real `which` processes with
          // timeout timers that outlive the test.
          hostProbeProvider.overrideWithValue(FakeHostProbe()),
        ],
        child: testApp(home: const VmSettingsPage(vmName: 'example')),
      ),
    );
    await tester.pump();
  }

  testWidgets('loads configuration through the injected store', (tester) async {
    final store = _Store();
    await open(tester, store);
    expect(store.loads, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    store.loads.single.complete('ram="8G"\ncpu_cores="4"\n');
    await tester.pumpAndSettle();
    // Sections build lazily inside the ListView — jump to Resources
    // so the RAM field exists, then check the structured size field
    // (value 8 split from unit G).
    await tester.tap(find.text('Resources'));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion after disposal does not update the page', (
    tester,
  ) async {
    final store = _Store();
    await open(tester, store);
    expect(store.loads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    store.loads.single.complete('ram="8G"\n');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('external edits are not overwritten when saving', (tester) async {
    final store = _Store();
    await open(tester, store);
    store.loads.single.complete('ram="4G"\n');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resources'));
    await tester.pumpAndSettle();
    // The first field is the Memory SizeField (the search box is a
    // TextField, so address the RAM field by its label).
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Memory'),
        matching: find.byType(EditableText),
      ),
      '8G',
    );
    // Rebuild so the dirty state flips the Save button to enabled.
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    store.loads.last.complete('ram="16G"\n');
    await tester.pumpAndSettle();
    expect(store.saves, isEmpty);
    expect(find.text('Configuration changed outside Quickgui'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure retains edits and offers another save', (
    tester,
  ) async {
    final store = _Store()..failSave = true;
    await open(tester, store);
    store.loads.single.complete('ram="4G"\n');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resources'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Memory'),
        matching: find.byType(EditableText),
      ),
      '8G',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    store.loads.last.complete('ram="4G"\n');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not save configuration:'),
      findsOneWidget,
    );
    expect(find.text('8'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed load offers retry', (tester) async {
    final store = _Store();
    await open(tester, store);
    expect(store.loads, hasLength(1));
    store.loads.single.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load configuration'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(store.loads, hasLength(2));
    store.loads.last.complete('ram="4G"\n');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resources'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
