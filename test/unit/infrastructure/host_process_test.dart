import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/process/host_platform.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';

void main() {
  test(
    'process start preserves arguments without repeating the executable',
    () async {
      final process = await SystemProcessRunner().start('sh', [
        '-c',
        r'printf "%s" "$1"',
        'fixture',
        'literal value ; not a command',
      ]);
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      expect(await process.exitCode, 0, reason: await stderr);
      expect(await stdout, 'literal value ; not a command');
    },
  );

  test('process runner propagates exit code stdout and stderr', () async {
    final result = await SystemProcessRunner().run('sh', [
      '-c',
      'printf output; printf error >&2; exit 7',
    ]);
    expect(result.exitCode, 7);
    expect(result.stdout, 'output');
    expect(result.stderr, 'error');
  });

  group('writable directory probe', () {
    late Directory directory;
    setUp(
      () => directory = Directory.systemTemp.createTempSync('quickgui-probe-'),
    );
    tearDown(() => directory.deleteSync(recursive: true));

    test(
      'does not overwrite or delete an existing file with the old probe name',
      () {
        final existing = File('${directory.path}/.quickgui_write_test')
          ..writeAsStringSync('user content');
        expect(isWritableDirectory(directory.path), isTrue);
        expect(existing.existsSync(), isTrue);
        expect(existing.readAsStringSync(), 'user content');
        expect(directory.listSync().map((entry) => entry.path), [
          existing.path,
        ]);
      },
    );
    test('leaves no probe artifacts after repeated checks', () {
      expect(isWritableDirectory(directory.path), isTrue);
      expect(isWritableDirectory(directory.path), isTrue);
      expect(directory.listSync(), isEmpty);
    });
    test('returns false for a missing directory without creating it', () {
      final missing = '${directory.path}/missing';
      expect(isWritableDirectory(missing), isFalse);
      expect(Directory(missing).existsSync(), isFalse);
    });
    test('returns false when the path is a regular file', () {
      final file = File('${directory.path}/file')..writeAsStringSync('content');
      expect(isWritableDirectory(file.path), isFalse);
      expect(file.readAsStringSync(), 'content');
    });
  });
}
