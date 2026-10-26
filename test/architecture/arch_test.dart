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

  /// Only the process/executor layer may spawn processes, and only the
  /// tracked backend may invoke the legacy text path — new call sites
  /// for `Process.run`/`Process.start`/`runAction` elsewhere are a bug.
  test('no direct process spawns or raw runAction outside the boundary', () {
    const allowedProcess = {
      'host_process.dart',
      'system_process_runner.dart',
      'quickemu_process.dart',
      'system_host_probe.dart',
      'import_image.dart',
    };
    const allowedRunAction = {
      'structured_or_legacy.dart',
      'tracked_backend_provider.dart',
      // delete_vm.plan() keeps a legacy text fallback because the
      // pre-contract --delete-plan output is line-oriented plan data.
      'delete_vm.dart',
    };
    final bad = dartFiles('lib')
        .where(
          (f) =>
              (badImports(f, RegExp(r'Process\.(run|start)\(')) &&
                  !allowedProcess.any((a) => f.path.endsWith(a))) ||
              (badImports(f, '.runAction(') &&
                  !allowedRunAction.any((a) => f.path.endsWith(a))),
        )
        .map((f) => f.path)
        .toList();
    expect(bad, isEmpty, reason: bad.join(', '));
  });
}
