import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// Snapshot of the activity centre: in-flight operations plus the
/// persisted history of finished ones.
class ActivityState {
  const ActivityState({this.active = const [], this.history = const []});

  /// Currently running/cancelling operations, newest first.
  final List<AppOperation> active;

  /// Finished operations, newest first (bounded).
  final List<OperationHistoryEntry> history;

  int get runningCount =>
      active.where((o) => o.state.isBusy || o.state is OperationRunning).length;
}

/// Tracks long-running operations so the UI can show a global activity
/// centre instead of per-page dialogs.
///
/// Persistence: finished ops are appended (bounded) to
/// [prefActivityHistory]; in-flight op descriptors are mirrored to
/// [prefActiveOperations] so a crash/restart can mark them interrupted
/// instead of silently losing them.
class ActivityController extends Notifier<ActivityState> {
  static const _historyLimit = 100;

  var _seq = 0;

  @override
  ActivityState build() {
    unawaited(_restore());
    return const ActivityState();
  }

  Future<void> _restore() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    final historyRaw =
        await prefs.getAs<List<String>>(prefActivityHistory) ?? const [];
    final orphanedRaw =
        await prefs.getAs<List<String>>(prefActiveOperations) ?? const [];
    final history = <OperationHistoryEntry>[
      for (final raw in historyRaw) ?_decode(raw),
      // Operations that were still running when the app last exited can
      // never resume: their host process is gone or orphaned. Surface
      // them as interrupted so the user knows.
      for (final raw in orphanedRaw)
        if (_decode(raw) case final e?)
          OperationHistoryEntry(
            kind: e.kind,
            target: e.target,
            startedAt: e.startedAt,
            completedAt: e.completedAt,
            status: OperationStatus.interrupted,
            message: e.message,
          ),
    ]..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    await prefs.set(prefActiveOperations, const <String>[]);
    await prefs.set(prefActivityHistory, [
      for (final e in history.take(_historyLimit)) jsonEncode(e.toJson()),
    ]);
    if (!ref.mounted) return;
    state = ActivityState(
      active: state.active,
      history: [...state.history, ...history].take(_historyLimit).toList(),
    );
    unawaited(reconcile());
  }

  /// Re-checks interrupted history entries against the backend: an op
  /// whose result could not be confirmed at shutdown is promoted to
  /// `succeeded` when there is evidence (e.g. a `start` whose VM is now
  /// running, a `stop` whose VM is stopped). Entries without evidence
  /// stay `interrupted` — they are never silently marked failed.
  Future<void> reconcile() async {
    final pending = [
      for (final e in state.history)
        if (e.status == OperationStatus.interrupted) e,
    ];
    if (pending.isEmpty) return;
    final backend = ref.read(backendProvider);
    var changed = false;
    final history = [...state.history];
    for (final entry in pending) {
      try {
        // Definitive path: the backend async-operation registry knows
        // the real outcome for ops whose operationId we recorded.
        OperationStatus? resolved;
        final opId = entry.backendOperationId;
        if (opId != null) {
          final op = await backend.operationStatus(entry.target, opId);
          resolved = switch ('${op?['state']}') {
            'completed' || 'succeeded' => OperationStatus.succeeded,
            'failed' => OperationStatus.failed,
            'cancelled' => OperationStatus.cancelled,
            _ => null, // running/queued/unknown: keep interrupted
          };
        }
        if (resolved == null) {
          final vm = await backend.inspectVirtualMachine(entry.target);
          final vmState = '${vm['state']}';
          resolved = switch (entry.kind) {
            OperationKind.start when vmState == 'running' =>
              OperationStatus.succeeded,
            OperationKind.stop || OperationKind.delete
                when vmState == 'stopped' || vmState == 'missing' =>
              OperationStatus.succeeded,
            _ => null,
          };
        }
        if (resolved != null) {
          history[history.indexOf(entry)] = OperationHistoryEntry(
            id: entry.id,
            kind: entry.kind,
            target: entry.target,
            startedAt: entry.startedAt,
            completedAt: entry.completedAt,
            status: resolved,
            message: entry.message,
            failureCode: entry.failureCode,
            retryable: entry.retryable,
            retrySpec: entry.retrySpec,
            retryOf: entry.retryOf,
            backendOperationId: entry.backendOperationId,
          );
          changed = true;
        }
      } catch (_) {
        // Backend unavailable or VM gone: keep interrupted.
      }
    }
    if (!changed || !ref.mounted) return;
    state = ActivityState(active: state.active, history: history);
    unawaited(_persist());
  }

  OperationHistoryEntry? _decode(String raw) {
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? OperationHistoryEntry.fromJson(json)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Registers a new operation and returns it. [onCancel] is invoked by
  /// [cancel] — the owner decides how to stop its process.
  AppOperation start(
    OperationKind kind,
    String target, {
    Future<void> Function()? onCancel,
    RetrySpec? retrySpec,
    String? retryOf,
  }) {
    final op = AppOperation(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      kind: kind,
      target: target,
      startedAt: DateTime.now(),
      onCancel: onCancel,
      retrySpec: retrySpec,
      retryOf: retryOf,
    );
    state = ActivityState(
      active: [op, ...state.active],
      history: state.history,
    );
    unawaited(_persistActive());
    return op;
  }

  /// The action receives the registered operation so backends can
  /// attach late metadata (e.g. the envelope `meta.operationId`).
  Future<T> run<T>(
    OperationKind kind,
    String target,
    Future<T> Function(AppOperation operation) action, {
    RetrySpec? retrySpec,
    String? retryOf,
    Future<void> Function()? onCancel,
  }) async {
    final operation = start(
      kind,
      target,
      onCancel: onCancel,
      retrySpec: retrySpec,
      retryOf: retryOf,
    );
    // The op was registered in `queued` — mark it running now that the
    // work actually begins, so the UI never shows a stale queue state.
    update(operation, const OperationState.running());
    try {
      final result = await action(operation);
      if (result is ProcessResult) {
        final raw = '${result.stdout}\n${result.stderr}'.trim();
        final output = raw.length > 65536
            ? raw.substring(raw.length - 65536)
            : raw;
        update(
          operation,
          result.exitCode == 0
              ? const OperationState.succeeded(null)
              : OperationState.failed(
                  code: 'backend.exit_${result.exitCode}',
                  message: output,
                ),
          output: output,
        );
      } else {
        // Structured (runVmJson) results: reaching this point means the
        // envelope said success — failures always arrive as AppFailure.
        update(operation, const OperationState.succeeded(null));
      }
      return result;
    } on AppFailure catch (failure) {
      // Typed failures keep their stable code and retry policy instead
      // of being flattened into an opaque exception string. A user
      // cancellation is not a failure — record it as cancelled.
      update(
        operation,
        failure.kind == AppFailureKind.cancelled
            ? const OperationState.cancelled()
            : OperationState.failed(
                code: failure.code,
                message: failure.userMessage,
                retryable: failure.retryable,
              ),
      );
      rethrow;
    } catch (error) {
      update(
        operation,
        OperationState.failed(code: 'backend.exception', message: '$error'),
      );
      rethrow;
    }
  }

  /// Subscribes to the backend's push stream (`--op-watch`) so live
  /// ops update without polling op-list. Events carry the op state
  /// file; we map them onto the matching in-flight AppOperation.
  StreamSubscription<Map<String, dynamic>>? _watchSub;
  void startOperationWatch(String target) {
    ref.onDispose(() => _watchSub?.cancel());
    _watchSub ??= ref.read(backendProvider).watchOperations(target).listen((
      opState,
    ) {
      final opId = opState['operationId'];
      final progress = opState['progress'];
      final st = opState['state'];
      for (final op in state.active) {
        if (op.backendOperationId != opId) continue;
        if (st == 'completed' || st == 'failed' || st == 'cancelled') {
          update(op, switch (st) {
            'completed' => const OperationSucceeded<Object?>(null),
            'cancelled' => const OperationCancelled(),
            _ => OperationFailed(
              code: 'backend.op_failed',
              message: 'op failed: ${opState['error'] ?? 'unknown'}',
            ),
          });
        } else if (progress is num) {
          op.state = OperationRunning(progress: progress / 100);
        }
      }
    }, onError: (_) => _watchSub = null); // stream died: polling still works
  }

  /// Updates progress/state of an in-flight operation.
  void update(AppOperation op, OperationState<Object?> next, {String? output}) {
    if (op.isTerminal) return;
    op.state = next;
    if (output != null) op.output = output;
    if (next.isTerminal) {
      op.completedAt = DateTime.now();
      final status = switch (next) {
        OperationSucceeded() => OperationStatus.succeeded,
        OperationCancelled() => OperationStatus.cancelled,
        OperationFailed() => OperationStatus.failed,
        OperationInterrupted() => OperationStatus.interrupted,
        _ => OperationStatus.failed,
      };
      final message = switch (next) {
        OperationFailed(:final message) => message,
        _ => op.output,
      };
      state = ActivityState(
        active: state.active.where((o) => o.id != op.id).toList(),
        history: [
          OperationHistoryEntry(
            id: op.id,
            kind: op.kind,
            target: op.target,
            startedAt: op.startedAt,
            completedAt: op.completedAt!,
            status: status,
            message: message,
            failureCode: switch (next) {
              OperationFailed(:final code) => code,
              _ => null,
            },
            retryable: switch (next) {
              OperationFailed(:final retryable) => retryable,
              _ => false,
            },
            retrySpec: op.retrySpec,
            retryOf: op.retryOf,
            backendOperationId: op.backendOperationId,
          ),
          ...state.history,
        ].take(_historyLimit).toList(),
      );
      unawaited(_persist());
    } else {
      // New list instance so Riverpod notifies listeners.
      state = ActivityState(active: [...state.active], history: state.history);
    }
  }

  /// Records a short-lived backend action (start/stop/snapshot...) as a
  /// history entry directly — these do not need a live operation tile.
  void record(
    OperationKind kind,
    String target, {
    required bool success,
    String message = '',
    String? failureCode,
    bool retryable = false,
    RetrySpec? retrySpec,
    String? retryOf,
  }) {
    final now = DateTime.now();
    state = ActivityState(
      active: state.active,
      history: [
        OperationHistoryEntry(
          id: '${now.microsecondsSinceEpoch}-${_seq++}',
          kind: kind,
          target: target,
          startedAt: now,
          completedAt: now,
          status: success ? OperationStatus.succeeded : OperationStatus.failed,
          message: message,
          failureCode: failureCode,
          retryable: retryable,
          retrySpec: retrySpec,
          retryOf: retryOf,
        ),
        ...state.history,
      ].take(_historyLimit).toList(),
    );
    unawaited(_persist());
  }

  /// Marks an in-flight operation as interrupted — the outcome could
  /// not be confirmed (backend lost, process orphaned, app closing).
  /// Distinct from `failed`: reconciliation or a safe retry may still
  /// determine the real result.
  void markInterrupted(AppOperation op) {
    update(op, const OperationState.interrupted());
  }

  /// Re-dispatches a failed operation from its typed [RetrySpec],
  /// linking the new attempt to the original entry.
  ///
  /// Specs with `regeneratesPlan` are refused here — destructive
  /// retries must rebuild a fresh plan (e.g. `DeleteVm.plan`) and be
  /// confirmed again before a spec without `planId` can run.
  Future<ProcessResult> retry(OperationHistoryEntry entry) async {
    final spec = entry.retrySpec;
    if (spec == null || !entry.retryable || spec.regeneratesPlan) {
      throw StateError('${entry.kind.wire} ${entry.target} is not retryable');
    }
    return await run(
      entry.kind,
      entry.target,
      (op) => runVmActionOrLegacy(
        ref.read(backendProvider),
        spec.command,
        spec.arguments,
      ),
      retrySpec: spec,
      retryOf: entry.id,
    );
  }

  /// Removes a finished op from the active list without recording it.
  void dismiss(AppOperation op) {
    state = ActivityState(
      active: state.active.where((o) => o.id != op.id).toList(),
      history: state.history,
    );
    unawaited(_persistActive());
  }

  Future<void> cancel(AppOperation op) async {
    final onCancel = op.onCancel;
    if (onCancel == null || op.isTerminal) return;
    update(op, const OperationState.cancelling());
    await onCancel();
  }

  void clearHistory() {
    state = ActivityState(active: state.active);
    unawaited(_persist());
  }

  Future<void> _persist() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    await prefs.set(prefActivityHistory, [
      for (final e in state.history.take(_historyLimit)) jsonEncode(e.toJson()),
    ]);
    await _persistActive();
  }

  Future<void> _persistActive() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    final now = DateTime.now();
    await prefs.set(prefActiveOperations, [
      for (final o in state.active)
        jsonEncode(
          OperationHistoryEntry(
            kind: o.kind,
            target: o.target,
            startedAt: o.startedAt,
            completedAt: now,
            status: OperationStatus.interrupted,
          ).toJson(),
        ),
    ]);
  }
}

/// The activity centre state (active ops + bounded history).
final activityProvider = NotifierProvider<ActivityController, ActivityState>(
  ActivityController.new,
);

/// Convenience count of in-flight operations for the shell badge.
final runningOperationsProvider = Provider<int>(
  (ref) => ref.watch(activityProvider).runningCount,
);

/// History entries filtered to a single VM/entity target.
final Provider<List<OperationHistoryEntry>> Function(String)
activityForProvider = Provider.family<List<OperationHistoryEntry>, String>(
  (ref, target) => ref
      .watch(activityProvider)
      .history
      .where((e) => e.target == target)
      .toList(),
);
