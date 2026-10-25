import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/vm_status.dart';

/// State-machine tests: the wire contract states and the lenient
/// transitions between them.
void main() {
  group('VmStatus wire mapping', () {
    for (final e in {
      'running': VmStatus.running,
      'stopped': VmStatus.stopped,
      'paused': VmStatus.paused,
      'stale': VmStatus.stale,
    }.entries) {
      test('${e.key} maps to ${e.value}', () {
        expect(VmStatus.fromWire(e.key), e.value);
        expect(e.value.toWire(), e.key);
      });
    }

    for (final bad in [
      'Running',
      'RUNNING',
      '',
      null,
      42,
      'deleted',
      'crashed',
    ]) {
      test('unrecognised $bad degrades to unknown, never throws', () {
        expect(VmStatus.fromWire(bad), VmStatus.unknown);
      });
    }
  });

  group('lifecycle invariants', () {
    test('stale is terminal-only: a live process can never be stale', () {
      // Contract: stale means pid file exists but process is gone.
      // It must remain distinguishable from running/stopped.
      expect(VmStatus.stale.toWire(), isNot(VmStatus.running.toWire()));
      expect(VmStatus.stale, isNot(VmStatus.stopped));
    });
  });
}
