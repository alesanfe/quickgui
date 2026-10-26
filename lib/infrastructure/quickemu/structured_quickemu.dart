import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_process.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_response.dart';

/// Single structured execution path for `quickemu --format json` commands.
///
/// Every caller gets the same treatment: `--format json` is appended
/// automatically, the process is bounded by a timeout, spawn errors and
/// signal termination become typed [AppFailure]s, the response envelope
/// is parsed via [QuickemuResponse.parse] and the exit code is checked
/// for coherence against `success`.
///
/// stdout/stderr/exitCode stay separate in the returned/thrown values —
/// nothing human-readable is ever mixed into stdout parsing.
class StructuredQuickemu {
  const StructuredQuickemu(
    this._process, {
    this.timeout,
    this.maxStdoutBytes = 4 * 1024 * 1024,
  });

  final QuickemuProcess _process;

  /// Default bound for a structured call; long-running commands must
  /// pass an explicit [timeout] per call, or an instance-wide default
  /// at construction; otherwise [timeoutFor] picks by command.
  final Duration? timeout;

  /// Per-category default timeout for [command]. Short for state
  /// queries, medium for bounded actions, long for disk-hungry work.
  /// An explicit `timeout:` argument always wins.
  static Duration timeoutFor(String command) {
    const short = {
      'status',
      'capabilities',
      'list-vms',
      'pause',
      'resume',
      'reset',
      'send-keys',
      'monitor-cmd',
      'powerdown',
      'kill',
      'start',
      'stop',
    };
    const medium = {
      'doctor',
      'screenshot',
      'delete-plan',
      'snapshot-list',
      'snapshot-create',
      'snapshot-apply',
      'snapshot-delete',
      'shutdown',
    };
    if (short.contains(command)) return const Duration(seconds: 30);
    if (medium.contains(command)) return const Duration(minutes: 2);
    // Long: clone, disk-resize, compact, import, export, backup and any
    // unknown command — disk-hungry operations must not be cut early.
    return const Duration(minutes: 10);
  }

  /// Safety cap for captured stdout — a malformed or hostile backend
  /// cannot exhaust memory through an unbounded response.
  final int maxStdoutBytes;

  /// Runs `quickemu [arguments] --format json` and returns the parsed
  /// envelope.
  ///
  /// [command] is the logical command name the envelope must declare.
  /// Throws [AppFailure] on every failure path — process spawn, timeout,
  /// cancellation, malformed envelope, incoherent exit code, or
  /// `success: false` (converted via [QuickemuResponse.toFailure]).
  Future<QuickemuResponse> run(
    String command,
    List<String> arguments, {
    String? vm,
    String? operation,
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(Process process)? onStarted,
  }) async {
    if (cancelSignal != null || onStarted != null) {
      // Live-process path: keeps a handle so the caller can observe or
      // terminate it. Streams are drained with a byte bound.
      return await _runCancellable(
        command,
        arguments,
        vm: vm,
        operation: operation,
        timeout: timeout,
        cancelSignal: cancelSignal,
        onStarted: onStarted,
      );
    }
    final ProcessResult result;
    try {
      result = await _process
          .quickemu([...arguments, ...formatJsonArgs])
          .timeout(timeout ?? this.timeout ?? timeoutFor(command));
    } on TimeoutException {
      throw AppFailure(
        AppFailureKind.timeout,
        'BACKEND_TIMEOUT',
        'The backend did not answer in time.',
        technical:
            'command=$command args=${_redact(arguments)} '
            'timeout=${(timeout ?? this.timeout ?? timeoutFor(command)).inSeconds}s',
        vm: vm,
        operation: operation,
        retryable: true,
        suggestion:
            'Check whether the VM or the host is overloaded and '
            'retry.',
      );
    } on ProcessException catch (e) {
      throw AppFailure(
        AppFailureKind.dependencyMissing,
        'SPAWN_FAILED',
        'The quickemu executable could not be started.',
        technical: 'command=$command error=${e.message}',
        vm: vm,
        operation: operation,
        suggestion: 'Verify that quickemu is installed and executable.',
        cause: e,
      );
    }
    return resolve(command, result, vm: vm, operation: operation);
  }

  /// Live-process path used when the caller needs cancellation or the
  /// process handle. Drains stdout/stderr with the same byte bound,
  /// terminates gracefully first and escalates to a hard kill when the
  /// process ignores it.
  Future<QuickemuResponse> _runCancellable(
    String command,
    List<String> arguments, {
    String? vm,
    String? operation,
    Duration? timeout,
    Future<void>? cancelSignal,
    void Function(Process process)? onStarted,
  }) async {
    final effective = timeout ?? this.timeout ?? timeoutFor(command);
    final Process process;
    try {
      process = await _process.startQuickemu([...arguments, ...formatJsonArgs]);
    } on ProcessException catch (e) {
      throw AppFailure(
        AppFailureKind.dependencyMissing,
        'SPAWN_FAILED',
        'The quickemu executable could not be started.',
        technical: 'command=$command error=${e.message}',
        vm: vm,
        operation: operation,
        suggestion: 'Verify that quickemu is installed and executable.',
        cause: e,
      );
    }
    onStarted?.call(process);

    final out = StringBuffer();
    final err = StringBuffer();
    final outDone = process.stdout
        .transform(utf8.decoder)
        .listen((s) {
          if (out.length < maxStdoutBytes) out.write(s);
        })
        .asFuture<void>()
        .catchError((_) => null);
    final errDone = process.stderr
        .transform(utf8.decoder)
        .listen((s) {
          if (err.length < maxStdoutBytes) err.write(s);
        })
        .asFuture<void>()
        .catchError((_) => null);

    final outcome = await Future.any<int>([
      process.exitCode,
      Future<int>.delayed(effective, () => -3),
      if (cancelSignal != null) cancelSignal.then((_) => -2),
    ]);

    if (outcome == -2 || outcome == -3) {
      // Graceful SIGTERM first, escalated to SIGKILL after 3s.
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.catchError((_) => -1);
      }
      await Future.wait([outDone, errDone]);
      if (outcome == -2) {
        throw AppFailure(
          AppFailureKind.cancelled,
          'CANCELLED',
          'The operation was cancelled by the user.',
          technical: 'command=$command args=${_redact(arguments)}',
          vm: vm,
          operation: operation,
        );
      }
      throw AppFailure(
        AppFailureKind.timeout,
        'BACKEND_TIMEOUT',
        'The backend did not answer in time.',
        technical:
            'command=$command args=${_redact(arguments)} '
            'timeout=${effective.inSeconds}s',
        vm: vm,
        operation: operation,
        retryable: true,
      );
    }

    await Future.wait([outDone, errDone]);
    return resolve(
      command,
      ProcessResult(process.pid, outcome, out.toString(), err.toString()),
      vm: vm,
      operation: operation,
    );
  }

  /// Parses and validates a completed process result. Exposed so callers
  /// that already ran the process (legacy paths, tests) reuse the same
  /// coherence rules.
  QuickemuResponse resolve(
    String command,
    ProcessResult result, {
    String? vm,
    String? operation,
  }) {
    final stdout = '${result.stdout}';
    final stderr = '${result.stderr}';
    final exitCode = result.exitCode;
    // An over-limit envelope would be truncated mid-JSON — surface the
    // real cause instead of a misleading MALFORMED_JSON.
    if (stdout.length > maxStdoutBytes) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'BACKEND_OUTPUT_TOO_LARGE',
        'The backend returned more output than the supported limit.',
        technical:
            'command=$command stdoutBytes=${stdout.length} '
            'limit=$maxStdoutBytes',
        vm: vm,
        operation: operation,
      );
    }

    QuickemuResponse response;
    try {
      response = QuickemuResponse.parse(
        stdout,
        command: command,
        exitCode: exitCode,
        stderr: stderr,
      );
    } on AppFailure catch (e) {
      // Envelope unreadable. With a non-zero exit and a human-readable
      // stderr the backend still reported *something* — surface it as a
      // typed failure instead of a bare contract error.
      if (exitCode != 0 && stderr.trim().isNotEmpty) {
        throw AppFailure(
          AppFailureKind.internal,
          'COMMAND_FAILED',
          'The backend command failed.',
          technical: 'command=$command exit=$exitCode stderr=${_clip(stderr)}',
          vm: vm,
          operation: operation,
          exitCode: exitCode,
          cause: e,
        );
      }
      rethrow;
    }

    if (!_commandMatches(command, response.command)) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'COMMAND_MISMATCH',
        'The backend answered a different command than requested.',
        technical: 'expected=$command got=${response.command} exit=$exitCode',
        vm: vm,
        operation: operation,
      );
    }

    // Coherence: a successful envelope with a failing exit code is
    // contradictory — distrust both and report a contract failure.
    if (response.success && exitCode != 0) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'INCOHERENT_RESPONSE',
        'The backend reported success but exited with an error code.',
        technical: 'command=$command exit=$exitCode stderr=${_clip(stderr)}',
        vm: vm,
        operation: operation,
        exitCode: exitCode,
      );
    }
    if (!response.success) {
      // Envelope failure wins over exit-code shape; success:false with
      // exit 0 is still a failure with structured errors attached.
      final failure = response.toFailure(vm: vm, operation: operation);
      throw AppFailure(
        failure.kind,
        failure.code,
        failure.userMessage,
        technical: failure.technical ?? 'stderr=${_clip(stderr)}',
        vm: failure.vm,
        operation: failure.operation,
        phase: failure.phase,
        exitCode: exitCode,
        retryable: failure.retryable,
        partialChanges: failure.partialChanges,
        suggestion: failure.suggestion,
        cause: failure.cause,
      );
    }
    if (response.warnings.isNotEmpty) {
      AppLog.backendContract.info(
        'command=$command warnings='
        '${response.warnings.map((w) => w.code).join(',')}',
      );
    }
    return response;
  }

  /// True when the failure means the backend does not speak the
  /// structured envelope at all — callers may fall back to legacy
  /// parsing without masking real contract defects.
  /// The real backend emits namespaced command names (`vm.status`,
  /// `vm.snapshot.list`) and past-tense names for lifecycle verbs
  /// (`vm.started`, `vm.paused`). Both spellings denote the same command —
  /// normalize before comparing so a pre-contract caller name like
  /// `status` still validates against `vm.status`.
  static bool _commandMatches(String expected, String actual) {
    if (expected == actual) return true;
    String norm(String c) => c.replaceFirst(RegExp(r'^(vm|host)\.'), '');
    final e = norm(expected);
    final a = norm(actual);
    if (e == a) return true;
    const aliases = {
      'start': {'started'},
      'stop': {'stopped'},
      'kill': {'stopped'},
      'powerdown': {'stopped'},
      'pause': {'paused'},
      'resume': {'resumed'},
      'clone': {'cloned'},
      'delete-vm': {'trashed', 'delete'},
      'delete-disk': {'trashed', 'delete'},
      'delete-plan': {'plan', 'delete-plan'},
      'execution-plan': {'plan'},
      'snapshot-list': {'snapshot.list'},
      'snapshot-create': {'snapshot.created'},
      'snapshot-apply': {'snapshot.applied', 'restored'},
      'snapshot-delete': {'snapshot.deleted'},
      'list-vms': {'list'},
    };
    return aliases[e]?.contains(a) ?? false;
  }

  static bool isLegacyBackend(AppFailure failure) =>
      failure.kind == AppFailureKind.backendContract &&
      {
        'EMPTY_RESPONSE',
        'MALFORMED_JSON',
        'UNEXPECTED_SHAPE',
        'MISSING_SCHEMA_VERSION',
      }.contains(failure.code);

  static String _clip(String s) =>
      s.length > 2000 ? '${s.substring(0, 2000)}…' : s;

  /// Args are logged for diagnostics; values that look like secrets
  /// (tokens, passwords, keys) are replaced before they reach a log.
  static String _redact(List<String> args) => args
      .map(
        (a) => RegExp('pass|token|secret|key', caseSensitive: false).hasMatch(a)
            ? '<redacted>'
            : a,
      )
      .join(' ');
}
