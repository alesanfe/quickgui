import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/automation/domain/automation_event.dart';
import 'package:quickgui/features/automation/domain/automation_run.dart';

void main() {
  group('AutomationEvent.parse', () {
    test('parses a full record', () {
      final e = AutomationEvent.parse(
        '{"seq":3,"ts":"2026-01-01T00:00:00Z","event":"step.started",'
        '"run":"r1","vm":"vm1","data":{"step":"launch","index":4,"total":9}}',
      )!;
      expect(e.seq, 3);
      expect(e.type, 'step.started');
      expect(e.run, 'r1');
      expect(e.vm, 'vm1');
      expect(e.data['step'], 'launch');
    });

    test('returns null for non-JSON and type-less records', () {
      expect(AutomationEvent.parse('not json'), isNull);
      expect(AutomationEvent.parse('{"a":1}'), isNull);
      expect(AutomationEvent.parse('[1,2]'), isNull);
      expect(AutomationEvent.parse('{"event":""}'), isNull);
    });

    test('tolerates null/missing data', () {
      final e = AutomationEvent.parse(
        '{"seq":1,"event":"run.completed","data":null}',
      )!;
      expect(e.data, isEmpty);
    });
  });

  group('AutomationRun', () {
    AutomationRun feed(List<String> lines) {
      final run = AutomationRun();
      for (final l in lines) {
        final e = AutomationEvent.parse(l);
        if (e != null) run.apply(e);
      }
      return run;
    }

    test('folds a full successful pipeline', () {
      final run = feed([
        '{"seq":1,"event":"run.started","run":"r1","data":{"profile":"p","os":"alpine-cloud","release":"v3.22","provider":"nocloud-image","steps":["resolve","acquire-image","prepare","launch","wait-ssh","provision","verify","shutdown","seal"]}}',
        '{"seq":2,"event":"step.started","run":"r1","data":{"step":"resolve","index":1,"total":9}}',
        '{"seq":3,"event":"step.completed","run":"r1","data":{"step":"resolve","index":1,"total":9,"progress":0.111}}',
        '{"seq":4,"event":"step.started","run":"r1","vm":"alpine-cloud-v3.22","data":{"step":"verify","index":7,"total":9}}',
        '{"seq":5,"event":"verify.result","run":"r1","data":{"name":"ssh-alive","pass":true,"rc":0,"output":""}}',
        '{"seq":6,"event":"verify.result","run":"r1","data":{"name":"hostname","pass":false,"rc":0,"output":"x"}}',
        '{"seq":7,"event":"step.completed","run":"r1","data":{"step":"verify","index":7,"total":9,"progress":0.777}}',
        '{"seq":8,"event":"run.completed","run":"r1","data":{"vm":"alpine-cloud-v3.22","dir":"/w/alpine-cloud-v3.22","artifacts":"/w/art"}}',
      ]);
      expect(run.runId, 'r1');
      expect(run.vmName, 'alpine-cloud-v3.22');
      expect(run.steps.length, 9);
      expect(run.steps[0].status, AutomationStepStatus.done);
      expect(run.steps[6].status, AutomationStepStatus.done);
      expect(run.results.length, 2);
      expect(run.passedChecks, 1);
      expect(run.status, AutomationRunStatus.completed);
      expect(run.progress, 1);
      expect(run.vmDir, '/w/alpine-cloud-v3.22');
      expect(run.isTerminal, isTrue);
    });

    test('marks failed step and run with code', () {
      final run = feed([
        '{"seq":1,"event":"run.started","run":"r2","data":{"steps":["resolve","launch"]}}',
        '{"seq":2,"event":"step.failed","run":"r2","data":{"step":"launch","error":"boom"}}',
        '{"seq":3,"event":"run.failed","run":"r2","data":{"error":"launch: boom","code":"STEP_FAILED"}}',
      ]);
      expect(run.steps[1].status, AutomationStepStatus.failed);
      expect(run.steps[1].error, 'boom');
      expect(run.status, AutomationRunStatus.failed);
      expect(run.errorCode, 'STEP_FAILED');
    });

    test('cancelled code maps to cancelled status', () {
      final run = feed([
        '{"seq":1,"event":"run.failed","run":"r3","data":{"error":"run cancelled","code":"CANCELLED"}}',
      ]);
      expect(run.status, AutomationRunStatus.cancelled);
    });

    test('resume pre-marks completed steps', () {
      final run = feed([
        '{"seq":10,"event":"run.resumed","run":"r4","data":{"profile":"p","fromStep":4,"steps":["a","b","c","d","e"]}}',
      ]);
      expect(run.resumed, isTrue);
      expect(
        run.steps.take(4).every((s) => s.status == AutomationStepStatus.done),
        isTrue,
      );
      expect(run.steps[4].status, AutomationStepStatus.pending);
    });
  });
}
