import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

/// Security tests: hostile user input must be rejected or stored
/// literally — never interpreted, executed or allowed to escape
/// the working directory.
void main() {
  group('VM name validation rejects path traversal and shell metachars', () {
    for (final hostile in [
      '../etc/passwd',
      r'..\..\win',
      'a/b',
      r'a\b',
      r'$(rm -rf ~)',
      '`id`',
      'name;rm -rf /',
      'name && id',
      'name|sh',
      '.hidden',
      '-rf',
      ' ',
      'café',
      'vm vm', // Unicode whitespace
    ]) {
      test('rejects "$hostile"', () {
        expect(VmNameInput.dirty(hostile).isValid, isFalse);
      });
    }
  });

  group('config values are stored literally', () {
    const store = VmConfigFileStore();
    late Directory dir;
    late String conf;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('qe-sec-');
      conf = '${dir.path}/vm.conf';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    for (final payload in [
      r'$(touch injected)',
      '`touch injected`',
      '../../escape',
      '%s%n%n',
    ]) {
      test('payload $payload round-trips verbatim with no side effects', () {
        store.write(conf, 'ssh_port', payload);
        expect(store.read(conf, 'ssh_port'), payload);
        expect(File('${dir.path}/injected').existsSync(), isFalse);
        expect(File('${dir.parent.path}/injected').existsSync(), isFalse);
      });
    }

    test('quote payloads are escaped, never breaking the line', () {
      store.write(conf, 'ssh_port', 'x";touch injected;"');
      final raw = File(conf).readAsStringSync();
      expect(raw, 'ssh_port="x\\";touch injected;\\""\n');
      expect(File('${dir.path}/injected').existsSync(), isFalse);
    });

    test('a value cannot inject a second key', () {
      store.write(conf, 'ram', '4G"\ntpm="on');
      final raw = File(conf).readAsStringSync();
      // The value is sanitised: no raw newline may spawn a new key.
      expect(raw.contains('\ntpm='), isFalse);
      expect(raw.trim().split('\n').length, 1);
    });
  });
}
