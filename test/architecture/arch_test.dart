import 'dart:io';

import 'package:test/test.dart';

// Architecture contract enforced by filesystem scan: feature domains
// never import Flutter, application layers never import widgets, and
// presentation never touches the backend implementation.
Iterable<File> dartFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
}

Iterable<File> featureFiles(String layer) => [
  'catalog',
  'downloads',
  'machines',
  'diagnostics',
  'settings',
  'home',
].expand((f) => dartFiles('lib/features/$f/$layer'));

bool badImports(File f, Pattern p) => f.readAsStringSync().contains(p);

void main() {
  test('feature domains do not import flutter or dart:io', () {
    final bad = featureFiles('domain')
        .where(
          (f) => badImports(f, RegExp("import '(package:flutter|dart:io)")),
        )
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('feature application layers do not import flutter widgets', () {
    final bad = featureFiles('application')
        .where((f) => badImports(f, "import 'package:flutter/"))
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('presentation never imports the backend implementation', () {
    final bad = dartFiles('lib')
        .where((f) => f.path.contains('presentation'))
        .where((f) => badImports(f, 'quickemu_backend.dart'))
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });
}
