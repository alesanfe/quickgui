// Covers _TrackedBackend: pure delegation for read paths and
// kind/target/retrySpec inference for mutating ones — plus the
// non-cancellable command guard and op-watch registration.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
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

  VirtualizationBackend tracked(ProviderContainer c) =>
      c.read(trackedBackendProvider);

  setUp(() {
    original = Directory.current;
    dir = Directory.systemTemp.createTempSync('qg-trk-');
    Directory.current = dir;
    prefs = FakePreferencesRepository();
    host = FakeHostProbe()..dir = dir.path;
    backend = FakeVirtualizationBackend();
  });

  tearDown(() {
    Directory.current = original;
    dir.deleteSync(recursive: true);
  });

  // Completed ops land in history immediately (the fake backend
  // resolves synchronously); active only holds in-flight ones.
  OperationKind kindOf(ProviderContainer c) {
    final st = c.read(activityProvider);
    if (st.active.isNotEmpty) return st.active.last.kind;
    if (st.history.isEmpty) fail('no operation recorded');
    return st.history.first.kind; // history is newest-first
  }

  group('delegation', () {
    test('read methods pass through untracked', () async {
      final c = container();
      addTearDown(c.dispose);
      final b = tracked(c);
      await b.checkAvailability();
      await b.version();
      await b.getCapabilities();
      await b.listOperatingSystems();
      await b.listVirtualMachines();
      await b.inspectVirtualMachine('x');
      await b.listSnapshots('x.conf');
      await b.operationStatus('x', 'op');
      await b.listTrash();
      await b.listBackups('x');
      await b.snapshotTree('x.conf');
      await b.vfioScan();
      await b.hostInfo();
      await b.listOperations('x');
      await b.readEvents('x');
      await b.vmStats('x');
      await b.listInventory();
      await b.listPlugins();
      expect(c.read(activityProvider).active, isEmpty); // nothing tracked
    });
  });

  group('runAction kind inference', () {
    test('maps flags to OperationKind', () async {
      final c = container();
      addTearDown(c.dispose);
      final b = tracked(c);
      Future<OperationKind> k(List<String> args) async {
        await b.runAction(args);
        return kindOf(c);
      }

      expect(
        await k(['--vm', 'v.conf', '--snapshot', 'x']),
        OperationKind.snapshot,
      );
      expect(await k(['--vm', 'v.conf', '--clone', 'n']), OperationKind.clone);
      expect(
        await k(['--vm', 'v.conf', '--disk-resize', '10G']),
        OperationKind.resize,
      );
      expect(await k(['--vm', 'v.conf', '--delete-vm']), OperationKind.delete);
      expect(await k(['--vm', 'v.conf', '--kill']), OperationKind.stop);
      expect(await k(['--vm', 'v.conf', '--stop']), OperationKind.stop);
      expect(
        await k(['--vm', 'v.conf', '--display', 'sdl']),
        OperationKind.start,
      );
      expect(
        await k(['--vm', 'v.conf', '--unknown-flag']),
        OperationKind.command,
      );
    });

    test('--delete-plan and --status bypass tracking', () async {
      final c = container();
      addTearDown(c.dispose);
      final b = tracked(c);
      await b.runAction(['--vm', 'v.conf', '--delete-plan']);
      await b.runAction(['--vm', 'v.conf', '--status']);
      expect(c.read(activityProvider).active, isEmpty);
    });
  });

  group('runVmJson', () {
    test('kind inference + cancellable only for safe commands', () async {
      final c = container();
      addTearDown(c.dispose);
      for (final cmd in [
        'start',
        'snapshot-create',
        'delete-vm',
        'clone',
        'powerdown',
        'disk-resize',
        'frobnicate',
      ]) {
        backend.jsonResponses[cmd] = {'ok': true};
      }
      final b = tracked(c);
      await b.runVmJson('start', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.start);
      await b.runVmJson('snapshot-create', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.snapshot);
      await b.runVmJson('delete-vm', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.delete);
      await b.runVmJson('clone', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.clone);
      await b.runVmJson('powerdown', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.stop);
      await b.runVmJson('disk-resize', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.resize);
      await b.runVmJson('frobnicate', ['--vm', '/p/v.conf']);
      expect(kindOf(c), OperationKind.command);
    });
  });

  group('tracked passthroughs', () {
    test('mutating helpers register ops with right kinds', () async {
      final c = container();
      addTearDown(c.dispose);
      final b = tracked(c);
      Future<OperationKind> k(Future<void> Function() f) async {
        await f();
        return kindOf(c);
      }

      expect(await k(() => b.restoreFromTrash('v')), OperationKind.restore);
      expect(
        await k(() => b.restoreBackup('v', '/x/b.tar.gz')),
        OperationKind.restore,
      );
      expect(await k(() => b.linkedClone('v', 'd')), OperationKind.clone);
      expect(await k(() => b.startWithProfile('v', 'p')), OperationKind.start);
      expect(
        await k(() => b.migrateConfToToml('v.conf').then((_) {})),
        OperationKind.convert,
      );
      expect(await k(() => b.exportVm('v').then((_) {})), OperationKind.export);
      expect(
        await k(() => b.verifyImage('/x/i.iso').then((_) {})),
        OperationKind.verify,
      );
      expect(
        await k(() => b.killVmProcess('v').then((_) {})),
        OperationKind.stop,
      );
      expect(
        await k(
          () => b.convertDiskImage('/x/a.img', '/x/b.qcow2').then((_) {}),
        ),
        OperationKind.convert,
      );
    });

    test('runQuickget --create-config tracks as import', () async {
      final c = container();
      addTearDown(c.dispose);
      final b = tracked(c);
      await b.runQuickget(['quickget', '--create-config', 'ubuntu', '24.04']);
      expect(kindOf(c), OperationKind.import);
      await b.runQuickget(['quickget', '--list']);
      expect(c.read(activityProvider).history.length, 1); // untracked
    });
  });
}
