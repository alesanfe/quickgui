import 'dart:convert';

/// One record of the `quickprovision run` JSONL event stream.
///
/// The engine emits a superset of these fields; unknown keys are kept
/// in [data] so the UI can grow with the stream. Records that are not
/// JSON objects (or carry no `event` type) parse to null — callers
/// treat them as free-form log lines.
class AutomationEvent {
  const AutomationEvent({
    required this.seq,
    required this.ts,
    required this.type,
    required this.run,
    required this.vm,
    required this.data,
  });

  final int seq;
  final String ts;
  final String type;
  final String run;
  final String vm;
  final Map<String, dynamic> data;

  // Lifecycle events the UI keys off — kept as constants so a typo in
  // a switch arm is a compile error, not a silent dead branch.
  static const runStarted = 'run.started';
  static const runResumed = 'run.resumed';
  static const planResolved = 'plan.resolved';
  static const stepStarted = 'step.started';
  static const stepProgress = 'step.progress';
  static const stepCompleted = 'step.completed';
  static const stepFailed = 'step.failed';
  static const provisionCommand = 'provision.command';
  static const verifyResult = 'verify.result';
  static const runCompleted = 'run.completed';
  static const runFailed = 'run.failed';

  static AutomationEvent? parse(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final type = decoded['event'];
    if (type is! String || type.isEmpty) return null;
    final data = decoded['data'];
    return AutomationEvent(
      seq: decoded['seq'] is num ? (decoded['seq'] as num).toInt() : 0,
      ts: '${decoded['ts'] ?? ''}',
      type: type,
      run: '${decoded['run'] ?? ''}',
      vm: '${decoded['vm'] ?? ''}',
      data: data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }

  /// Short single-line rendering for the on-page log tail.
  String describe() {
    final d = data;
    return switch (type) {
      runStarted =>
        'run ${d['profile'] ?? ''} — ${d['os']} ${d['release']}'
            '${d['reuse'] == true ? ' (reusing VM)' : ''}',
      runResumed => 'resumed from step ${d['fromStep']}',
      planResolved => 'conf: ${d['conf'] ?? ''}',
      stepStarted => '▶ ${d['step']}',
      stepProgress => '  ${d['message'] ?? ''}',
      stepCompleted => '✓ ${d['step']}',
      stepFailed => '✗ ${d['step']}: ${d['error'] ?? ''}',
      provisionCommand => 'cmd ${d['name']}: rc=${d['rc']}',
      verifyResult =>
        'check ${d['name']}: ${d['pass'] == true ? 'pass' : 'FAIL'}',
      runCompleted => 'completed — ${d['vm']}',
      runFailed => 'failed [${d['code']}] ${d['error']}',
      _ => type,
    };
  }
}
