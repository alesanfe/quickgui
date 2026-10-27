// Bug-confirmation tests for unchecked indexing found in the audit.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app.dart:29 — Locale(s.split("_")[0], s.split("_")[1])', () {
    test('crashes on a locale tag without a country part', () {
      // 'en' (no '_') → split returns ['en'] → [1] out of bounds.
      expect(() => 'en'.split('_')[1], throwsA(isA<RangeError>()));
    });

    test('safe alternative checks the split length', () {
      final parts = 'en'.split('_');
      expect(parts.length > 1 ? parts[1] : null, isNull);
    });
  });

  group('os_icon_assets.dart:14 — substring(0, lastIndexOf("."))', () {
    test('crashes on a filename without an extension', () {
      // lastIndexOf('.') → -1 → substring(0, -1) throws.
      expect(
        () => 'icon-noext'.substring(0, 'icon-noext'.lastIndexOf('.')),
        throwsA(isA<RangeError>()),
      );
    });

    test('safe alternative guards the -1 index', () {
      const filename = 'icon-noext';
      final dot = filename.lastIndexOf('.');
      expect(dot == -1 ? filename : filename.substring(0, dot), filename);
    });
  });
}
