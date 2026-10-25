import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/application/list_vms.dart';
import 'package:quickgui/core/result/result.dart';

import '../../../../support/fakes/fake_virtualization_backend.dart';

void main() {
  test('returns vm names when backend is available', () async {
    final fake = FakeVirtualizationBackend()..vms = ['a', 'b'];
    final r = await ListVms(fake)();
    expect((r as Ok<List<String>>).value, ['a', 'b']);
  });

  test('returns typed failure when backend is missing', () async {
    final fake = FakeVirtualizationBackend()..available = false;
    final r = await ListVms(fake)();
    expect(r, isA<Err<List<String>>>());
    expect((r as Err<List<String>>).failure.code, 'backend.unavailable');
  });
}
