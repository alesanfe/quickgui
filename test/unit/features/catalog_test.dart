import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/catalog/application/load_catalog.dart';

import '../../support/fakes/fake_virtualization_backend.dart';

void main() {
  test('catalogue use case reports unavailable backend', () async {
    final backend = FakeVirtualizationBackend()..available = false;
    final result = await LoadCatalog(backend)();
    expect(
      (result as Err<List<List<String>>>).failure.code,
      'backend.unavailable',
    );
  });

  test('catalogue use case preserves raw wire rows', () async {
    final rows = [
      ['Ubuntu', 'ubuntu', '24.04', 'desktop', 'curl'],
    ];
    final backend = FakeVirtualizationBackend()..catalog = rows;
    final result = await LoadCatalog(backend)();
    expect((result as Ok<List<List<String>>>).value, rows);
  });

  test(
    'domain catalogue groups OS releases and options in wire order',
    () async {
      final backend = FakeVirtualizationBackend()
        ..catalog = [
          ['Ubuntu', 'ubuntu', '24.04', 'desktop', 'curl'],
          ['Ubuntu', 'ubuntu', '24.04', 'server', 'zsync'],
          ['Ubuntu', 'ubuntu', '22.04', 'desktop', 'curl'],
          ['Debian', 'debian', '12', 'netinst', 'curl'],
        ];
      final result = await loadOperatingSystems(backend);
      expect(result.map((os) => os.code), ['ubuntu', 'debian']);
      expect(result.map((os) => os.name), ['Ubuntu', 'Debian']);
      expect(result.first.versions.map((v) => v.version), ['24.04', '22.04']);
      expect(result.first.versions.first.options.map((o) => o.option), [
        'desktop',
        'server',
      ]);
      expect(result.first.versions.first.options.map((o) => o.downloader), [
        'curl',
        'zsync',
      ]);
    },
  );

  test(
    'legacy catalogue supplies curl when downloader column is missing',
    () async {
      final backend = FakeVirtualizationBackend()
        ..catalog = [
          ['Ubuntu', 'ubuntu', '24.04', 'desktop'],
        ];
      final result = await loadOperatingSystems(backend);
      expect(result.single.versions.single.options.single.downloader, 'curl');
    },
  );

  test('empty catalogue produces no phantom operating systems', () async {
    expect(await loadOperatingSystems(FakeVirtualizationBackend()), isEmpty);
  });
}
