// Runs with: flutter test integration_test (needs a device/host).
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/app/globals.dart';

void main() {
  test('incompatible_backend: backend object is injectable', () {
    expect(backend, isNotNull);
  });
}
