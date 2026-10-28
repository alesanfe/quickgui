@TestOn('vm')
@Tags(['capture'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/presentation/version_selection.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/create/presentation/create_page.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/home/presentation/dashboard_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/settings/presentation/settings_page.dart';
import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

import 'package:quickgui/features/machines/application/ports/proc.dart';

/// Real fonts so text and icons render as in the app — every family declared
/// in FontManifest.json (Roboto via alchemist, MaterialIcons, package fonts).
Future<void> _loadAllFonts() async {
  final bundle = rootBundle;
  List<dynamic> manifest;
  try {
    manifest = json.decode(
      await bundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
  } catch (_) {
    manifest = const [];
  }
  for (final e in manifest) {
    final entry = e as Map<String, dynamic>;
    var family = entry['family'] as String;
    if (family.startsWith('packages/alchemist/')) {
      family = family.substring('packages/alchemist/'.length);
    }
    final loader = FontLoader(family);
    for (final f in entry['fonts'] as List<dynamic>) {
      loader.addFont(
        bundle.load((f as Map<String, dynamic>)['asset'] as String),
      );
    }
    try {
      await loader.load();
    } catch (_) {
      // Asset unavailable in the test bundle — fall back below.
    }
  }
  // Explicit fallbacks: Roboto ships with alchemist, MaterialIcons with the
  // framework.
  for (final (family, assets) in [
    (
      'Roboto',
      [
        'Regular',
        'Medium',
        'Bold',
      ].map((w) => 'packages/alchemist/assets/fonts/Roboto/Roboto-$w.ttf'),
    ),
    // The .conf editor uses fontFamily 'monospace'; map it to Roboto so
    // captures show real text instead of missing-glyph boxes.
    (
      'monospace',
      ['Regular']
          .map((w) => 'packages/alchemist/assets/fonts/Roboto/Roboto-$w.ttf'),
    ),
    ('MaterialIcons', ['fonts/MaterialIcons-Regular.otf'].map((p) => p)),
  ]) {
    final loader = FontLoader(family);
    var added = false;
    for (final a in assets) {
      try {
        loader.addFont(bundle.load(a));
        added = true;
      } catch (_) {}
    }
    if (added) {
      try {
        await loader.load();
      } catch (_) {}
    }
  }
}

/// Fixed path so the rendered "machines directory" label is deterministic
/// and the goldens stay stable across runs. Recreated in setUpAll with
/// minimal valid .conf files so the Manager lists VMs (it scans
/// Directory.current pointed to by the workingDirectory pref).
final Directory _vmDir = Directory('/tmp/qg_capture_vms');

/// The Manager writes the workingDirectory pref into the process-global
/// Directory.current — restore it per test so a deleted dir never
/// cascades into later captures.
late final Directory _originalCwd;

/// Recreate the VM sandbox before EVERY test (not setUpAll): a mid-suite
/// failure must not leave a deleted Directory.current for the rest.
void _resetVmDir() {
  Directory.current = _originalCwd;
  if (_vmDir.existsSync()) _vmDir.deleteSync(recursive: true);
  _vmDir.createSync(recursive: true);
  for (final name in ['ubuntu-24.04', 'windows-11', 'debian-12']) {
    File('${_vmDir.path}/$name.conf')
        .writeAsStringSync('guest_os="linux"\ndisk_img="$name/disk.qcow2"\n');
    Directory('${_vmDir.path}/$name').createSync();
  }
}

/// Fake catalogue entry used by both the OS-selection page and the
/// version-selection page.
final OperatingSystem _captureOs = OperatingSystem('Ubuntu', 'ubuntu')
  ..versions = [
    Version('24.04')..options.add(Option('desktop', 'qemu')),
    Version('25.04')..options.add(Option('desktop', 'qemu')),
    Version('25.10')..options.add(Option('desktop', 'qemu')),
  ];

/// Fixed machine library for dashboard captures — mirrors the three VMs
/// written into [_vmDir] by [_resetVmDir].
const _captureMachines = <LibraryMachine>[
  LibraryMachine(
    name: 'debian-12',
    confPath: '/vms/debian-12.conf',
    state: 'stopped',
    values: {'cpu_cores': '2', 'ram': '2G'},
  ),
  LibraryMachine(
    name: 'ubuntu-24.04',
    confPath: '/vms/ubuntu-24.04.conf',
    state: 'running',
    values: {'cpu_cores': '4', 'ram': '4G'},
    pid: 42424,
  ),
  LibraryMachine(
    name: 'windows-11',
    confPath: '/vms/windows-11.conf',
    state: 'stopped',
    values: {'cpu_cores': '8', 'ram': '8G'},
  ),
];

/// Synchronous [VmConfigStore]: `loadRaw`/`saveRaw` resolve on the
/// microtask queue so dialogs never wait on real file IO inside
/// `testWidgets`.
class _SyncVmConfigStore extends VmConfigFileStore {
  const _SyncVmConfigStore();

  @override
  Future<String> loadRaw(String confPath) =>
      Future.value(File(confPath).readAsStringSync());

  @override
  Future<void> saveRaw(String confPath, String content) async =>
      File(confPath).writeAsStringSync(content);
}

Widget _app({
  required Widget home,
  required bool dark,
  bool backendAvailable = true,
  ProcResult? actionResult,
  FakeHostProbe? probe,
  String? runningVm,
}) => ProviderScope(
  overrides: [
    backendProvider.overrideWithValue(
      FakeVirtualizationBackend()
        ..available = backendAvailable
        ..vms = ['ubuntu-24.04', 'windows-11', 'debian-12']
        ..states = {
          ?runningVm: {
            'name': runningVm,
            'state': 'running',
            'pid': runningPid,
          },
        }
        ..capabilities = {
          'schemaVersion': 1,
          'applicationVersion': '4.9.9',
          'capabilities': {'snapshots': true, 'safeDeletePlan': false},
        }
        ..lastActionResult = actionResult,
    ),
    hostProbeProvider.overrideWithValue(probe ?? FakeHostProbe()),
    osCatalogueProvider.overrideWithValue(
      Future.value(<OperatingSystem>[_captureOs]),
    ),
    // Reads/writes the real .conf files on disk, but stays synchronous so
    // captures don't depend on real file IO completing under FakeAsync.
    vmConfigStoreProvider.overrideWithValue(const _SyncVmConfigStore()),
    preferencesRepositoryProvider.overrideWithValue(
      FakePreferencesRepository()
        ..store['workingDirectory'] = _vmDir.path
        ..store['downloadHistory'] = <String>[
          'ubuntu-24.04 desktop — completed',
          'debian-12 netinst — completed',
        ],
    ),
    initialSettingsProvider.overrideWithValue(SettingsState(darkMode: dark)),
    // The dashboard lists machines via a real directory scan — pin a
    // fixed library so captures are host-independent.
    vmLibraryProvider.overrideWith((ref) async => _captureMachines),
  ],
  child: testApp(theme: dark ? AppTheme.dark() : AppTheme.light(), home: home),
);

Future<void> _capture(
  WidgetTester t,
  Widget widget,
  String name, {
  Future<void> Function(WidgetTester t)? interact,
  String? runningVm,
  Size? size,
}) async {
  t.view.physicalSize = size ?? windowSize;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  if (runningVm != null) {
    // The Manager marks a VM active when <vm>/<vm>.pid contains a pid the
    // HostProbe reports alive. A synthetic pid + the injected FakeHostProbe
    // keeps the fixture host-independent (no real `sleep` process needed).
    File('${_vmDir.path}/$runningVm/$runningVm.pid')
        .writeAsStringSync('$runningPid');
    File('${_vmDir.path}/$runningVm/$runningVm.ports')
        .writeAsStringSync('ssh,2222\nspice,5930\n');
  }
  await t.pumpWidget(widget);
  // Fixed pump budget (not pumpAndSettle): the Manager's periodic 5s
  // refresh timer would keep scheduling frames and stall the settle.
  // ~2.5s is enough for the prefs -> _getVms -> setState chain, since
  // the VM directory scan is synchronous (listSync).
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
  if (interact != null) {
    await interact(t);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }
  // Transient snackbars (first-run hint, batch results) live ~4s — past
  // the pump budget — and would poison the pixel comparison. Clear any
  // pending one so every capture is a stable, snackbar-free frame.
  if (find.byType(ScaffoldMessenger).evaluate().isNotEmpty) {
    t
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
        .clearSnackBars();
    // The dismiss animation must fully settle — a half-hidden bar still
    // diffs against the golden.
    for (
      var i = 0;
      i < 15 && find.byType(SnackBar).evaluate().isNotEmpty;
      i++
    ) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }
  // matchesGoldenFile rasterizes the whole window via captureImage; run with
  // --update-goldens so the PNG is written next to this file under out/.
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('out/$name.png'),
  );
}

const windowSize = Size(1200, 800);

/// Synthetic pid the FakeHostProbe reports as alive for "running VM"
/// captures — keeps the fixture free of real process dependencies.
const runningPid = 42424;

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => null,
        );
    _originalCwd = Directory.current;
    await _loadAllFonts();
    await TestLocalizationsDelegate.preload();
  });

  setUp(_resetVmDir);

  final pages = <String, Widget>{
    '02_machines_manager': const Manager(),
    '01_dashboard': const DashboardPage(),
    '03_create': const CreatePage(),
    '04_diagnostics': const DiagnosticsPage(),
    '05_os_selection': const OperatingSystemSelection(),
    '06_version_selection': VersionSelection(operatingSystem: _captureOs),
    '10_settings': const SettingsPage(),
    '11_activity': const ActivityPage(),
  };

  /// Opens the VM row popup, scrolls the item into view (the menu is taller
  /// than the viewport) and taps it. The resulting dialog reads the .conf
  /// with real file IO, so a real event-loop window follows the tap.
  Future<void> Function(WidgetTester t) menuItem(String label) => (t) async {
    await t.tap(find.byIcon(Icons.more_vert).first);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    // The VmActionsMenu renders rows as MenuItemButton inside a
    // MenuAnchor — and the details pane repeats labels such as
    // 'Snapshots' and 'Display viewer' in non-interactive rows, so the
    // finder must be scoped to the menu's own buttons.
    final menuItems = find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text(label),
    );
    final firstRow = find.text('Edit configuration').last;
    final scrollable = find
        .ancestor(of: firstRow, matching: find.byType(Scrollable))
        .first;
    // Rows near the menu's clip edge count as laid-out but their centre
    // is not hittable — centre the target inside the menu's viewport.
    final item = menuItems.last;
    final state = t.state<ScrollableState>(scrollable);
    final itemRect = t.getRect(item);
    final scrollRect = t.getRect(scrollable);
    state.position.jumpTo(
      state.position.pixels + itemRect.center.dy - scrollRect.center.dy,
    );
    await t.pumpAndSettle();
    await t.tap(item);
    // The popup closes via a Future chain (onSelected -> _editVmConfValues
    // -> File.readAsLines, whose open/read/close steps each need a real
    // event-loop turn followed by a fake-microtask flush).
    for (
      var i = 0;
      i < 12 && find.byType(AlertDialog).evaluate().isEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pump();
      await t.pump();
    }
  };

  /// Settings tiles below the fold aren't laid out yet — jump the list
  /// to the bottom first so the About section builds its children.
  Future<void> Function(WidgetTester t) settingsItem(String label) =>
      (t) async {
        final scrollable = find.byType(Scrollable).last;
        t
            .state<ScrollableState>(scrollable)
            .position
            .jumpTo(
              t.state<ScrollableState>(scrollable).position.maxScrollExtent,
            );
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        await t.tap(find.text(label).last);
      };

  /// Interactions run after the page settles; each produces one capture of
  /// the resulting menu/dialog, so the whole VM-actions surface is covered.
  final interactions = <String, Future<void> Function(WidgetTester t)>{
    '07_vm_menu': (t) async {
      await t.tap(find.byIcon(Icons.more_vert).first);
    },
    '08_vm_config_dialog': (t) async {
      await t.tap(find.byIcon(Icons.more_vert).first);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await t.tap(find.text('Edit configuration').last);
      // Mount the dialog so loadRaw() starts, then give the real file IO
      // a real event-loop window to complete.
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    },
    '09_vm_delete_confirm': (t) async {
      await t.tap(find.byIcon(Icons.more_vert).first);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      // 'Delete' is the last item — below the popup's viewport, so scroll
      // the menu before tapping. `.last` picks the menu item (overlay,
      // built later) over the details pane's own Delete button.
      final item = find.text('Delete').last;
      await t.scrollUntilVisible(
        item,
        -250,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(item);
    },
    // Conf-value dialogs read the .conf with real file IO before showing,
    // so they need a real event-loop window after the tap.
    '12_vm_snapshots': menuItem('Snapshots'),
    '13_vm_resources': menuItem('Resources'),
    '14_vm_boot_network': menuItem('Boot & network'),
    '15_vm_devices': menuItem('Devices'),
    '16_check_updates': (t) async {
      await settingsItem('Check for updates')(t);
      // fetchLatestQuickguiRelease hits the network (real IO) — a real
      // window lets the reply (or the offline error path) resolve.
      await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    },
    '17_system_diagnostics': settingsItem('Quickemu report'),
    '18_vm_menu_running': (t) async {
      await t.tap(find.byIcon(Icons.more_vert).first);
    },
    '19_vm_stop_confirm': (t) async {
      await t.tap(find.byIcon(Icons.stop).first);
    },
    '20_vm_process_output': menuItem('Check VM'),
    '21_vm_resize': menuItem('Resize disk'),
    '22_vm_clone': menuItem('Clone'),
    '23_vm_settings_all': menuItem('Settings (all)'),
    '24_vm_shared_folder': menuItem('Shared folder'),
    '25_vm_display_viewer': menuItem('Display viewer'),
  };

  final interactionHosts = <String, Widget>{
    '07_vm_menu': const Manager(),
    '08_vm_config_dialog': const Manager(),
    '09_vm_delete_confirm': const Manager(),
    '12_vm_snapshots': const Manager(),
    '13_vm_resources': const Manager(),
    '14_vm_boot_network': const Manager(),
    '15_vm_devices': const Manager(),
    '16_check_updates': const SettingsPage(),
    '17_system_diagnostics': const SettingsPage(),
    '18_vm_menu_running': const Manager(),
    '19_vm_stop_confirm': const Manager(),
    '20_vm_process_output': const Manager(),
    '21_vm_resize': const Manager(),
    '22_vm_clone': const Manager(),
    '23_vm_settings_all': const Manager(),
    '24_vm_shared_folder': const Manager(),
    '25_vm_display_viewer': const Manager(),
  };

  // Surfaces that only exist when a VM is running: the pid/ports files are
  // written before pumpWidget so the first _getVms scan marks it active.
  final interactionRunningVms = <String, String>{
    '18_vm_menu_running': 'debian-12',
    '19_vm_stop_confirm': 'debian-12',
  };

  // The Settings(all) dialog stacks 16 fields in a fixed Column — it needs
  // ~1100px of height to lay out fully (a real overflow bug at 800px).
  final interactionSizes = <String, Size>{
    '23_vm_settings_all': const Size(1200, 1300),
  };

  // Sample quickreport output so the System diagnostics dialog captures a
  // representative body instead of the fake backend's empty result.
  final interactionActionResults = <String, ProcResult>{
    '17_system_diagnostics': const ProcResult(0, '''
Quickemu 4.9.9
Quickget 4.9.9
QEMU 10.1.0
Host: Ubuntu 26.04.1 LTS (kernel 7.0.0-38-generic)
CPU: 8 cores, KVM available
spicy 0.42 — found
ssh-keygen — found
chunkcheck — found
All checks passed.
''', ''),
    '20_vm_process_output': const ProcResult(0, '''
quickemu --vm debian-12.conf --status debian-12
- guest_os=linux
- disk_img=debian-12/disk.qcow2 (64G)
- RAM: 4G, CPU cores: 4
- Boot: efi, Network: nat
- Display: spice (port 5930)
- SSH port: 2222
VM is stopped.
''', ''),
  };

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final e in pages.entries) {
      testWidgets('${e.key} ($theme)', (t) async {
        await _capture(t, _app(home: e.value, dark: dark), '${e.key}_$theme');
      });
    }
    for (final e in interactions.entries) {
      testWidgets('${e.key} ($theme)', (t) async {
        await _capture(
          t,
          _app(
            home: interactionHosts[e.key]!,
            dark: dark,
            actionResult: interactionActionResults[e.key],
            probe: interactionRunningVms.containsKey(e.key)
                ? (FakeHostProbe()
                    ..tools.add('spicy')
                    ..terminal = 'xterm'
                    ..alivePids = {runningPid})
                : null,
            runningVm: interactionRunningVms[e.key],
          ),
          '${e.key}_$theme',
          interact: e.value,
          runningVm: interactionRunningVms[e.key],
          size: interactionSizes[e.key],
        );
      });
    }
  }
}
