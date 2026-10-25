import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

void main() {
  late Directory dir;
  late String conf;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qg-atomic-');
    conf = '${dir.path}/vm.conf';
    File(conf).writeAsStringSync('guest_os="linux"\nram="4G"\n');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const store = VmConfigFileStore();

  test('write replaces a key and leaves no temp file behind', () {
    store.write(conf, 'ram', '8G');
    expect(File(conf).readAsStringSync(), contains('ram="8G"'));
    expect(
      dir.listSync().where((f) => f.path.endsWith('.quickgui-tmp')),
      isEmpty,
    );
  });

  test('write appends an unknown key without touching others', () {
    store.write(conf, 'tpm', 'on');
    final content = File(conf).readAsStringSync();
    expect(content, contains('guest_os="linux"'));
    expect(content, contains('tpm="on"'));
  });

  test('saveRaw is atomic and keeps a backup of the previous content', () async {
    await store.saveRaw(conf, 'guest_os="linux"\nram="16G"\n');
    expect(File('$conf.bak').readAsStringSync(), contains('ram="4G"'));
    expect(File(conf).readAsStringSync(), contains('ram="16G"'));
    expect(
      dir.listSync().where((f) => f.path.endsWith('.quickgui-tmp')),
      isEmpty,
    );
  });

  test('backups rotate keeping the three most recent', () async {
    for (var i = 0; i < 4; i++) {
      await store.saveRaw(conf, 'guest_os="linux"\nram="${i + 1}G"\n');
    }
    // Each .bak holds the content BEFORE its write: after the 4th save
    // (ram=4G), .bak has ram=3G, .bak.1 has 2G, .bak.2 has 1G.
    expect(File('$conf.bak').readAsStringSync(), contains('ram="3G"'));
    expect(File('$conf.bak.1').readAsStringSync(), contains('ram="2G"'));
    expect(File('$conf.bak.2').readAsStringSync(), contains('ram="1G"'));
    expect(File('$conf.bak.3').existsSync(), isFalse);
  });

  test('values are sanitized so they cannot inject conf lines', () {
    store.write(conf, 'display', 'x"\nevil="injected');
    final lines = File(conf).readAsLinesSync();
    expect(lines.where((l) => l.startsWith('evil=')), isEmpty);
  });

  test('fingerprint changes when the file changes', () async {
    final before = VmConfigFileStore.fingerprint(conf);
    await store.saveRaw(conf, 'guest_os="linux"\nram="9G"\n');
    expect(VmConfigFileStore.fingerprint(conf), isNot(before));
  });

  test('fingerprint reports missing for absent files', () {
    expect(VmConfigFileStore.fingerprint('${dir.path}/nope.conf'), 'missing');
  });

  test(
    'write through a symlink keeps the link and swaps the target',
    () {
      final target = '${dir.path}/real.conf';
      final link = '${dir.path}/link.conf';
      File(target).writeAsStringSync('guest_os="linux"\n');
      Link(link).createSync(target);
      store.write(link, 'ram', '4G');
      expect(FileSystemEntity.typeSync(link), FileSystemEntityType.link);
      expect(File(target).readAsStringSync(), contains('ram="4G"'));
    },
    // Creating symlinks on Windows requires Developer Mode/admin.
    skip: Platform.isWindows ? 'symlink creation needs a privilege' : null,
  );
}
