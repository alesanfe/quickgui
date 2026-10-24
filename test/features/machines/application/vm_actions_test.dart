import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/application/delete_vm.dart';
import 'package:quickgui/features/machines/application/start_vm.dart';
import 'package:quickgui/features/machines/application/stop_vm.dart';
import 'package:quickgui/core/result/result.dart';

import '../../../support/fakes/fake_virtualization_backend.dart';

void main() {
  test('start sends the right args and succeeds', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = ProcessResult(0, 0, 'ok', '');
    final r = await StartVm(fake)('vm1');
    expect(r, isA<Ok<void>>());
  });

  test('stop surfaces typed failure on nonzero exit', () async {
    final fake = FakeVirtualizationBackend()
      ..lastActionResult = ProcessResult(0, 1, '', 'boom');
    final r = await StopVm(fake)('vm1');
    expect((r as Err<void>).failure.code, 'vm.stop_failed');
  });

  test('delete plan returns typed failure when backend missing', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final r = await DeleteVm(fake).plan('vm1');
    expect((r as Err<List<String>>).failure.code, 'backend.unavailable');
  });
}
