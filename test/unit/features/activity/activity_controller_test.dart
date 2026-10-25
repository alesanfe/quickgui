import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../../../support/fakes/fake_preferences_repository.dart';

ProviderContainer _container(FakePreferencesRepository prefs) =>
    ProviderContainer(
      overrides: [preferencesRepositoryProvider.overrideWithValue(prefs)],
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
        () async => throw const AppFailure(
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
      () async => ProcessResult(0, 3, '', 'boom'),
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
}
