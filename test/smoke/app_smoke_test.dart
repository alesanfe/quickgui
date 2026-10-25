import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/features/machines/domain/vm_status.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

/// Smoke tests: the core surfaces the rest of the app depends on exist
/// and behave — if these fail, nothing else will work.
void main() {
  test('VmConfigStore read/write works end to end', () {
    const store = VmConfigFileStore();
    final tmp = Directory.systemTemp.createTempSync('qe-smoke-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final conf = '${tmp.path}/vm.conf';
    store.write(conf, 'guest_os', 'linux');
    expect(store.read(conf, 'guest_os'), 'linux');
  });

  test('VmStatus covers the contract states', () {
    expect(VmStatus.values.length, greaterThanOrEqualTo(4));
    expect(VmStatus.fromWire('running'), VmStatus.running);
  });

  test('at least English is a supported locale', () {
    expect(supportedLocales, contains('en'));
  });
}
