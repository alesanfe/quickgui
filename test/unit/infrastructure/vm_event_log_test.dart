import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';

String ev(int seq, String type, {String vm = 'vm1', String? data}) =>
    '{"seq":$seq,"ts":"2026-01-01T00:00:0${seq}Z","event":"$type",'
    '"vm":"$vm","pid":42${data != null ? ',"data":$data' : ''}}';

void main() {
  late Directory dir;
  late File journal;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qg-events-');
    journal = File('${dir.path}/vm1.events.jsonl');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('replay', () {
    test('replays events with seq above the cursor (QG-023)', () async {
      journal.writeAsStringSync(
        '${ev(1, 'vm.started')}\n${ev(2, 'vm.paused')}\n'
        '${ev(3, 'vm.resumed')}\n',
      );
      final events = await VmEventLog(journal.path)
          .watch(sinceSeq: 1)
          .take(2)
          .toList();
      expect(events.map((e) => e.seq), [2, 3]);
      expect(events.first.type, 'vm.paused');
      expect(events.first.vm, 'vm1');
      expect(events.first.pid, 42);
      expect(events.first.ts, isNotNull);
    });

    test('parses data payload and skips corrupt lines', () async {
      journal.writeAsStringSync(
        'garbage line\n'
        '{"no":"seq"}\n'
        '${ev(1, 'vm.hotplug', data: '{"device":"usb","id":"1"}')}\n'
        '${ev(2, 'vm.stopped')}\n',
      );
      final events = await VmEventLog(journal.path).watch().take(2).toList();
      expect(events, hasLength(2));
      expect(events.first.data['device'], 'usb');
      expect(events.first.type, 'vm.hotplug');
      expect(events.first.changesState, isFalse);
      expect(events.last.changesState, isTrue);
    });

    test('lastSeq returns the highest seq for cursor persistence', () async {
      journal.writeAsStringSync('${ev(4, 'vm.started')}\n${ev(9, 'x')}\n');
      expect(await VmEventLog(journal.path).lastSeq(), 9);
      expect(await VmEventLog('${dir.path}/missing.jsonl').lastSeq(), 0);
    });
  });

  group('live tail', () {
    test('appended events stream in order', () async {
      journal.writeAsStringSync('${ev(1, 'vm.started')}\n');
      final log = VmEventLog(journal.path);
      final received = <VmEvent>[];
      final sub = log.watch().listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      journal.writeAsStringSync(
        '${ev(1, 'vm.started')}\n${ev(2, 'vm.paused')}\n'
        '${ev(3, 'vm.resumed')}\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        received.map((e) => e.seq).toList(),
        containsAllInOrder([1, 2, 3]),
      );
      // Seq 1 must not be emitted twice (replay + tail).
      expect(received.where((e) => e.seq == 1), hasLength(1));
    });

    test('a seq gap on the live tail emits VmEventGap', () async {
      journal.writeAsStringSync('${ev(1, 'vm.started')}\n');
      final received = <VmEvent>[];
      final sub = VmEventLog(journal.path).watch().listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // seq 2 lost (e.g. log rotated) — the gap must be surfaced.
      journal.writeAsStringSync(
        '${ev(1, 'vm.started')}\n${ev(5, 'vm.stopped')}\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received.whereType<VmEventGap>(), hasLength(1));
      expect(received.last.seq, 5);
    });

    test('journal truncation flags a gap and resyncs', () async {
      journal.writeAsStringSync(
        '${ev(1, 'vm.started')}\n${ev(2, 'vm.paused')}\n',
      );
      final received = <VmEvent>[];
      final sub = VmEventLog(journal.path).watch().listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      journal.writeAsStringSync('${ev(7, 'vm.started')}\n');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received.whereType<VmEventGap>(), isNotEmpty);
      expect(received.last.seq, 7);
    });

    test('utf-8 payloads keep byte offsets aligned', () async {
      journal.writeAsStringSync(
        '${ev(1, 'vm.note', data: '{"text":"está"')}\n',
      );
      final received = <VmEvent>[];
      final sub = VmEventLog(journal.path).watch().listen(received.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      journal.writeAsStringSync(
        '${ev(1, 'vm.note', data: '{"text":"está"')}\n'
        '${ev(2, 'vm.stopped')}\n',
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, hasLength(2));
      expect(received.last.seq, 2);
    });
  });
}
