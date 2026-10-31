// Covers the collection-grouping rules (QG-032): the `group:name`
// tag convention, exclusion of internal tags, alphabetical ordering
// and the ungrouped-always-last invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/vm_grouping.dart';

void main() {
  group('vmCollection', () {
    test('group:name tag names the collection before the colon', () {
      expect(vmCollection({'web:prod'}), 'web');
      expect(vmCollection({'lab:test', 'other'}), 'lab');
    });

    test('plain tags and _internal tags never name a collection', () {
      expect(vmCollection({'linux', 'x86'}), isNull);
      expect(vmCollection({'_favorite'}), isNull);
      expect(vmCollection({'_hidden:secret'}), isNull);
    });

    test('a tag ending at the colon is ignored', () {
      expect(vmCollection({'web:'}), isNull);
    });

    test('first matching tag wins (deterministic, sorted order)', () {
      expect(vmCollection({'z:last', 'a:first'}), 'a');
    });
  });

  group('groupMachines', () {
    final tags = {
      'a': ['web:prod'],
      'b': <String>[],
      'c': ['db:prod'],
      'd': ['web:dev'],
    };

    test('groups by collection, ungrouped last, collections sorted', () {
      final grouped = groupMachines(['a', 'b', 'c', 'd'], tags);
      expect(grouped.keys.toList(), ['db', 'web', null]);
      expect(grouped['web'], ['a', 'd']);
      expect(grouped['db'], ['c']);
      expect(grouped[null], ['b']);
    });

    test('no collections -> single null group', () {
      final grouped = groupMachines(['x', 'y'], {'x': [], 'y': []});
      expect(grouped.keys.toList(), [null]);
      expect(grouped[null], ['x', 'y']);
    });

    test('input order preserved inside each group', () {
      final grouped = groupMachines(['d', 'a'], tags);
      expect(grouped['web'], ['d', 'a']);
    });

    test('VMs missing from the tag map are ungrouped', () {
      final grouped = groupMachines(['zz'], tags);
      expect(grouped[null], ['zz']);
    });
  });
}
