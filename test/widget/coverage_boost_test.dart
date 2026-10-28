import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/presentation/operation_tile.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/create/application/import_image.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/presentation/details/vm_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late Directory dir;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakeHostProbe host;
  late FakePreferencesRepository prefs;

  setUp(() {
    original = Directory.current;
    dir = Directory.systemTemp.createTempSync('qg-cov-');
    Directory.current = dir;
    backend = FakeVirtualizationBackend()
      ..vms = ['vm1']
      ..states = {
        'vm1': {'name': 'vm1', 'state': 'stopped', 'pid': null},
      };
    host = FakeHostProbe()..dir = dir.path;
    prefs = FakePreferencesRepository()..store[prefWorkingDirectory] = dir.path;
    File(
      '${dir.path}/vm1.conf',
    ).writeAsStringSync('guest_os="linux"\ndisk_img="disk.qcow2"\nram="2G"\n');
  });

  tearDown(() {
    Directory.current = original;
    dir.deleteSync(recursive: true);
  });

  Widget app(Widget home) => ProviderScope(
    overrides: [
      backendProvider.overrideWithValue(backend),
      trackedBackendProvider.overrideWithValue(backend),
      hostProbeProvider.overrideWithValue(host),
      preferencesRepositoryProvider.overrideWithValue(prefs),
      osIconsProvider.overrideWithValue({}),
      osCatalogueProvider.overrideWithValue(Future.value([])),
    ],
    child: testApp(home: home),
  );

  group('importImageFile', () {
    Future<void> launch(
      WidgetTester tester,
      String image, {
      Size size = const Size(1000, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => importImageFile(context, ref, image),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('passthrough image imports via create-config', (tester) async {
      await launch(tester, '${dir.path}/my.iso');
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(backend.quickgetCalls.single.first, '--create-config');
      expect(backend.quickgetCalls.single[1], 'my');
    });

    testWidgets('convertible image converts to qcow2 first', (tester) async {
      await launch(tester, '${dir.path}/disk.vdi');
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(backend.convertCalls.single.first, endsWith('disk.vdi'));
      expect(backend.convertCalls.single.last, endsWith('disk.qcow2'));
      expect(backend.quickgetCalls.single, isNotEmpty);
    });

    testWidgets('failed conversion reports and skips import', (tester) async {
      backend.lastActionResult = const ProcResult(1, '', 'qemu-img failed');
      await launch(tester, '${dir.path}/bad.vmdk');
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('qemu-img failed'), findsWidgets);
      expect(backend.quickgetCalls, isEmpty);
    });

    testWidgets('failed import reports the error', (tester) async {
      backend.lastActionResult = const ProcResult(2, '', 'no such iso');
      await launch(tester, '${dir.path}/gone.iso');
      await tester.tap(find.text('Import').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('no such iso'), findsWidgets);
    });
  });

  group('Manager dialogs', () {
    Future<void> openManager(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const Manager()));
      await tester.pumpAndSettle();
    }

    Future<void> chooseAction(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('More actions').first);
      await tester.pumpAndSettle();
      // The menu is height-capped (~560) — items below the fold are not
      // built until scrolled into view.
      var item = find.text(label);
      for (var i = 0; i < 6 && item.evaluate().isEmpty; i++) {
        final scrollable = find.byType(Scrollable).last;
        await tester.drag(scrollable, const Offset(0, -350));
        await tester.pumpAndSettle();
        item = find.text(label);
      }
      await tester.ensureVisible(item.last);
      await tester.tap(item.last);
      await tester.pumpAndSettle();
    }

    testWidgets('trash dialog lists items and restores', (tester) async {
      backend.trashItems = [
        {'name': 'oldvm', 'deletedAt': '2026-01-01'},
      ];
      await openManager(tester);
      await tester.tap(find.byTooltip('Trash'));
      await tester.pumpAndSettle();
      expect(find.text('oldvm'), findsWidgets);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(backend.trashItems, isEmpty);
    });

    testWidgets('trash dialog shows empty state', (tester) async {
      await openManager(tester);
      await tester.tap(find.byTooltip('Trash'));
      await tester.pumpAndSettle();
      expect(find.textContaining('trash is empty'), findsWidgets);
    });

    testWidgets('backups dialog lists and creates', (tester) async {
      backend.backupItems = [
        {'file': 'vm1-1.tar.gz', 'size': '1.2G'},
      ];
      await openManager(tester);
      await chooseAction(tester, 'Backups');
      expect(find.text('vm1-1.tar.gz'), findsWidgets);
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();
      expect(backend.backupItems.length, greaterThan(1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('hotplug dialog attaches a usb device', (tester) async {
      await openManager(tester);
      await chooseAction(tester, 'Hotplug devices');
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        '046d:c077',
      );
      await tester.pump();
      await tester.tap(find.text('Attach USB'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('move/rename dialog sends a rename', (tester) async {
      await openManager(tester);
      await chooseAction(tester, 'Move / Rename');
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .last,
        'vm1-renamed',
      );
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('VmPage', () {
    Future<void> openVmPage(
      WidgetTester tester, {
      String state = 'stopped',
    }) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      backend.states = {
        'vm1': {
          'name': 'vm1',
          'state': state,
          'pid': state == 'stopped' ? null : 4242,
        },
      };
      await tester.pumpWidget(app(const VmPage(vmName: 'vm1')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('renders actions and overview from the conf', (tester) async {
      await openVmPage(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('guest_os'), findsWidgets);
      expect(find.text('linux'), findsWidgets);
      expect(find.text('Start'), findsWidgets);
    });

    testWidgets('Start on a stopped VM runs the backend action', (
      tester,
    ) async {
      await openVmPage(tester);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(backend.actionCalls.single, ['--vm', 'vm1.conf']);
    });

    testWidgets('Pause on a running VM sends --pause', (tester) async {
      await openVmPage(tester, state: 'running');
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();
      expect(backend.actionCalls.single, ['--vm', 'vm1.conf', '--pause']);
    });

    testWidgets('Resume on a paused VM sends --resume', (tester) async {
      await openVmPage(tester, state: 'paused');
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(backend.actionCalls.single, ['--vm', 'vm1.conf', '--resume']);
    });

    testWidgets('advanced menu trash runs after confirmation', (tester) async {
      await openVmPage(tester);
      await tester.tap(find.byTooltip('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to trash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(backend.actionCalls.single, ['--vm', 'vm1.conf', '--trash']);
    });

    testWidgets('advanced menu kill cancelled runs nothing', (tester) async {
      await openVmPage(tester, state: 'running');
      await tester.tap(find.byTooltip('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.actionCalls, isEmpty);
    });

    testWidgets('operations and logs tabs render', (tester) async {
      await openVmPage(tester);
      await tester.tap(find.text('Operations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('VmConnectionView', () {
    Future<void> openConn(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: VmConnectionView(vm: 'vm1', confPath: 'vm1.conf'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('connect without ports file explains the missing port', (
      tester,
    ) async {
      await openConn(tester);
      await tester.tap(find.text('Connect / reconnect'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('not published a connection port'),
        findsOneWidget,
      );
    });

    testWidgets('connect without an installed viewer explains the fix', (
      tester,
    ) async {
      Directory('${dir.path}/vm1').createSync();
      File('${dir.path}/vm1/vm1.ports').writeAsStringSync('spice,59999\n');
      await openConn(tester);
      await tester.tap(find.text('Connect / reconnect'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SPICE viewer is unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('connect with closed spice port reports it', (tester) async {
      host.tools.add('spicy');
      Directory('${dir.path}/vm1').createSync();
      File('${dir.path}/vm1/vm1.ports').writeAsStringSync('spice,59999\n');
      await openConn(tester);
      await tester.tap(find.text('Connect / reconnect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('SPICE port is closed'), findsOneWidget);
    });

    testWidgets('ssh connect opens the user dialog', (tester) async {
      Directory('${dir.path}/vm1').createSync();
      File('${dir.path}/vm1/vm1.ports').writeAsStringSync('ssh,2222\n');
      host
        ..terminal = 'xterm'
        ..sshPorts = {2222};
      await openConn(tester);
      await tester.tap(find.text('Connect with SSH'));
      // _checking drives a LinearProgressIndicator — pump, don't settle.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(TextField), findsWidgets);
      expect(find.textContaining('2222'), findsWidgets);
    });
  });

  group('HistoryEntryTile', () {
    testWidgets('tap opens the report dialog', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: HistoryEntryTile(
              entry: OperationHistoryEntry(
                id: 'x',
                kind: OperationKind.export,
                target: 'vm1',
                startedAt: DateTime(2026),
                completedAt: DateTime(2026, 1, 1, 1),
                status: OperationStatus.failed,
                message: 'checksum mismatch',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('checksum mismatch'), findsWidgets);
      await tester.tap(find.text('Copy report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });
}
