import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

/// Lightweight performance guardrails: config reads and form validation
/// must stay effectively instant for realistic workloads.
void main() {
  const store = VmConfigFileStore();
  late Directory dir;
  late String conf;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qe-perf-');
    conf = '${dir.path}/vm.conf';
    File(conf).writeAsStringSync(
      List.generate(200, (i) => 'key_$i="value_$i"').join('\n'),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('200-key conf reads stay under 500ms', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      store.read(conf, 'key_$i');
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  test('a single atomic write stays under 500ms', () {
    // Same guardrail as the batch case: temp+backup+rename must stay
    // effectively instant. min-of-5 filters scheduler preemption on shared
    // hosts without weakening the bound — a real regression (e.g. a
    // per-byte rewrite) shows up in every sample.
    store.write(conf, 'key_0', 'warmup'); // absorb first-write costs
    var best = 1 << 30;
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      store.write(conf, 'key_0', 'new_$i');
      sw.stop();
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    expect(best, lessThan(500));
  });

  test('50 batched writes commit atomically under 500ms', () {
    // writeAll performs one read-modify-commit pass for the whole map —
    // the pattern callers use for multi-key edits — instead of paying the
    // temp+backup+rename cost per key. The guardrail catches a regression
    // to the per-key path (~seconds for 50 keys), not scheduler jitter on
    // shared CI hosts.
    store.writeAll(conf, {'key_0': 'warmup'}); // absorb first-write costs
    final sw = Stopwatch()..start();
    store.writeAll(conf, {for (var i = 0; i < 50; i++) 'key_$i': 'new_$i'});
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(500));
    expect(store.read(conf, 'key_49'), 'new_49');
  });
}
