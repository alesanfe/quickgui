import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

void main() {
  const store = VmConfigFileStore();
  late Directory directory;
  late String path;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('quickgui-config-');
    path = '${directory.path}/machine with spaces.conf';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('missing configuration has no value or raw content', () async {
    expect(store.read(path, 'ram'), isNull);
    expect(await store.loadRaw(path), isEmpty);
  });

  for (final value in [
    '4G',
    '',
    'a b',
    'máquina',
    r'$(touch injected)',
    r'C:\VMs\disk',
  ]) {
    test('write and read round trip preserves literal value $value', () {
      store.write(path, 'ram', value);
      expect(store.read(path, 'ram'), value);
      expect(File('${directory.path}/injected').existsSync(), isFalse);
    });
  }

  test('updating one key preserves unrelated settings and comments', () {
    File(
      path,
    ).writeAsStringSync('# existing configuration\nram="2G"\ncpu_cores="2"\n');
    store.write(path, 'ram', '8G');
    expect(
      File(path).readAsStringSync(),
      '# existing configuration\nram="8G"\ncpu_cores="2"\n',
    );
    expect(store.read(path, 'cpu_cores'), '2');
  });

  test('new keys append once and repeated writes are idempotent', () {
    store.write(path, 'ram', '4G');
    store.write(path, 'cpu_cores', '2');
    final original = File(path).readAsStringSync();
    store.write(path, 'cpu_cores', '2');
    expect(File(path).readAsStringSync(), original);
  });

  // write() mirrors read(): both honour the first occurrence of a key.
  // Replacing every duplicate would silently drop later entries.
  test('write replaces only the first of duplicated keys', () {
    File(path).writeAsStringSync('ram="1G"\nram="2G"\n');
    store.write(path, 'ram', '8G');
    expect(File(path).readAsStringSync(), 'ram="8G"\nram="2G"\n');
    expect(store.read(path, 'ram'), '8G');
  });

  test('read ignores comments, unquoted values and unrelated keys', () {
    File(path).writeAsStringSync('#ram="1G"\nram=2G\ncpu_cores="2"\n');
    expect(store.read(path, 'ram'), isNull);
    expect(store.read(path, 'cpu_cores'), '2');
  });

  test('raw save and load preserve Unicode and line endings', () async {
    const content = '# configuración\r\nram="4G"\r\n';
    await store.saveRaw(path, content);
    expect(await store.loadRaw(path), content);
  });

  test('raw save replaces old content', () async {
    await store.saveRaw(path, 'old');
    await store.saveRaw(path, 'new');
    expect(await store.loadRaw(path), 'new');
  });

  test(
    'save surfaces a missing parent rather than silently succeeding',
    () async {
      await expectLater(
        store.saveRaw('${directory.path}/absent/vm.conf', 'ram="4G"'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
  group('backups', () {
    test('listBackups returns rotated backups newest first', () async {
      await store.saveRaw(path, 'v1');
      await store.saveRaw(path, 'v2');
      await store.saveRaw(path, 'v3');
      final backups = VmConfigFileStore.listBackups(path);
      expect(backups, isNotEmpty);
      expect(backups.first.readAsStringSync(), 'v2');
    });

    test(
      'restoreBackup restores content and keeps current as backup',
      () async {
        await store.saveRaw(path, 'v1');
        await store.saveRaw(path, 'v2');
        final backup = VmConfigFileStore.listBackups(path).first;
        VmConfigFileStore.restoreBackup(path, backup.path);
        expect(await store.loadRaw(path), 'v1');
        // The restore itself backed up 'v2' first — undoable.
        final after = VmConfigFileStore.listBackups(path);
        expect(after.first.readAsStringSync(), 'v2');
      },
    );
  });
}
