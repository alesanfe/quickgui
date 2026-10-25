import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';
import 'package:quickgui/features/machines/domain/vm_status.dart';

/// Resilience tests: corrupt, partial or unexpected inputs degrade to
/// clean outcomes instead of crashes or silent corruption.
void main() {
  const store = VmConfigFileStore();
  late Directory dir;
  late String conf;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qe-resil-');
    conf = '${dir.path}/vm.conf';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a syntactically corrupt conf still loads without throwing', () async {
    File(conf)
        .writeAsStringSync('guest_os="linux"\n\x00\x01binary\nram="4G"\n\n');
    final raw = await store.loadRaw(conf);
    expect(raw, isNotEmpty);
    expect(store.read(conf, 'ram'), '4G');
  });

  test('truncated values do not break reads', () {
    File(conf).writeAsStringSync('ram="4G');
    expect(() => store.read(conf, 'ram'), returnsNormally);
  });

  test('a conf inside a symlinked directory stays in place', () {
    final link = Link('${dir.path}/link.conf');
    link.createSync(conf);
    store.write(link.path, 'ram', '8G');
    expect(File(conf).existsSync(), isTrue);
  });

  test('VmStatus tolerates garbage backend output', () {
    expect(VmStatus.fromWire('\x00\xffgarbage'), VmStatus.unknown);
    expect(VmStatus.fromWire('{"json":true}'), VmStatus.unknown);
  });
}
