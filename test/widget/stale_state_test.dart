import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

/// Same driver as manager_workflows_test — duplicated locally so this
/// file stays self-contained.
Future<void> chooseAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More actions').first);
  await tester.pumpAndSettle();
  var item = find.widgetWithText(MenuItemButton, label);
  for (final sub in find.byType(SubmenuButton).evaluate().toList()) {
    if (item.evaluate().isNotEmpty) break;
    await tester.tap(find.byWidget(sub.widget));
    await tester.pumpAndSettle();
    item = find.widgetWithText(MenuItemButton, label);
  }
  // Invoke the button's own callback — a geometric tap near the menu's
  // clip edge can hit the barrier instead and silently dismiss the
  // menu, making the test flaky rather than the widget wrong.
  tester.widget<MenuItemButton>(item.first).onPressed!();
  // Pump a bounded window: enough for the revalidation's async chain,
  // but well under the SnackBar's ~4 s auto-dismiss — pumpAndSettle
  // would run out the timer on the fake clock and remove the very
  // widget under test.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Conf dialogs read the file with real async IO (readAsString/
/// readAsLines) — pumpAndSettle never drains the event loop, so give
/// the read a real window then settle the dialog in. Same pattern as
/// the capture harness: bounded runAsync rounds until [until] (or any
/// Dialog) mounts.
Future<void> settleIo(WidgetTester tester, [Finder? until]) async {
  bool settled() => until != null
      ? until.evaluate().isNotEmpty
      : find.byType(Dialog).evaluate().isNotEmpty;
  for (var i = 0; i < 12 && !settled(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late Directory directory;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeHostProbe host;
  late File conf;

  setUp(() {
    original = Directory.current;
    directory = Directory.systemTemp.createTempSync('qg-stale-');
    Directory.current = directory;
    conf = File('${directory.path}/linux-test.conf')
      ..writeAsStringSync('guest_os="linux"\nram="4G"\n');
    backend = FakeVirtualizationBackend()
      ..vms = ['linux-test']
      ..capabilities = {
        'capabilities': {'structuredStatus': true},
      }
      ..states = {
        'linux-test': {'state': 'stopped'},
      };
    preferences = FakePreferencesRepository()
      ..store[prefWorkingDirectory] = directory.path
      // Silence the first-run hint SnackBar — it queues ahead of the
      // notices under test and would mask them.
      ..store[prefFirstRunHintShown] = true;
    host = FakeHostProbe()..dir = directory.path;
  });
  tearDown(() {
    Directory.current = original;
    directory.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(host),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          osIconsProvider.overrideWithValue({}),
        ],
        child: testApp(home: const Manager()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('linux-test'), findsWidgets);
  }

  // QGUI-X-004: a cached "stopped" menu must not send a start when the
  // VM began running between the last refresh and the tap.
  testWidgets('state-dependent action is blocked when the VM changed state', (
    tester,
  ) async {
    await open(tester);
    // External change: the backend now reports the VM running.
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    await chooseAction(tester, 'Verify image');
    expect(backend.actionCalls, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('the action no longer applies'), findsOneWidget);
  });

  testWidgets('action on a VM deleted behind the UI is blocked', (
    tester,
  ) async {
    await open(tester);
    conf.deleteSync();
    backend.states = {};
    await chooseAction(tester, 'Verify image');
    expect(backend.actionCalls, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('no longer exists'), findsOneWidget);
  });

  // QGUI-X-004: the structured .conf editors share the same external-
  // change contract as the raw editor — saving over an externally
  // modified file must surface the merge dialog instead of silently
  // overwriting.
  testWidgets('saving over an externally edited conf shows the conflict', (
    tester,
  ) async {
    await open(tester);
    await chooseAction(tester, 'Shared folder');
    await settleIo(tester);
    expect(find.text('Save'), findsOneWidget);
    // External editor appends a key while the dialog is open.
    conf.writeAsStringSync('guest_os="linux"\nram="4G"\nexternal_edit="yes"\n');
    await tester.tap(find.text('Save'));
    // The outgoing dialog pops while the disk re-read runs — wait for
    // the conflict dialog itself, not "any Dialog".
    await settleIo(tester, find.text('Configuration changed outside Quickgui'));
    expect(find.text('Configuration changed outside Quickgui'), findsOneWidget);
    // Overwrite keeps the user's edit and drops the external key.
    await tester.tap(find.text('Overwrite anyway'));
    await tester.pumpAndSettle();
    final written = conf.readAsStringSync();
    expect(written, contains('public_dir='));
    expect(written, isNot(contains('external_edit')));
  });

  testWidgets('conflict reload keeps the external version', (tester) async {
    await open(tester);
    await chooseAction(tester, 'Shared folder');
    await settleIo(tester);
    conf.writeAsStringSync('guest_os="linux"\nram="4G"\nexternal_edit="yes"\n');
    await tester.tap(find.text('Save'));
    await settleIo(tester, find.text('Configuration changed outside Quickgui'));
    await tester.tap(find.text('Reload from disk'));
    await tester.pumpAndSettle();
    expect(conf.readAsStringSync(), contains('external_edit="yes"'));
  });

  // QGUI-X-003: VM actions run through the activity coordinator — a
  // second op on the same machine is refused instead of interleaving
  // quickemu invocations, and the refused action never reaches the
  // backend.
  testWidgets('action is refused while another op occupies the VM', (
    tester,
  ) async {
    await open(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Manager)),
    );
    container
        .read(activityProvider.notifier)
        .start(OperationKind.download, 'linux-test');
    backend.jsonCalls.clear();
    backend.actionCalls.clear();
    await chooseAction(tester, 'Start');
    expect(backend.jsonCalls, isEmpty);
    expect(backend.actionCalls, isEmpty);
    expect(
      find.textContaining('already running for linux-test'),
      findsOneWidget,
    );
  });

  testWidgets('successful action registers a completed operation', (
    tester,
  ) async {
    await open(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Manager)),
    );
    await chooseAction(tester, 'Start');
    await tester.pumpAndSettle();
    expect(
      backend.actionCalls.any((args) => args.contains('linux-test.conf')),
      isTrue,
    );
    final history = container.read(activityProvider).history;
    expect(
      history.any((e) => e.target == 'linux-test'),
      isTrue,
      reason: 'the tracked op should land in activity history',
    );
  });
}
