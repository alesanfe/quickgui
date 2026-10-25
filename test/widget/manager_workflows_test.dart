import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

class ManagerScreen {
  ManagerScreen(this.tester);
  final WidgetTester tester;

  Future<void> chooseAction(String label) async {
    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    // Items live under Configure/Lifecycle/Maintenance submenus; direct
    // items (Snapshots, Delete) are at the top level.
    var item = find.text(label);
    if (item.evaluate().isEmpty) {
      for (final group in ['Configure', 'Lifecycle', 'Maintenance']) {
        final g = find.text(group);
        if (g.evaluate().isEmpty) continue;
        await tester.tap(g.last);
        await tester.pumpAndSettle();
        item = find.text(label);
        if (item.evaluate().isNotEmpty) break;
      }
    }
    await tester.ensureVisible(item.last);
    await tester.tap(item.last);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(String label) async {
    // Tap by text: works for TextButton, FilledButton and dialog items.
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  late Directory directory;
  late Directory original;
  late FakeVirtualizationBackend backend;
  late FakePreferencesRepository preferences;
  late FakeHostProbe host;

  setUp(() {
    original = Directory.current;
    directory = Directory.systemTemp.createTempSync('qg-manager-');
    Directory.current = directory;
    File('${directory.path}${Platform.pathSeparator}linux-test.conf')
        .writeAsStringSync('guest_os="linux"\nram="4G"\n');
    File('${directory.path}/invalid.conf').writeAsStringSync('not a VM');
    backend = FakeVirtualizationBackend()
      ..vms = ['linux-test']
      ..capabilities = {
        'capabilities': {'structuredStatus': true},
      }
      ..states = {
        'linux-test': {'state': 'stopped'},
      };
    preferences = FakePreferencesRepository()
      ..store[prefWorkingDirectory] = directory.path;
    host = FakeHostProbe()..dir = directory.path;
  });
  tearDown(() {
    Directory.current = original;
    directory.deleteSync(recursive: true);
  });

  Future<ManagerScreen> open(WidgetTester tester) async {
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
        ],
        child: testApp(home: const Manager()),
      ),
    );
    await tester.pumpAndSettle();
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    expect(find.text('invalid'), findsNothing);
    return ManagerScreen(tester);
  }

  for (final action in ['Info', 'Create', 'Apply', 'Delete']) {
    testWidgets('snapshot $action sends only the selected action', (
      tester,
    ) async {
      final screen = await open(tester);
      await screen.chooseAction('Snapshots');
      await tester.enterText(find.byType(TextField).last, 'checkpoint');
      await tester.pump();
      await screen.confirm(action);
      if (action == 'Apply' || action == 'Delete') {
        // Destructive snapshot actions require a second confirmation.
        await screen.confirm(action);
      }
      expect(backend.actionCalls, [
        [
          '--vm',
          '${directory.path}${Platform.pathSeparator}linux-test.conf',
          '--snapshot',
          action.toLowerCase(),
          if (action != 'Info') 'checkpoint',
        ],
      ]);
    });
  }

  testWidgets('snapshot dialog lists existing snapshots and fills the tag', (
    tester,
  ) async {
    backend.snapshots = [
      {
        'id': '1',
        'name': 'before-upgrade',
        'date': 1700000000,
        'vm-state-size': 0,
      },
    ];
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    expect(find.text('Existing snapshots'), findsOneWidget);
    expect(find.text('before-upgrade'), findsOneWidget);
    await tester.tap(find.text('before-upgrade'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'before-upgrade'), findsOneWidget);
  });

  testWidgets('snapshot dialog can be dismissed with Cancel', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.enterText(find.byType(TextField).last, 'checkpoint');
    await screen.confirm('Cancel');
    expect(backend.actionCalls, isEmpty);
  });

  for (final action in ['Apply', 'Delete']) {
    testWidgets('snapshot $action cancelled at confirmation runs nothing', (
      tester,
    ) async {
      final screen = await open(tester);
      await screen.chooseAction('Snapshots');
      await tester.enterText(find.byType(TextField).last, 'checkpoint');
      await tester.pump();
      await screen.confirm(action);
      await screen.confirm('Cancel');
      expect(backend.actionCalls, isEmpty);
    });
  }

  testWidgets('snapshot actions stay disabled until a tag is entered', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    for (final label in ['Create', 'Apply', 'Delete']) {
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, label).last)
            .onPressed,
        isNull,
      );
    }
    await screen.confirm('Info');
    expect(backend.actionCalls, [
      [
        '--vm',
        '${directory.path}${Platform.pathSeparator}linux-test.conf',
        '--snapshot',
        'info',
      ],
    ]);
  });

  testWidgets('snapshot tag with spaces is forwarded as one argument', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.enterText(find.byType(TextField).last, 'my snapshot');
    await tester.pump();
    await screen.confirm('Create');
    expect(backend.actionCalls, [
      [
        '--vm',
        '${directory.path}${Platform.pathSeparator}linux-test.conf',
        '--snapshot',
        'create',
        'my snapshot',
      ],
    ]);
  });

  for (final (label, title, confirm, flag, value) in [
    ('Clone', 'Clone linux-test', 'Clone', '--clone', 'linux-copy'),
    (
      'Resize disk',
      'Resize disk of linux-test',
      'Resize',
      '--disk-resize',
      '128G',
    ),
  ]) {
    testWidgets('$label validates input and forwards the confirmed value', (
      tester,
    ) async {
      final screen = await open(tester);
      await screen.chooseAction(label);
      expect(find.text(title), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '../invalid');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, confirm).last)
            .onPressed,
        isNull,
      );
      expect(backend.actionCalls, isEmpty);
      await tester.enterText(find.byType(TextField).last, value);
      await tester.pump();
      await screen.confirm(confirm);
      expect(backend.actionCalls, [
        [
          '--vm',
          '${directory.path}${Platform.pathSeparator}linux-test.conf',
          flag,
          value,
        ],
      ]);
    });
    testWidgets('$label cancellation leaves the backend untouched', (
      tester,
    ) async {
      final screen = await open(tester);
      await screen.chooseAction(label);
      await screen.confirm('Cancel');
      expect(backend.actionCalls, isEmpty);
    });
  }

  testWidgets('filter is case insensitive and does not run commands', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'LINUX');
    await tester.pump();
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    // The row is filtered out; the details pane keeps the selection,
    // like VirtualBox does when the list is filtered.
    expect(find.widgetWithText(ListTile, 'linux-test'), findsNothing);
    expect(backend.actionCalls, isEmpty);
  });

  testWidgets('missing acceleration displays an explicit warning', (
    tester,
  ) async {
    host.kvm = false;
    await open(tester);
    expect(find.textContaining('Hardware virtualisation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (label, flag) in [
    ('Resume', '--resume'),
    ('Check VM', '--doctor'),
  ]) {
    testWidgets('$label sends one command for the selected VM', (tester) async {
      final screen = await open(tester);
      await screen.chooseAction(label);
      expect(backend.actionCalls, [
        [
          '--vm',
          '${directory.path}${Platform.pathSeparator}linux-test.conf',
          flag,
        ],
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (label, flag) in [
    ('Cancel', null),
    ('Delete disk image', '--delete-disk'),
    ('Delete whole VM', '--delete-vm'),
  ]) {
    testWidgets('delete confirmation $label respects its scope', (
      tester,
    ) async {
      final screen = await open(tester);
      await screen.chooseAction('Delete');
      // Structured delete-plan first, then the legacy fallback when the
      // fake backend reports no envelope.
      expect(backend.actionCalls, [
        ['--vm', 'linux-test.conf', '--delete-plan'],
        ['--vm', 'linux-test.conf', '--delete-plan', '--format', 'json'],
      ]);
      expect(File('linux-test.conf').existsSync(), isTrue);
      await screen.confirm(label);
      expect(backend.actionCalls, [
        ['--vm', 'linux-test.conf', '--delete-plan'],
        ['--vm', 'linux-test.conf', '--delete-plan', '--format', 'json'],
        if (flag != null) ['--vm', 'linux-test.conf', flag],
      ]);
      expect(File('linux-test.conf').existsSync(), isTrue);
    });
  }

  testWidgets(
    'start passes display from configuration instead of host toggle',
    (tester) async {
      File('linux-test.conf')
          .writeAsStringSync('guest_os="linux"\ndisplay="sdl"\n');
      await open(tester);
      await tester.tap(find.byIcon(Icons.play_arrow_outlined));
      await tester.pumpAndSettle();
      expect(backend.actionCalls, [
        ['--vm', 'linux-test.conf', '--display', 'sdl'],
      ]);
      // Row start icon + details pane Start button.
      expect(find.byIcon(Icons.play_arrow), findsWidgets);
    },
  );

  testWidgets('running VM reset asks confirmation then sends system_reset', (
    tester,
  ) async {
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    final screen = await open(tester);
    await screen.chooseAction('Reset');
    expect(find.text('Reset linux-test?'), findsOneWidget);
    await screen.confirm('Reset');
    expect(backend.actionCalls, [
      [
        '--vm',
        '${directory.path}${Platform.pathSeparator}linux-test.conf',
        '--monitor-cmd',
        'system_reset',
      ],
    ]);
  });

  testWidgets('running VM reset cancelled sends nothing', (tester) async {
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    final screen = await open(tester);
    await screen.chooseAction('Reset');
    await screen.confirm('Cancel');
    expect(backend.actionCalls, isEmpty);
  });

  testWidgets('paused VM shows a Paused badge', (tester) async {
    backend.states = {
      'linux-test': {'state': 'paused'},
    };
    await open(tester);
    // Row subtitle badge + details pane state chip.
    expect(find.text('Paused'), findsWidgets);
  });

  testWidgets('stopped VM does not offer reset', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('running VM stop can be cancelled without sending a command', (
    tester,
  ) async {
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    final screen = await open(tester);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    await screen.confirm('Cancel');
    expect(backend.actionCalls, isEmpty);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('action with output opens the quickemu output dialog', (
    tester,
  ) async {
    backend.lastActionResult = ProcessResult(0, 0, 'doctor says hi', '');
    final screen = await open(tester);
    await screen.chooseAction('Check VM');
    await tester.pump();
    expect(find.text('doctor says hi'), findsOneWidget);
    await tester.tap(find.text('Dismiss').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('running VM exposes SPICE connect with its port', (tester) async {
    host
      ..terminal = 'xterm'
      ..tools.add('spicy');
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    Directory('linux-test').createSync();
    // No ssh entry: an ssh port would trigger a real Socket.connect probe.
    File('linux-test/linux-test.ports').writeAsStringSync('spice,5930\n');
    await open(tester);
    expect(find.textContaining('SPICE port: 5930'), findsOneWidget);
    await tester.tap(find.byTooltip('Connect display with SPICE'));
    await tester.pump();
    expect(find.byTooltip('SSH server not detected on guest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app lifecycle pause and resume keeps the list stable', (
    tester,
  ) async {
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 100));
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pid-file fallback marks the VM running without capabilities', (
    tester,
  ) async {
    backend.capabilities = null;
    Directory('linux-test').createSync();
    File('linux-test/linux-test.pid').writeAsStringSync('$pid');
    host.alivePids = {pid};
    await open(tester);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Open VM folder delegates to the backend', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Open VM folder');
    await tester.pump();
    expect(backend.folderCalls, ['linux-test']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Export runs the backend export for the VM', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Export');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(backend.exportCalls, ['linux-test']);
    expect(tester.takeException(), isNull);
  });
}
