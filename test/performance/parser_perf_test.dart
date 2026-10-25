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

  test('a single atomic write stays under 200ms', () {
    final sw = Stopwatch()..start();
    store.write(conf, 'key_0', 'new_0');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(200));
  });

  test('50 batched writes commit atomically under 200ms', () {
    // writeAll performs one read-modify-commit pass for the whole map —
    // the pattern callers use for multi-key edits — instead of paying the
    // temp+backup+rename cost per key.
    final sw = Stopwatch()..start();
    store.writeAll(conf, {for (var i = 0; i < 50; i++) 'key_$i': 'new_$i'});
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(200));
    expect(store.read(conf, 'key_49'), 'new_49');
  });
}
