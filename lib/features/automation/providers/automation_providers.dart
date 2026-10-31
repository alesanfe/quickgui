import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/automation/application/ports/automation_backend.dart';
import 'package:quickgui/features/automation/domain/automation_event.dart';
import 'package:quickgui/features/automation/domain/automation_profile.dart';
import 'package:quickgui/features/automation/domain/automation_run.dart';
import 'package:quickgui/features/automation/infrastructure/quickprovision_backend.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// The automation engine backend (`quickprovision` CLI adapter).
final automationBackendProvider = Provider<AutomationBackend>(
  (ref) => QuickprovisionBackend(SystemProcessRunner()),
);

/// `quickprovision` availability on PATH — null while probing.
final automationAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(automationBackendProvider).checkAvailability(),
);

/// UI-facing state of the automation feature: the last plan preview
/// plus the live/finished run the event stream produced.
class AutomationUiState {
  const AutomationUiState({
    this.plan,
    this.profilePath,
    this.run,
    this.log = const [],
    this.busy = false,
  });

  /// Envelope `data` from `quickprovision plan` — steps/provider/warnings.
  final Map<String, dynamic>? plan;

  /// Where the generated TOML profile was written.
  final String? profilePath;

  /// Folded event-stream state — null until the first run.
  final AutomationRun? run;

  /// Described event lines, newest last (bounded tail).
  final List<String> log;

  /// A blocking request (plan/write) is in flight.
  final bool busy;

  AutomationUiState copyWith({
    Map<String, dynamic>? Function()? plan,
    String? profilePath,
    AutomationRun? run,
    List<String>? log,
    bool? busy,
  }) => AutomationUiState(
    plan: plan != null ? plan() : this.plan,
    profilePath: profilePath ?? this.profilePath,
    run: run ?? this.run,
    log: log ?? this.log,
    busy: busy ?? this.busy,
  );
}

/// Drives quickprovision runs: profile → TOML file → process → folded
/// [AutomationRun], mirrored into the activity centre as one
/// [OperationKind.automation] operation.
class AutomationController extends Notifier<AutomationUiState> {
  static const _logLimit = 200;

  RunningProc? _proc;
  AppOperation? _op;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  @override
  AutomationUiState build() {
    ref.onDispose(() {
      unawaited(_stdoutSub?.cancel());
      unawaited(_stderrSub?.cancel());
    });
    return const AutomationUiState();
  }

  /// Writes [profile] as TOML under `<workDir>/automation-profiles/`
  /// and returns the file path (also stored in state).
  Future<String> writeProfile(AutomationProfile profile, String workDir) async {
    final dir = Directory(p.join(workDir, 'automation-profiles'));
    await dir.create(recursive: true);
    final path = p.join(dir.path, '${profile.slug}.toml');
    await File(path).writeAsString(profile.toToml());
    state = state.copyWith(profilePath: path);
    return path;
  }

  /// `quickprovision plan` preview — resolves steps/provider/warnings
  /// without starting anything.
  Future<Map<String, dynamic>?> previewPlan(
    AutomationProfile profile,
    String workDir,
  ) async {
    state = state.copyWith(busy: true);
    try {
      final path = await writeProfile(profile, workDir);
      final plan = await ref.read(automationBackendProvider).plan(path);
      state = state.copyWith(plan: () => plan);
      return plan;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Starts a fresh run of [profile]. Events fold into the state's
  /// run; the activity centre op mirrors progress and cancellation.
  Future<void> start(AutomationProfile profile, String workDir) async {
    final path = await writeProfile(profile, workDir);
    final run = AutomationRun();
    state = AutomationUiState(plan: state.plan, profilePath: path, run: run);
    final backend = ref.read(automationBackendProvider);
    _op = ref
        .read(activityProvider.notifier)
        .start(
          OperationKind.automation,
          profile.name.isNotEmpty ? profile.name : profile.slug,
          onCancel: cancelRun,
        );
    _proc = await backend.startRun(path, workDir);
    _wire(_proc!, run, workDir);
  }

  /// Resumes the newest unfinished run under the current VM dir —
  /// the engine re-enters at the first incomplete step.
  Future<void> resume() async {
    final run = state.run;
    final vmDir = _vmDir(run);
    if (run == null || vmDir == null) return;
    final backend = ref.read(automationBackendProvider);
    _op = ref
        .read(activityProvider.notifier)
        .start(
          OperationKind.automation,
          run.profileName.isNotEmpty ? run.profileName : run.vmName,
          onCancel: cancelRun,
        );
    _proc = await backend.resumeRun(vmDir);
    run.status = AutomationRunStatus.running;
    _wire(_proc!, run, _workDirOf(vmDir));
  }

  /// Journal-level cancel: flags the run's op entry so the runner
  /// aborts at the next step boundary and tears down its own QEMU.
  /// Falls back to killing the quickprovision process when the journal
  /// entry cannot be located yet (run still pre-launch).
  Future<void> cancelRun() async {
    final run = state.run;
    final proc = _proc;
    if (run == null || run.isTerminal) return;
    var cancelled = false;
    final vmDir = _vmDir(run);
    if (vmDir != null) {
      try {
        final vm = run.vmName;
        if (vm.isNotEmpty) {
          final ops = await ref.read(backendProvider).listOperations(vm);
          for (final op in ops.reversed) {
            if ('${op['type']}' == 'quickprovision' &&
                '${op['state']}' != 'completed') {
              await ref
                  .read(backendProvider)
                  .cancelOperation(vm, '${op['operationId'] ?? op['id']}');
              cancelled = true;
              break;
            }
          }
        }
        if (!cancelled) {
          final opsDir = Directory(p.join(vmDir, 'ops'));
          if (opsDir.existsSync()) {
            final files =
                opsDir
                    .listSync()
                    .whereType<File>()
                    .where((f) => f.path.endsWith('.json'))
                    .toList()
                  ..sort(
                    (a, b) =>
                        b.lastModifiedSync().compareTo(a.lastModifiedSync()),
                  );
            for (final f in files) {
              final decoded = jsonDecode(f.readAsStringSync());
              if (decoded is Map && '${decoded['type']}' == 'quickprovision') {
                final id = p.basenameWithoutExtension(f.path);
                final r = await ref
                    .read(automationBackendProvider)
                    .cancel(vmDir, id);
                cancelled = r.exitCode == 0;
                break;
              }
            }
          }
        }
      } catch (e, st) {
        AppLog.backendContract.info(
          'automation cancel: journal path failed ($e)\n$st',
        );
      }
    }
    if (!cancelled) proc?.kill();
  }

  /// Clears the run view back to the profile form.
  void reset() => state = const AutomationUiState();

  /// The VM's runtime dir (holds `.quickprovision/` and `ops/`): derived
  /// from the emitted conf path — flat layout puts the conf next to
  /// the workdir root, nested inside `<vm>/<vm>.conf`.
  String? _vmDir(AutomationRun? run) {
    if (run == null) return null;
    if (run.vmDir.isNotEmpty) return run.vmDir;
    if (run.confPath.isEmpty || run.vmName.isEmpty) return null;
    final dir = p.dirname(run.confPath);
    return p.basename(dir) == run.vmName ? dir : p.join(dir, run.vmName);
  }

  String _workDirOf(String vmDir) => p.dirname(vmDir);

  void _wire(RunningProc proc, AutomationRun run, String workDir) {
    final outLines = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    _stdoutSub = outLines.listen((line) {
      final ev = AutomationEvent.parse(line.trim());
      if (ev == null) {
        _log('… $line');
        return;
      }
      run.apply(ev);
      _log(ev.describe());
      if (ev.type == AutomationEvent.runCompleted && _op != null) {
        _finish(const OperationState.succeeded(null));
      } else if (ev.type == AutomationEvent.runFailed && _op != null) {
        _finish(
          run.status == AutomationRunStatus.cancelled
              ? const OperationState.cancelled()
              : OperationState.failed(
                  code: 'quickprovision.${run.errorCode.toLowerCase()}',
                  message: run.error,
                ),
        );
      } else {
        _tick(run);
      }
    });
    _stderrSub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('! $line'));
    unawaited(
      proc.exitCode.then((code) {
        if (!run.isTerminal) {
          run.error = 'quickprovision exited (rc=$code) before finishing';
          run.errorCode = 'EXIT_$code';
          run.status = AutomationRunStatus.failed;
          _log(run.error);
        }
        final op = _op;
        if (run.isTerminal && op != null && !op.isTerminal) {
          _finish(
            run.status == AutomationRunStatus.completed && code == 0
                ? const OperationState.succeeded(null)
                : run.status == AutomationRunStatus.cancelled
                ? const OperationState.cancelled()
                : OperationState.failed(
                    code: 'quickprovision.${run.errorCode.toLowerCase()}',
                    message: run.error,
                  ),
          );
        }
      }),
    );
  }

  void _tick(AutomationRun run) {
    final op = _op;
    if (op == null || op.isTerminal) return;
    final step = run.currentStep;
    ref
        .read(activityProvider.notifier)
        .update(
          op,
          OperationState.running(
            progress: run.progress,
            line: step == null ? null : '${step.id} (${step.index})',
          ),
        );
    state = state.copyWith(run: run, log: [...state.log]);
  }

  void _finish(OperationState<Object?> next) {
    final op = _op;
    if (op == null || op.isTerminal) return;
    ref.read(activityProvider.notifier).update(op, next);
    _op = null;
    state = state.copyWith(run: state.run, log: [...state.log]);
  }

  void _log(String line) {
    final log = [...state.log, line];
    state = state.copyWith(
      log: log.length > _logLimit ? log.sublist(log.length - _logLimit) : log,
    );
  }
}

/// The automation page's controller — survives navigation so an
/// in-flight run is still visible when the user comes back.
final automationControllerProvider =
    NotifierProvider<AutomationController, AutomationUiState>(
      AutomationController.new,
    );

/// Working directory where generated profiles and VMs live — the same
/// pref the rest of the app uses, defaulting to the process cwd.
final automationWorkDirProvider = FutureProvider<String>((ref) async {
  final prefs = ref.read(preferencesRepositoryProvider);
  return await prefs.getAs<String>(prefWorkingDirectory) ??
      Directory.current.path;
});
