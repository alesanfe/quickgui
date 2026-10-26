import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import 'package:quickgui/features/machines/providers/backend_providers.dart';

import '../../../support/fakes/fake_preferences_repository.dart';
import '../../../support/fakes/fake_virtualization_backend.dart';

ProviderContainer _container(
  FakePreferencesRepository prefs, {
  FakeVirtualizationBackend? backend,
}) => ProviderContainer(
  overrides: [
    preferencesRepositoryProvider.overrideWithValue(prefs),
    if (backend != null) backendProvider.overrideWithValue(backend),
  ],
);

void main() {
  test('AppFailure maps to typed failed state and history entry', () async {
    final prefs = FakePreferencesRepository();
    final c = _container(prefs);
    addTearDown(c.dispose);
    final ctrl = c.read(activityProvider.notifier);

    await expectLater(
      ctrl.run(
        OperationKind.start,
        'vm1',
        (op) async => throw const AppFailure(
          AppFailureKind.timeout,
          'BACKEND_TIMEOUT',
          'Timed out',
          retryable: true,
        ),
      ),
      throwsA(isA<AppFailure>()),
    );

    final entry = c.read(activityProvider).history.single;
    expect(entry.status, OperationStatus.failed);
    expect(entry.failureCode, 'BACKEND_TIMEOUT');
    expect(entry.retryable, isTrue);
    expect(entry.message, 'Timed out');
  });

  test('non-zero exit records backend.exit_N code', () async {
    final prefs = FakePreferencesRepository();
    final c = _container(prefs);
    addTearDown(c.dispose);
    final ctrl = c.read(activityProvider.notifier);

    final r = await ctrl.run(
      OperationKind.stop,
      'vm1',
      (op) async => ProcessResult(0, 3, '', 'boom'),
    );
    expect(r.exitCode, 3);
    final entry = c.read(activityProvider).history.single;
    expect(entry.status, OperationStatus.failed);
    expect(entry.failureCode, 'backend.exit_3');
    expect(entry.retryable, isFalse);
  });

  test('terminal ops reject further transitions', () async {
    final prefs = FakePreferencesRepository();
    final c = _container(prefs);
    addTearDown(c.dispose);
    final ctrl = c.read(activityProvider.notifier);

    final op = ctrl.start(OperationKind.export, 'vm1');
    ctrl.update(op, const OperationState.succeeded(null));
    ctrl.update(op, const OperationState.failed(code: 'x', message: 'late'));
    expect(
      c.read(activityProvider).history.single.status,
      OperationStatus.succeeded,
    );
  });

  test('interrupted ops restore as interrupted history', () async {
    final prefs = FakePreferencesRepository()
      ..store['activeOperations'] = [
        '{"kind":"download","target":"iso","startedAt":"2026-01-01T00:00:00.000Z","completedAt":"2026-01-01T00:01:00.000Z","status":"interrupted","message":""}',
      ];
    final c = _container(prefs);
    addTearDown(c.dispose);
    // Reading the provider once triggers build() (and the async
    // _restore()); the awaited preference calls then need real
    // event-loop turns to complete.
    c.read(activityProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final history = c.read(activityProvider).history;
    expect(history, isNotEmpty);
    expect(history.first.status, OperationStatus.interrupted);
  });

  test('history round-trips failureCode and retryable', () {
    final entry = OperationHistoryEntry(
      kind: OperationKind.delete,
      target: 'vm9',
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      completedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      status: OperationStatus.failed,
      message: 'gone',
      failureCode: 'VM_NOT_FOUND',
    );
    final decoded = OperationHistoryEntry.fromJson(entry.toJson());
    expect(decoded?.failureCode, 'VM_NOT_FOUND');
    expect(decoded?.retryable, isFalse);
  });

  group('extended states', () {
    test('queued and paused are busy but not terminal', () {
      const queued = OperationState<void>.queued();
      const paused = OperationState<void>.paused(progress: 0.5);
      expect(queued.isBusy, isTrue);
      expect(queued.isTerminal, isFalse);
      expect(paused.isBusy, isTrue);
      expect(paused.isTerminal, isFalse);
    });

    test('interrupted is terminal but not failed', () {
      const interrupted = OperationState<void>.interrupted();
      expect(interrupted.isBusy, isFalse);
      expect(interrupted.isTerminal, isTrue);
    });

    test('markInterrupted records interrupted history, not failed', () {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      final op = ctrl.start(OperationKind.export, 'vm1');
      ctrl.markInterrupted(op);

      final entry = c.read(activityProvider).history.single;
      expect(entry.status, OperationStatus.interrupted);
      expect(c.read(activityProvider).active, isEmpty);
    });

    test('interrupted op rejects further transitions', () {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      final op = ctrl.start(OperationKind.resize, 'vm1');
      ctrl.markInterrupted(op);
      ctrl.update(op, const OperationState.succeeded(null));
      expect(
        c.read(activityProvider).history.single.status,
        OperationStatus.interrupted,
      );
    });
  });

  group('retry', () {
    test('retrySpec round-trips through history json', () {
      const spec = RetrySpec(
        command: 'pause',
        arguments: ['--vm', 'vm1.conf', '--pause'],
        idempotent: true,
      );
      final entry = OperationHistoryEntry(
        id: 'op1',
        kind: OperationKind.command,
        target: 'vm1',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: DateTime.fromMillisecondsSinceEpoch(1),
        status: OperationStatus.failed,
        failureCode: 'BACKEND_TIMEOUT',
        retryable: true,
        retrySpec: spec,
      );
      final decoded = OperationHistoryEntry.fromJson(entry.toJson())!;
      expect(decoded.retrySpec?.command, 'pause');
      expect(decoded.retrySpec?.arguments, contains('--pause'));
      expect(decoded.retrySpec?.idempotent, isTrue);
      expect(decoded.canRetry, isTrue);
    });

    test('entries without a spec cannot be retried', () {
      final entry = OperationHistoryEntry(
        kind: OperationKind.delete,
        target: 'vm1',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: DateTime.fromMillisecondsSinceEpoch(1),
        status: OperationStatus.failed,
        failureCode: 'VM_NOT_FOUND',
        retryable: true,
      );
      expect(entry.canRetry, isFalse);
    });

    test('plan-regenerating specs are refused by retry()', () async {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);
      final entry = OperationHistoryEntry(
        kind: OperationKind.delete,
        target: 'vm1',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: DateTime.fromMillisecondsSinceEpoch(1),
        status: OperationStatus.failed,
        retryable: true,
        retrySpec: const RetrySpec(
          command: 'delete-vm',
          arguments: ['--vm', 'vm1.conf', '--delete-vm'],
          regeneratesPlan: true,
        ),
      );
      await expectLater(ctrl.retry(entry), throwsStateError);
    });
  });

  group('reconcile', () {
    test(
      'interrupted start resolves to succeeded when VM is running',
      () async {
        final prefs = FakePreferencesRepository();
        final backend = FakeVirtualizationBackend()
          ..states = {
            'vm1': {'name': 'vm1', 'state': 'running', 'pid': 42},
          };
        final c = _container(prefs, backend: backend);
        addTearDown(c.dispose);
        final ctrl = c.read(activityProvider.notifier);
        final op = ctrl.start(OperationKind.start, 'vm1');
        ctrl.markInterrupted(op);

        await ctrl.reconcile();

        expect(
          c.read(activityProvider).history.single.status,
          OperationStatus.succeeded,
        );
      },
    );

    test('interrupted op without evidence stays interrupted', () async {
      final prefs = FakePreferencesRepository();
      final backend = FakeVirtualizationBackend()
        ..states = {
          'vm1': {'name': 'vm1', 'state': 'stopped', 'pid': null},
        };
      final c = _container(prefs, backend: backend);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);
      final op = ctrl.start(OperationKind.start, 'vm1');
      ctrl.markInterrupted(op);

      await ctrl.reconcile();

      expect(
        c.read(activityProvider).history.single.status,
        OperationStatus.interrupted,
      );
    });
  });
}
