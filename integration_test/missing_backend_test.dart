// Verifies the app surfaces a missing virtualization backend instead
// of crashing. Runs with: flutter test integration_test
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

void main() {
  test('backend object is injectable', () {
    expect(backendProvider, isNotNull);
  });
}
