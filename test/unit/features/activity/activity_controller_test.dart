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

import 'package:quickgui/features/machines/application/ports/proc.dart';

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
      (op) async => const ProcResult(3, '', 'boom'),
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

  group('failure lifecycle (QG-013)', () {
    OperationHistoryEntry entry({
      OperationStatus status = OperationStatus.failed,
      bool retryable = false,
      String? id,
      String? retryOf,
    }) => OperationHistoryEntry(
      id: id,
      kind: OperationKind.start,
      target: 'vm1',
      startedAt: DateTime.fromMillisecondsSinceEpoch(0),
      completedAt: DateTime.fromMillisecondsSinceEpoch(1),
      status: status,
      retryable: retryable,
      retryOf: retryOf,
    );

    test('failed-retryable starts as requiresAction', () async {
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

      final e = c.read(activityProvider).history.single;
      expect(e.lifecycle, OperationLifecycle.requiresAction);
      expect(e.requiresAction, isTrue);
    });

    test('non-retryable failure starts as permanentlyFailed', () async {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      await ctrl.run(
        OperationKind.start,
        'vm1',
        (op) async => const ProcResult(3, '', 'boom'),
      );

      final e = c.read(activityProvider).history.single;
      expect(e.status, OperationStatus.failed);
      expect(e.lifecycle, OperationLifecycle.permanentlyFailed);
      expect(e.requiresAction, isFalse);
    });

    test('interrupted starts as requiresAction', () {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);
      final op = ctrl.start(OperationKind.export, 'vm1');
      ctrl.markInterrupted(op);
      expect(
        c.read(activityProvider).history.single.lifecycle,
        OperationLifecycle.requiresAction,
      );
    });

    test('acknowledge and ignore transition lifecycle', () async {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);
      final op = ctrl.start(OperationKind.export, 'vm1');
      ctrl.markInterrupted(op);
      final e = c.read(activityProvider).history.single;

      ctrl.acknowledge(e);
      expect(
        c.read(activityProvider).history.single.lifecycle,
        OperationLifecycle.acknowledged,
      );
      ctrl.ignore(c.read(activityProvider).history.single);
      expect(
        c.read(activityProvider).history.single.lifecycle,
        OperationLifecycle.ignored,
      );
    });

    test('lifecycle round-trips through json', () {
      final e = entry(
        id: 'a',
        retryable: true,
      ).copyWith(lifecycle: OperationLifecycle.acknowledged);
      final decoded = OperationHistoryEntry.fromJson(e.toJson())!;
      expect(decoded.lifecycle, OperationLifecycle.acknowledged);
      // Entries persisted before the field existed derive a sensible
      // default from status+retryable.
      final legacy = OperationHistoryEntry.fromJson({
        'kind': 'start',
        'target': 'vm1',
        'startedAt': '2026-01-01T00:00:00.000Z',
        'completedAt': '2026-01-01T00:01:00.000Z',
        'status': 'failed',
        'message': '',
        'retryable': true,
      })!;
      expect(legacy.lifecycle, OperationLifecycle.requiresAction);
    });

    test('identical failures merge into one entry with a counter', () {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      for (var i = 0; i < 3; i++) {
        final op = ctrl.start(OperationKind.start, 'vm1');
        ctrl.update(
          op,
          const OperationState.failed(
            code: 'BACKEND_TIMEOUT',
            message: 'Timed out',
            retryable: true,
          ),
        );
      }
      final history = c.read(activityProvider).history;
      expect(history, hasLength(1));
      expect(history.single.occurrences, 3);
    });

    test('distinct failures are not merged', () {
      final prefs = FakePreferencesRepository();
      final c = _container(prefs);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      for (final code in ['A', 'B']) {
        final op = ctrl.start(OperationKind.start, 'vm1');
        ctrl.update(op, OperationState.failed(code: code, message: 'x'));
      }
      expect(c.read(activityProvider).history, hasLength(2));
    });
  });

  group('retry guards and lineage (QG-015)', () {
    const spec = RetrySpec(
      command: 'start',
      arguments: ['--vm', 'vm1.conf'],
      idempotent: true,
    );

    test('concurrent retry of same target is refused', () async {
      final prefs = FakePreferencesRepository();
      final backend = FakeVirtualizationBackend()
        ..jsonResponses['start'] = {'state': 'ok'};
      final c = _container(prefs, backend: backend);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      final entry = OperationHistoryEntry(
        id: 'orig',
        kind: OperationKind.start,
        target: 'vm1',
        startedAt: DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: DateTime.fromMillisecondsSinceEpoch(1),
        status: OperationStatus.failed,
        retryable: true,
        retrySpec: spec,
      );
      // An unrelated op already in flight on the same target+kind
      // must block a second dispatch.
      ctrl.start(OperationKind.start, 'vm1');
      expect(ctrl.retryInFlight(entry), isTrue);
      await expectLater(ctrl.retry(entry), throwsStateError);
    });

    test('successful retry marks original recovered', () async {
      final prefs = FakePreferencesRepository();
      final backend = FakeVirtualizationBackend()
        ..jsonResponses['start'] = {'state': 'ok'};
      final c = _container(prefs, backend: backend);
      addTearDown(c.dispose);
      final ctrl = c.read(activityProvider.notifier);

      // Seed a retryable failure through the normal path — a typed
      // AppFailure with an idempotent spec.
      await expectLater(
        ctrl.run(
          OperationKind.start,
          'vm2',
          (op) async => throw const AppFailure(
            AppFailureKind.timeout,
            'BACKEND_TIMEOUT',
            'Timed out',
            retryable: true,
          ),
          retrySpec: spec,
        ),
        throwsA(isA<AppFailure>()),
      );
      final failed = c.read(activityProvider).history.single;
      expect(failed.canRetry, isTrue);
      expect(failed.lifecycle, OperationLifecycle.requiresAction);

      await ctrl.retry(failed);

      final orig = c
          .read(activityProvider)
          .history
          .firstWhere((e) => e.id == failed.id);
      expect(orig.lifecycle, OperationLifecycle.recovered);
      final attempt = c
          .read(activityProvider)
          .history
          .firstWhere((e) => e.retryOf == failed.id);
      expect(attempt.status, OperationStatus.succeeded);
      expect(ctrl.attemptNumber(attempt), 2);
      expect(ctrl.attemptNumber(orig), 1);
      // The retry attempt is never merged into the original failure.
      expect(
        c.read(activityProvider).history.where((e) => e.target == 'vm2'),
        hasLength(2),
      );
    });

    test('failed retry returns original to requiresAction', () async {
      final prefs = FakePreferencesRepository();
      final backend = FakeVirtualizationBackend();
      // No json response → envelope missing → runVmActionOrLegacy
      // falls back to runAction; make that fail too.
      backend.lastActionResult = const ProcResult(1, '', 'still broken');
      final c = _container(prefs, backend: backend);
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
          retrySpec: spec,
        ),
        throwsA(isA<AppFailure>()),
      );
      final failed = c.read(activityProvider).history.single;

      // retry() rethrows the ProcResult-less failure path — the
      // legacy ProcResult is returned, not thrown, so check state.
      final result = await ctrl.retry(failed);
      expect(result.exitCode, 1);
      final orig = c
          .read(activityProvider)
          .history
          .firstWhere((e) => e.id == failed.id);
      expect(orig.lifecycle, OperationLifecycle.requiresAction);
    });
  });

  group('activity filters (QG-014)', () {
    final now = DateTime.now();
    OperationHistoryEntry entry({
      OperationKind kind = OperationKind.start,
      String target = 'vm1',
      OperationStatus status = OperationStatus.failed,
      bool retryable = false,
      OperationLifecycle? lifecycle,
      Duration age = Duration.zero,
      String message = '',
      String? code,
    }) => OperationHistoryEntry(
      kind: kind,
      target: target,
      startedAt: now.subtract(age),
      completedAt: now.subtract(age),
      status: status,
      message: message,
      failureCode: code,
      retryable: retryable,
      lifecycle:
          lifecycle ??
          OperationLifecycle.forStatus(status, retryable: retryable),
    );

    test('matches by kind, target, status and free text', () {
      final e = entry(
        kind: OperationKind.snapshot,
        target: 'web-vm',
        message: 'disk full',
        code: 'LOW_SPACE',
      );
      expect(
        const ActivityFilter(kind: OperationKind.snapshot).matches(e, now),
        isTrue,
      );
      expect(
        const ActivityFilter(kind: OperationKind.clone).matches(e, now),
        isFalse,
      );
      expect(const ActivityFilter(target: 'web-vm').matches(e, now), isTrue);
      expect(const ActivityFilter(target: 'db-vm').matches(e, now), isFalse);
      expect(const ActivityFilter(query: 'disk full').matches(e, now), isTrue);
      expect(const ActivityFilter(query: 'low_space').matches(e, now), isTrue);
      expect(const ActivityFilter(query: 'network').matches(e, now), isFalse);
    });

    test('cancelled bucket groups cancelled and interrupted', () {
      expect(
        const ActivityFilter(status: OperationStatus.cancelled)
            .matches(entry(status: OperationStatus.interrupted), now),
        isTrue,
      );
      expect(
        const ActivityFilter(status: OperationStatus.failed)
            .matches(entry(status: OperationStatus.succeeded), now),
        isFalse,
      );
    });

    test('retryableOnly and requiresActionOnly', () {
      final retryable = entry(retryable: true);
      final plain = entry(status: OperationStatus.succeeded);
      expect(
        const ActivityFilter(retryableOnly: true).matches(retryable, now),
        isTrue,
      );
      expect(
        const ActivityFilter(retryableOnly: true).matches(plain, now),
        isFalse,
      );
      expect(
        const ActivityFilter(requiresActionOnly: true).matches(retryable, now),
        isTrue,
      );
      expect(
        const ActivityFilter(requiresActionOnly: true).matches(plain, now),
        isFalse,
      );
      // Acknowledged failures leave the requires-action bucket.
      final acked = entry(
        retryable: true,
        lifecycle: OperationLifecycle.acknowledged,
      );
      expect(
        const ActivityFilter(requiresActionOnly: true).matches(acked, now),
        isFalse,
      );
    });

    test('maxAge filters out older entries', () {
      final recent = entry(age: const Duration(minutes: 30));
      final old = entry(age: const Duration(days: 2));
      const filter = ActivityFilter(maxAge: Duration(hours: 1));
      expect(filter.matches(recent, now), isTrue);
      expect(filter.matches(old, now), isFalse);
    });

    test('isActive and json round-trip', () {
      const empty = ActivityFilter();
      expect(empty.isActive, isFalse);
      const filter = ActivityFilter(
        kind: OperationKind.snapshot,
        target: 'vm1',
        retryableOnly: true,
        requiresActionOnly: true,
        maxAge: Duration(hours: 24),
        query: 'oops',
      );
      expect(filter.isActive, isTrue);
      final decoded = ActivityFilter.fromJson(filter.toJson());
      expect(decoded.kind, OperationKind.snapshot);
      expect(decoded.target, 'vm1');
      expect(decoded.retryableOnly, isTrue);
      expect(decoded.requiresActionOnly, isTrue);
      expect(decoded.maxAge, const Duration(hours: 24));
      expect(decoded.query, 'oops');
    });
  });

  group('diagnostics (QG-015)', () {
    test('toDiagnosticLine carries stable metadata, no secrets', () {
      final entry = OperationHistoryEntry(
        id: 'op7',
        kind: OperationKind.start,
        target: 'vm1',
        startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        completedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        status: OperationStatus.failed,
        failureCode: 'BACKEND_TIMEOUT',
        retryable: true,
        retryOf: 'op3',
        backendOperationId: 'op-123',
        retrySpec: const RetrySpec(
          command: 'start',
          arguments: ['--vm', 'vm1.conf'],
          idempotent: true,
        ),
      );
      final line = entry.toDiagnosticLine();
      expect(line, contains('kind=start'));
      expect(line, contains('target=vm1'));
      expect(line, contains('code=BACKEND_TIMEOUT'));
      expect(line, contains('retryOf=op3'));
      expect(line, contains('backendOp=op-123'));
      // RetrySpec argv is intentionally absent — logical command only.
      expect(line, isNot(contains('vm1.conf')));
      expect(line, isNot(contains('password')));
    });
  });
}
