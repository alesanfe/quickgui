import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/machines/providers/vm_tags_providers.dart';
import 'package:quickgui/features/settings/domain/ui_preferences.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../../support/fakes/fake_host_probe.dart';
import '../../support/fakes/fake_preferences_repository.dart';
import '../../support/fakes/fake_virtualization_backend.dart';

void main() {
  late FakePreferencesRepository prefs;
  late FakeHostProbe host;
  late FakeVirtualizationBackend backend;
  late Directory dir;
  late Directory original;

  ProviderContainer container() => ProviderContainer(
    overrides: [
      preferencesRepositoryProvider.overrideWithValue(prefs),
      hostProbeProvider.overrideWithValue(host),
      backendProvider.overrideWithValue(backend),
    ],
  );

  setUp(() {
    original = Directory.current;
    dir = Directory.systemTemp.createTempSync('qg-prov-');
    Directory.current = dir;
    prefs = FakePreferencesRepository();
    host = FakeHostProbe()..dir = dir.path;
    backend = FakeVirtualizationBackend();
  });

  tearDown(() {
    Directory.current = original;
    dir.deleteSync(recursive: true);
  });

  group('VmTagsController', () {
    test('starts empty and persists tags', () async {
      final c = container();
      addTearDown(c.dispose);
      final ctrl = c.read(vmTagsProvider.notifier);
      expect(c.read(vmTagsProvider), isEmpty);
      await ctrl.setTags('vm1', ['prod', 'linux']);
      await ctrl.addTag('vm1', 'prod'); // dedup
      await ctrl.addTag('vm2', 'dev');
      expect(ctrl.tagsFor('vm1'), ['prod', 'linux']);
      expect(ctrl.allTags, ['dev', 'linux', 'prod']);
      final stored = prefs.store[prefVmTags]! as String;
      expect(stored, contains('vm1'));
      await ctrl.removeTag('vm1', 'linux');
      expect(ctrl.tagsFor('vm1'), ['prod']);
      await ctrl.setTags('vm1', const []);
      expect(ctrl.tagsFor('vm1'), isEmpty);
    });

    test('loads persisted JSON and survives corruption', () async {
      prefs.store[prefVmTags] = '{"a":["x","y"],"b":42}';
      final c = container();
      addTearDown(c.dispose);
      final ctrl = c.read(vmTagsProvider.notifier);
      await pumpEventQueue();
      expect(ctrl.tagsFor('a'), ['x', 'y']);
      expect(ctrl.tagsFor('b'), isEmpty); // non-List value skipped
      prefs.store[prefVmTags] = '{not json';
      final c2 = container();
      addTearDown(c2.dispose);
      await pumpEventQueue();
      expect(c2.read(vmTagsProvider), isEmpty);
    });
  });

  group('UiPreferencesController', () {
    test('defaults then loads persisted values', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(c.read(uiPreferencesProvider), const UiPreferences());
      await pumpEventQueue();
      prefs.store[prefRefreshIntervalSeconds] = 9;
      prefs.store[prefPreferredViewer] = 'remote-viewer';
      prefs.store[prefNotifyOnComplete] = false;
      prefs.store[prefConfirmRiskyActions] = false;
      prefs.store[prefAdvancedConfig] = true;
      final c2 = container();
      addTearDown(c2.dispose);
      c2.read(uiPreferencesProvider);
      await pumpEventQueue();
      final s = c2.read(uiPreferencesProvider);
      expect(s.refreshIntervalSeconds, 9);
      expect(s.preferredViewer, 'remote-viewer');
      expect(s.notifyOnComplete, isFalse);
      expect(s.confirmRiskyActions, isFalse);
      expect(s.advancedConfig, isTrue);
    });

    test('setters update state and persist', () async {
      final c = container();
      addTearDown(c.dispose);
      final ctrl = c.read(uiPreferencesProvider.notifier);
      await pumpEventQueue(); // let async _load settle before writing
      await ctrl.setRefreshIntervalSeconds(30);
      await ctrl.setPreferredViewer('spicy');
      await ctrl.setNotifyOnComplete(false);
      await ctrl.setConfirmRiskyActions(false);
      await ctrl.setAdvancedConfig(true);
      final s = c.read(uiPreferencesProvider);
      expect(s.refreshIntervalSeconds, 30);
      expect(prefs.store[prefPreferredViewer], 'spicy');
      expect(prefs.store[prefNotifyOnComplete], false);
      expect(prefs.store[prefConfirmRiskyActions], false);
      expect(prefs.store[prefAdvancedConfig], true);
    });
  });

  group('vmLibraryProvider', () {
    test('lists conf-backed VMs sorted, skips non-VM files', () async {
      File('${dir.path}/b.conf').writeAsStringSync('guest_os="linux"\n');
      File('${dir.path}/a.conf')
          .writeAsStringSync('guest_os="windows"\ndisk_img="disk.qcow2"\n');
      File('${dir.path}/a/disk.qcow2').createSync(recursive: true);
      File('${dir.path}/a/disk.qcow2').writeAsStringSync('xxxx');
      File('${dir.path}/note.txt').writeAsStringSync('not a vm');
      File('${dir.path}/novm.conf').writeAsStringSync('ram="2G"\n');
      // The provider inspects VMs by their full path minus extension.
      backend.states = {
        '${dir.path}/a': {'name': 'a', 'state': 'running', 'pid': 111},
        '${dir.path}/b': {'name': 'b', 'state': 'stopped'},
      };
      host.alivePids = {111};
      Directory('${dir.path}/a').createSync(recursive: true);
      File('${dir.path}/a/a.pid').writeAsStringSync('111\n');
      final c = container();
      addTearDown(c.dispose);
      final vms = await c.read(vmLibraryProvider.future);
      expect(vms.map((v) => v.name), ['a', 'b']);
      final a = vms.first;
      expect(a.state, 'running');
      expect(a.pid, 111);
      expect(a.active, isTrue);
      expect(a.values['guest_os'], 'windows');
      expect(vms.last.state, 'stopped');
      expect(vms.last.active, isFalse);
    });

    test('marks stale VMs whose pid died', () async {
      File('${dir.path}/gone.conf').writeAsStringSync('guest_os="linux"\n');
      Directory('${dir.path}/gone').createSync();
      File('${dir.path}/gone/gone.pid').writeAsStringSync('999');
      backend.states = {
        '${dir.path}/gone': {'name': 'gone', 'state': 'running', 'pid': 999},
      };
      host.alivePids = const {}; // pid 999 not alive
      final c = container();
      addTearDown(c.dispose);
      final vms = await c.read(vmLibraryProvider.future);
      expect(vms.single.state, 'stale');
    });

    test('empty directory yields an empty library', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(await c.read(vmLibraryProvider.future), isEmpty);
    });

    test('hostFreeSpaceProvider delegates to the probe', () async {
      host.free = 1234;
      final c = container();
      addTearDown(c.dispose);
      expect(await c.read(hostFreeSpaceProvider.future), 1234);
    });
  });

  group('AppFailure', () {
    test('fileWrite carries path, retryable and suggestion', () {
      final f = AppFailure.fileWrite('/x/vm.conf', 'io error');
      expect(f.kind, AppFailureKind.fileWrite);
      expect(f.code, 'CONF_WRITE_FAILED');
      expect(f.retryable, isTrue);
      expect(f.technical, contains('/x/vm.conf'));
      expect(f.suggestion, isNotEmpty);
    });

    test('externalModification and process factories', () {
      final e = AppFailure.externalModification('/x.conf');
      expect(e.kind, AppFailureKind.externalModification);
      final p = AppFailure.process(
        'QEMU_DIED',
        'vm died',
        exitCode: 1,
        stderr: 'boom',
        vm: 'v1',
        retryable: true,
      );
      expect(p.kind, AppFailureKind.processGone);
      expect(p.technical, 'boom');
      expect(p.exitCode, 1);
      expect(p.vm, 'v1');
    });

    test('cancelled keeps operation/vm context', () {
      final f = AppFailure.cancelled(operation: 'op9', vm: 'v7');
      expect(f.kind, AppFailureKind.cancelled);
      expect(f.operation, 'op9');
      expect(f.vm, 'v7');
    });

    test('summary and toReportLine expose the stable fields', () {
      const f = AppFailure(
        AppFailureKind.portBusy,
        'PORT_BUSY',
        'port taken',
        vm: 'v',
        operation: 'o',
        phase: 'launch',
        exitCode: 3,
        retryable: true,
        partialChanges: true,
      );
      expect(f.summary, 'PORT_BUSY: port taken');
      final line = f.toReportLine();
      for (final part in [
        'code=PORT_BUSY',
        'kind=portBusy',
        'vm=v',
        'operation=o',
        'phase=launch',
        'exit=3',
        'retryable=true',
        'partialChanges=true',
      ]) {
        expect(line, contains(part));
      }
      expect('$f', 'AppFailure(PORT_BUSY): port taken');
    });

    test('isBackendEnvelopeMissing whitelists only envelope absence', () {
      for (final code in [
        'EMPTY_RESPONSE',
        'MALFORMED_JSON',
        'UNEXPECTED_SHAPE',
        'MISSING_SCHEMA_VERSION',
      ]) {
        expect(
          isBackendEnvelopeMissing(
            AppFailure(AppFailureKind.backendContract, code, 'x'),
          ),
          isTrue,
          reason: code,
        );
      }
      // Contract defects must NOT fall back.
      for (final code in ['CONTRACT_TOO_NEW', 'WRONG_COMMAND', 'X']) {
        expect(
          isBackendEnvelopeMissing(
            AppFailure(AppFailureKind.backendContract, code, 'x'),
          ),
          isFalse,
          reason: code,
        );
      }
      // Other kinds never qualify.
      expect(
        isBackendEnvelopeMissing(
          const AppFailure(AppFailureKind.timeout, 'EMPTY_RESPONSE', 'x'),
        ),
        isFalse,
      );
    });
  });
}
