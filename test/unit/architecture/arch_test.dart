import 'dart:io';

import 'package:test/test.dart';

// Architecture contract enforced by filesystem scan: domain never
// imports Flutter, presentation never spawns processes, and only
// infrastructure/ knows the backend implementation.
Iterable<File> dartFiles(String dir) =>
    Directory('lib/$dir')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

void main() {
  test('domain does not import flutter or dart:io', () {
    final bad = dartFiles('domain')
        .where(
          (f) => f.readAsStringSync().contains(
            RegExp("import '(package:flutter|dart:io)"),
          ),
        )
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('application does not import flutter widgets', () {
    final bad = dartFiles('application')
        .where((f) => f.readAsStringSync().contains("import 'package:flutter/"))
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('presentation never imports the backend implementation', () {
    final bad = dartFiles('presentation')
        .where((f) => f.readAsStringSync().contains('quickemu_backend.dart'))
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });
}
