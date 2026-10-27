// Bug-confirmation tests for unchecked jsonDecode on external data.
// A corrupted events.jsonl or tags file crashes the UI silently.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activity_providers + vm_tags_providers — jsonDecode(raw)', () {
    test('crashes on a truncated JSON line', () {
      // A partially-written events.jsonl (crash mid-write) leaves a
      // truncated line → jsonDecode throws FormatException.
      expect(
        () => jsonDecode('{"seq":1,"type":"vm.starte'),
        throwsA(isA<FormatException>()),
      );
    });

    test('crashes on a non-JSON line (log noise)', () {
      // A stray banner/comment line in the file crashes the decode.
      expect(() => jsonDecode('# comment'), throwsA(isA<FormatException>()));
    });

    test('safe alternative skips malformed lines', () {
      final lines = ['{"seq":1}', '# comment', '{"seq":2}'];
      final decoded = <Map<String, dynamic>>[];
      for (final l in lines) {
        try {
          decoded.add(Map<String, dynamic>.from(jsonDecode(l) as Map));
        } on FormatException catch (_) {
          // skip
        }
      }
      expect(decoded.length, 2);
    });
  });

  group('quickemu_backend:569 — jsonDecode(l) as Map', () {
    test('crashes when an event line is a JSON scalar', () {
      // jsonDecode('42') → 42 → 'as Map' cast throws.
      expect(
        () => jsonDecode('42') as Map<dynamic, dynamic>,
        throwsA(isA<TypeError>()),
      );
    });
  });
}
