// Runs with: flutter test integration_test (needs a device/host).
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/app/dependencies/providers.dart';

void main() {
  test('create_vm: backend object is injectable', () {
    expect(backendProvider, isNotNull);
  });
}
