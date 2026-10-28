import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/application/delete_vm.dart';
import 'package:quickgui/features/machines/application/create_vm.dart';
import 'package:quickgui/features/machines/application/inspect_vm.dart';
import 'package:quickgui/features/machines/application/start_vm.dart';
import 'package:quickgui/features/machines/application/stop_vm.dart';
import 'package:quickgui/core/result/result.dart';

import '../../../../support/fakes/fake_virtualization_backend.dart';

import 'package:quickgui/features/machines/application/ports/proc.dart';

void main() {
  for (final option in <String?>[null, '', 'desktop']) {
    test('create forwards OS release and optional edition ($option)', () async {
      final fake = FakeVirtualizationBackend();
      expect(await CreateVm(fake)('ubuntu', '24.04', option), isA<Ok<void>>());
      expect(fake.quickgetCalls, [
        ['ubuntu', '24.04', if (option != null && option.isNotEmpty) option],
      ]);
    });
  }
  test(
    'create fails without executing quickget when backend is absent',
    () async {
      final fake = FakeVirtualizationBackend()..available = false;
      final result = await CreateVm(fake)('ubuntu', '24.04');
      expect((result as Err<void>).failure.code, 'backend.unavailable');
      expect(fake.quickgetCalls, isEmpty);
    },
  );
  test('create propagates command failure', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(1, '', 'image unavailable');
    final result = await CreateVm(fake)('ubuntu', '24.04');
    expect((result as Err<void>).failure.code, 'vm.create_failed');
  });
  test('inspect returns the requested machine state', () async {
    final fake = FakeVirtualizationBackend()
      ..states = {
        'vm': {'state': 'paused', 'pid': 123},
      };
    final result = await InspectVm(fake)('vm');
    expect((result as Ok<Map<String, dynamic>>).value, {
      'state': 'paused',
      'pid': 123,
    });
  });
  test('inspect reports missing backend', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final result = await InspectVm(fake)('vm');
    expect(
      (result as Err<Map<String, dynamic>>).failure.code,
      'backend.unavailable',
    );
  });
  test('stop sends kill to the requested VM', () async {
    final fake = FakeVirtualizationBackend();
    expect(await StopVm(fake)('vm'), isA<Ok<void>>());
    expect(fake.actionCalls, [
      ['--vm', 'vm.conf', '--kill'],
    ]);
  });
  test('stop does not execute when backend is absent', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final result = await StopVm(fake)('vm');
    expect((result as Err<void>).failure.code, 'backend.unavailable');
    expect(fake.actionCalls, isEmpty);
  });

  for (final diskOnly in [false, true]) {
    test('delete selects only requested scope (diskOnly=$diskOnly)', () async {
      final fake = FakeVirtualizationBackend();
      final result = await DeleteVm(fake)('vm with spaces', diskOnly: diskOnly);
      expect(result, isA<Ok<void>>());
      expect(fake.actionCalls, [
        [
          '--vm',
          'vm with spaces.conf',
          if (diskOnly) '--delete-disk' else '--delete-vm',
        ],
      ]);
    });
  }

  test('delete refuses to execute when backend is missing', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final result = await DeleteVm(fake)('vm');
    expect((result as Err<void>).failure.code, 'backend.unavailable');
    expect(fake.actionCalls, isEmpty);
  });

  test('delete surfaces process failure without retrying', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(2, '', 'permission denied');
    final result = await DeleteVm(fake)('vm');
    expect((result as Err<void>).failure.code, 'vm.delete_failed');
    expect(fake.actionCalls, hasLength(1));
  });

  test('requesting a delete plan never issues a delete command', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(0, '{"schemaVersion":1}\n', '');
    final result = await DeleteVm(fake).plan('vm');
    expect(result, isA<Ok<DeletePlan>>());
    expect(fake.actionCalls, [
      ['--vm', 'vm.conf', '--delete-plan', '--format', 'json'],
    ]);
  });

  test('delete plan surfaces a failed process', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(1, '', 'invalid config');
    final result = await DeleteVm(fake).plan('vm');
    expect((result as Err<DeletePlan>).failure.code, 'vm.delete_plan_failed');
  });

  for (final display in <String?>[null, '', 'spice', 'none']) {
    test(
      'start preserves VM argument and display override ($display)',
      () async {
        final fake = FakeVirtualizationBackend();
        final result = await StartVm(fake)('vm ; echo test', display: display);
        expect(result, isA<Ok<void>>());
        expect(fake.actionCalls, [
          [
            '--vm',
            'vm ; echo test.conf',
            if (display != null && display.isNotEmpty) ...[
              '--display',
              display,
            ],
          ],
        ]);
      },
    );
  }

  test('start refuses to execute when backend is missing', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final result = await StartVm(fake)('vm');
    expect((result as Err<void>).failure.code, 'backend.unavailable');
    expect(fake.actionCalls, isEmpty);
  });

  test('start surfaces nonzero exit as a typed failure', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(1, '', 'bad firmware');
    final result = await StartVm(fake)('vm');
    expect((result as Err<void>).failure.code, 'vm.start_failed');
  });

  test('start sends the right args and succeeds', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(0, 'ok', '');
    final r = await StartVm(fake)('vm1');
    expect(r, isA<Ok<void>>());
    expect(fake.actionCalls, [
      ['--vm', 'vm1.conf'],
    ]);
  });

  test('stop surfaces typed failure on nonzero exit', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = const ProcResult(1, '', 'boom');
    final r = await StopVm(fake)('vm1');
    expect((r as Err<void>).failure.code, 'vm.stop_failed');
  });

  test('delete plan returns typed failure when backend missing', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final r = await DeleteVm(fake).plan('vm1');
    expect((r as Err<DeletePlan>).failure.code, 'backend.unavailable');
  });
}
