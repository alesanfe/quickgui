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

import 'package:quickgui/features/machines/application/ports/proc.dart';

class ManagerScreen {
  ManagerScreen(this.tester);
  final WidgetTester tester;

  Future<void> chooseAction(String label) async {
    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    // The overflow menu is a MenuAnchor whose entries are MenuItemButtons.
    // Match the button *containing* the label: a plain find.text also hits
    // same-named controls in the details pane and row quick actions, which
    // sit under the open menu and swallow the tap on its barrier.
    var item = find.widgetWithText(MenuItemButton, label);
    // Rarely-used actions live in cascading SubmenuButtons — their
    // children only enter the tree once the submenu is open, so open
    // each submenu in turn until the item appears.
    for (final sub in find.byType(SubmenuButton).evaluate().toList()) {
      if (item.evaluate().isNotEmpty) break;
      await tester.tap(find.byWidget(sub.widget));
      await tester.pumpAndSettle();
      item = find.widgetWithText(MenuItemButton, label);
    }
    await tester.ensureVisible(item.first);
    await tester.pumpAndSettle();
    await tester.tap(item.first.hitTestable());
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
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    expect(find.text('invalid'), findsNothing);
    return ManagerScreen(tester);
  }

  // Snapshot actions are split by scope (QGUI-SNAP-001): creating a
  // snapshot is a global action driven by the tag field, while apply/
  // delete act on the selected row of the existing-snapshots list.
  testWidgets('snapshot Create sends the typed tag', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.enterText(
      find.widgetWithText(TextField, 'Snapshot tag'),
      'checkpoint',
    );
    await tester.pump();
    await screen.confirm('Create snapshot');
    expect(backend.actionCalls, [
      [
        '--vm',
        '${directory.path}${Platform.pathSeparator}linux-test.conf',
        '--snapshot',
        'create',
        'checkpoint',
      ],
    ]);
  });

  testWidgets('snapshot Info runs from the More actions menu', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.tap(find.byTooltip('More snapshot actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snapshot backend info'));
    await tester.pumpAndSettle();
    expect(backend.actionCalls, [
      [
        '--vm',
        '${directory.path}${Platform.pathSeparator}linux-test.conf',
        '--snapshot',
        'info',
      ],
    ]);
  });

  for (final (label, flag) in [('Apply', 'apply'), ('Delete', 'delete')]) {
    Future<void> tapRowAction(WidgetTester tester) async {
      // Apply is a text button on the row; Delete is an icon button —
      // the row keeps destructive affordances icon-only + tooltip.
      if (flag == 'delete') {
        await tester.tap(find.byTooltip('Delete snapshot'));
      } else {
        await tester.tap(find.text(label));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('snapshot $label on a row confirms then sends $flag', (
      tester,
    ) async {
      backend.snapshots = [
        {'id': '1', 'name': 'before-upgrade', 'date': 1700000000},
      ];
      final screen = await open(tester);
      await screen.chooseAction('Snapshots');
      await tapRowAction(tester);
      // Destructive actions require a second confirmation.
      await screen.confirm(label);
      expect(backend.actionCalls, [
        [
          '--vm',
          '${directory.path}${Platform.pathSeparator}linux-test.conf',
          '--snapshot',
          flag,
          'before-upgrade',
        ],
      ]);
    });

    testWidgets('snapshot $label cancelled at confirmation runs nothing', (
      tester,
    ) async {
      backend.snapshots = [
        {'id': '1', 'name': 'before-upgrade', 'date': 1700000000},
      ];
      final screen = await open(tester);
      await screen.chooseAction('Snapshots');
      await tapRowAction(tester);
      await screen.confirm('Cancel');
      expect(backend.actionCalls, isEmpty);
    });
  }

  testWidgets('snapshot dialog lists existing snapshots with per-row actions', (
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
    expect(find.text('Apply'), findsOneWidget);
    expect(find.byTooltip('Delete snapshot'), findsOneWidget);
  });

  testWidgets('snapshot dialog can be dismissed with Close', (tester) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.enterText(
      find.widgetWithText(TextField, 'Snapshot tag'),
      'checkpoint',
    );
    await screen.confirm('Close');
    expect(backend.actionCalls, isEmpty);
  });

  testWidgets('snapshot Create stays disabled until a tag is entered', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create snapshot'),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Snapshot tag'),
      'checkpoint',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create snapshot'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('snapshot tag with spaces is forwarded as one argument', (
    tester,
  ) async {
    final screen = await open(tester);
    await screen.chooseAction('Snapshots');
    await tester.enterText(
      find.widgetWithText(TextField, 'Snapshot tag'),
      'my snapshot',
    );
    await tester.pump();
    await screen.confirm('Create snapshot');
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
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, confirm).last,
            )
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
    // The search field is debounced (250 ms) — let the timer fire.
    await tester.pump(const Duration(milliseconds: 300));
    // The name appears both in the row and in the details pane header.
    expect(find.text('linux-test'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump(const Duration(milliseconds: 300));
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

  for (final (label, flag, state) in [
    ('Resume', '--resume', 'paused'),
    ('Check VM', '--doctor', 'stopped'),
  ]) {
    testWidgets('$label sends one command for the selected VM', (tester) async {
      backend.states = {
        'linux-test': {'state': state},
      };
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
      expect(backend.actionCalls, [
        ['--vm', 'linux-test.conf', '--delete-plan', '--format', 'json'],
      ]);
      expect(File('linux-test.conf').existsSync(), isTrue);
      await screen.confirm(label);
      expect(backend.actionCalls, [
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
    backend.lastActionResult = const ProcResult(0, 'doctor says hi', '');
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
    // The disabled SSH affordance appears on the row and in the
    // details pane — both carry the same reason tooltip.
    expect(find.byTooltip('SSH server not detected on guest'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // .ports is external file content — a comma-less or empty-value line
  // must not crash the parser (parts[1] RangeError) nor register a
  // bogus port; valid entries keep working.
  testWidgets('malformed ports file lines are skipped without crashing', (
    tester,
  ) async {
    backend.states = {
      'linux-test': {'state': 'running'},
    };
    Directory('linux-test').createSync();
    File('linux-test/linux-test.ports')
        .writeAsStringSync('ssh\nspice,5930\nssh,\n');
    await open(tester);
    expect(find.textContaining('SPICE port: 5930'), findsOneWidget);
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
