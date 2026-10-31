import 'automation_event.dart';

/// Per-step status of an automation run.
enum AutomationStepStatus { pending, running, done, failed }

class AutomationStep {
  AutomationStep({required this.id, required this.index});

  final String id;
  final int index;
  AutomationStepStatus status = AutomationStepStatus.pending;
  String message = '';
  String error = '';
}

/// Result of a single [[verify]] check.
class VerifyResult {
  const VerifyResult({
    required this.name,
    required this.pass,
    required this.rc,
    required this.output,
  });

  final String name;
  final bool pass;
  final int rc;
  final String output;
}

enum AutomationRunStatus { idle, running, completed, failed, cancelled }

/// View-model a `quickprovision run` JSONL stream is folded into — pure and
/// synchronous so tests drive it with recorded event files.
class AutomationRun {
  AutomationRun();

  String runId = '';
  String vmName = '';
  String profileName = '';
  String osName = '';
  String release = '';
  String provider = '';
  String confPath = '';
  String vmDir = '';
  String artifactsDir = '';
  int sshPort = 0;
  List<AutomationStep> steps = [];
  List<VerifyResult> results = [];
  AutomationRunStatus status = AutomationRunStatus.running;
  String error = '';
  String errorCode = '';
  double progress = 0;
  int fromStep = 0;
  bool resumed = false;
  bool reuse = false;

  bool get isTerminal =>
      status == AutomationRunStatus.completed ||
      status == AutomationRunStatus.failed ||
      status == AutomationRunStatus.cancelled;

  AutomationStep? get currentStep =>
      steps.where((s) => s.status == AutomationStepStatus.running).firstOrNull;

  int get passedChecks => results.where((r) => r.pass).length;

  /// Folds one event into the run state. Unknown events are ignored —
  /// the stream can grow new types without breaking older UIs.
  void apply(AutomationEvent e) {
    if (e.run.isNotEmpty) runId = e.run;
    if (e.vm.isNotEmpty) vmName = e.vm;
    final d = e.data;
    switch (e.type) {
      case AutomationEvent.runStarted:
        profileName = '${d['profile'] ?? ''}';
        osName = '${d['os'] ?? ''}';
        release = '${d['release'] ?? ''}';
        provider = '${d['provider'] ?? ''}';
        reuse = d['reuse'] == true;
        _initSteps(d['steps']);
      case AutomationEvent.runResumed:
        resumed = true;
        profileName = '${d['profile'] ?? profileName}';
        fromStep = d['fromStep'] is num ? (d['fromStep'] as num).toInt() : 0;
        _initSteps(d['steps']);
        for (var i = 0; i < fromStep && i < steps.length; i++) {
          steps[i].status = AutomationStepStatus.done;
        }
      case AutomationEvent.planResolved:
        confPath = '${d['conf'] ?? ''}';
        sshPort = d['sshPort'] is num ? (d['sshPort'] as num).toInt() : 0;
      case AutomationEvent.stepStarted:
        _markStep(d, AutomationStepStatus.running);
      case AutomationEvent.stepProgress:
        final s = _findStep(d);
        if (s != null) s.message = '${d['message'] ?? ''}';
      case AutomationEvent.stepCompleted:
        _markStep(d, AutomationStepStatus.done);
        if (d['progress'] is num) {
          progress = (d['progress'] as num).toDouble();
        }
      case AutomationEvent.stepFailed:
        _markStep(d, AutomationStepStatus.failed);
        final s = _findStep(d);
        if (s != null) s.error = '${d['error'] ?? ''}';
      case AutomationEvent.verifyResult:
        results.add(
          VerifyResult(
            name: '${d['name'] ?? ''}',
            pass: d['pass'] == true,
            rc: d['rc'] is num ? (d['rc'] as num).toInt() : -1,
            output: '${d['output'] ?? ''}',
          ),
        );
      case AutomationEvent.runCompleted:
        status = AutomationRunStatus.completed;
        progress = 1;
        vmName = '${d['vm'] ?? vmName}';
        vmDir = '${d['dir'] ?? vmDir}';
        artifactsDir = '${d['artifacts'] ?? ''}';
      case AutomationEvent.runFailed:
        errorCode = '${d['code'] ?? ''}';
        error = '${d['error'] ?? ''}';
        status = errorCode == 'CANCELLED'
            ? AutomationRunStatus.cancelled
            : AutomationRunStatus.failed;
    }
  }

  void _initSteps(Object? raw) {
    if (raw is! List) return;
    steps = [
      for (var i = 0; i < raw.length; i++)
        AutomationStep(id: '${raw[i]}', index: i + 1),
    ];
  }

  AutomationStep? _findStep(Map<String, dynamic> d) {
    final id = '${d['step'] ?? ''}';
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _markStep(Map<String, dynamic> d, AutomationStepStatus st) {
    final s = _findStep(d);
    if (s != null) s.status = st;
  }
}
