// Bug confirmation: selection.versions.first on an empty versions
// list crashes with StateError instead of leaving a sensible default.
// Found during the full-project debt audit.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';

void main() {
  test('versions.first crashes on an empty versions list', () {
    // Mirrors create_wizard_page.dart:95 and download_controls.dart:73 —
    // `selection.versions.first.options.length` throws when versions
    // is empty before the length check can run.
    final item = OperatingSystem('Test', 'test-os');
    expect(item.versions, isEmpty);
    expect(
      () => item.versions.first.options.length,
      throwsA(isA<StateError>()),
    );
  });

  test('firstOrNull is the safe alternative (documents the fix)', () {
    final item = OperatingSystem('Test', 'test-os');
    // The guard the code should use — returns null, no crash.
    expect(item.versions.firstOrNull, isNull);
  });
}
