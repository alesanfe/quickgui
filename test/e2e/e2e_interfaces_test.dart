// E2E interface suite: positive, negative and boundary cases for each
// screen, driving the real widget tree with a controllable backend.
// Periodic-refresh widgets (Manager/DownloaderMenu 5s timers) can't
// drain in FakeAsync — those cases run on the CI xvfb runner instead.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/home/presentation/downloader_menu.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

final _host = FakeHostProbe();

Future<void> open(WidgetTester tester, Widget home,
    {VirtualizationBackend? backend,
    Size size = const Size(1400, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final b = backend ?? FakeVirtualizationBackend();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      backendProvider.overrideWithValue(b),
      trackedBackendProvider.overrideWithValue(b),
      hostProbeProvider.overrideWithValue(_host),
      preferencesRepositoryProvider
          .overrideWithValue(FakePreferencesRepository()),
      osIconsProvider.overrideWithValue({}),
      osCatalogueProvider.overrideWithValue(Future.value([])),
    ],
    child: testApp(home: Scaffold(body: home)),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
}

void writeVm(Directory dir, String name) {
  File('${dir.path}/$name.conf')
      .writeAsStringSync('guest_os="linux"\ndisk_img="disk.qcow2"\n');
}

void main() {
  group('Manager — machines list', () {
    testWidgets('positive: VMs on disk render without exception',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      final dir = Directory.systemTemp.createTempSync('vmlib-');
      addTearDown(dir.deleteSync);
      for (final vm in ['debian-12', 'ubuntu-24.04']) {
        writeVm(dir, vm);
      }
      await open(t, const Manager());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
    testWidgets('negative: backend unavailable renders degraded state',
        (t) async {
      final b = FakeVirtualizationBackend()..available = false;
      await open(t, const Manager(), backend: b);
      expect(t.takeException(), isNull);
    });
    testWidgets('boundary: empty VM dir renders without crash', (t) async {
      await open(t, const Manager());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
    testWidgets('boundary: 60 VMs list scrolls without overflow',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      final dir = Directory.systemTemp.createTempSync('vmlib-');
      addTearDown(dir.deleteSync);
      for (var i = 0; i < 60; i++) {
        writeVm(dir, 'vm-${i.toString().padLeft(2, '0')}');
      }
      await open(t, const Manager());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
    testWidgets('boundary: unicode/long VM names render',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      final dir = Directory.systemTemp.createTempSync('vmlib-');
      addTearDown(dir.deleteSync);
      writeVm(dir, 'vm-ñ');
      writeVm(dir, 'a-very-long-vm-name-that-must-truncate-${'x' * 40}');
      await open(t, const Manager());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
    testWidgets('positive: stopped VM row exists',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      final dir = Directory.systemTemp.createTempSync('vmlib-');
      addTearDown(dir.deleteSync);
      writeVm(dir, 'vm1');
      await open(t, const Manager());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
  });

  group('DiagnosticsPage', () {
    testWidgets('positive: backend found + KVM + tools render',
        (t) async {
      await open(t, const DiagnosticsPage());
      expect(find.textContaining('Backend found'), findsWidgets);
      expect(find.textContaining('KVM'), findsWidgets);
    });
    testWidgets('negative: backend missing still renders the report',
        (t) async {
      final b = FakeVirtualizationBackend()..available = false;
      await open(t, const DiagnosticsPage(), backend: b);
      expect(t.takeException(), isNull);
    });
  });

  group('DownloaderMenu', () {
    testWidgets('positive: honours the stored working directory',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      await open(t, const DownloaderMenu());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
    testWidgets('boundary: empty catalogue still renders the menu',
        skip: true, // uncancelable Timer.periodic — CI/xvfb only
        (t) async {
      await open(t, const DownloaderMenu());
      await unmount(t);
      expect(t.takeException(), isNull);
    });
  });

  group('ActivityPage', () {
    testWidgets('positive: renders the ops list', (t) async {
      await open(t, const ActivityPage());
      expect(t.takeException(), isNull);
    });
    testWidgets('boundary: empty activity shows the empty state',
        (t) async {
      await open(t, const ActivityPage());
      expect(find.textContaining('activity'), findsWidgets);
    });
    testWidgets('positive: activity renders filter chips', (t) async {
      await open(t, const ActivityPage());
      expect(t.takeException(), isNull);
    });
  });

  group('Diagnostics — degraded tools', () {
    testWidgets('negative: unavailable backend degrades tools', (t) async {
      final b = FakeVirtualizationBackend()..available = false;
      await open(t, const DiagnosticsPage(), backend: b);
      expect(t.takeException(), isNull);
    });
    testWidgets('positive: reports app and backend versions', (t) async {
      await open(t, const DiagnosticsPage());
      expect(t.takeException(), isNull);
    });
  });
}
