// Bug-confirmation tests for crashes found in round-2 pattern audits.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('operating_system_selection:136 — osIcons[k]!', () {
    test('crashes when the icon map lacks the OS code', () {
      // osIconsProvider returns a Map — [item.code] returns null when
      // the OS has no icon and ! dereferences it.
      const icons = {'debian': 'assets/x.png'};
      expect(
        () => icons['amiga']!,
        throwsA(isA<TypeError>()),
      );
    });

    test('safe alternative falls back to a generic icon', () {
      const icons = {'debian': 'assets/x.png'};
      expect(icons['amiga'] ?? 'assets/generic.png', 'assets/generic.png');
    });
  });

  group('activity_providers:124 — history[indexOf(entry)]', () {
    test('crashes when the entry was already removed', () {
      // indexOf returns -1 when the entry vanished between lookup and
      // assignment → history[-1] is out of bounds.
      final history = ['a', 'b'];
      expect(
        () => history[history.indexOf('missing')],
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('diagnostics_page:282 — e.value as Map', () {
    test('crashes when the value is not a map', () {
      // Diagnostics data can carry non-map values for some keys.
      const map = {'key': 'scalar'};
      expect(
        () => map['key']! as Map,
        throwsA(isA<TypeError>()),
      );
    });
  });
}
