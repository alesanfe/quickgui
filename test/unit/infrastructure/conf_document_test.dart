import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/storage/conf_document.dart';

void main() {
  group('ConfDocument.parse', () {
    test('minimal and complete configs', () {
      final doc = ConfDocument.parse('ram="4G"\ncpu_cores="4"\n');
      expect(doc.toMap(), {'ram': '4G', 'cpu_cores': '4'});
      expect(doc.unparsed, isEmpty);
      expect(doc.duplicateKeys, isEmpty);
    });

    test('comments, blanks and spaces around = are preserved', () {
      const raw = '# a comment\n\nram = "4G"  \n';
      final doc = ConfDocument.parse(raw);
      expect(doc.toMap()['ram'], '4G');
      expect(doc.lines[0].kind, ConfLineKind.comment);
      expect(doc.lines[1].kind, ConfLineKind.blank);
      expect(doc.serialize(), raw);
    });

    test('round-trip is byte-stable when unedited', () {
      const raw =
          '#!/usr/bin/quickemu --vm\nguest_os="linux"\nram="8G"\n# note\n';
      expect(ConfDocument.parse(raw).serialize(), raw);
    });

    test('duplicate keys are flagged, last wins in toMap', () {
      final doc = ConfDocument.parse('ram="4G"\nram="8G"\n');
      expect(doc.duplicateKeys, ['ram']);
      expect(doc.toMap()['ram'], '8G');
      expect(doc.warnings.single.warning, contains('duplicate key'));
    });

    test('unquoted values tolerated with warning', () {
      final doc = ConfDocument.parse('ram=4G\n');
      expect(doc.toMap()['ram'], '4G');
      expect(doc.warnings.single.warning, contains('unquoted'));
    });

    test('empty value differs from absent key', () {
      final doc = ConfDocument.parse('name=""\n');
      expect(doc.toMap().containsKey('name'), isTrue);
      expect(doc.toMap()['name'], '');
      expect(doc.toMap().containsKey('other'), isFalse);
    });

    test('unclosed quote is unparsed, not dropped', () {
      final doc = ConfDocument.parse('ram="4G\n');
      expect(doc.toMap(), isEmpty);
      expect(doc.unparsed, hasLength(1));
      expect(doc.unparsed.single.raw, 'ram="4G');
    });

    test('trailing content after closing quote is unparsed', () {
      final doc = ConfDocument.parse('ram="4G" ; rm -rf /\n');
      expect(doc.toMap(), isEmpty);
      expect(doc.unparsed, hasLength(1));
    });

    test('= inside quoted value is fine', () {
      final doc = ConfDocument.parse('args="a=b c"\n');
      expect(doc.toMap()['args'], 'a=b c');
    });

    test('escaped chars decode inside quotes', () {
      final doc = ConfDocument.parse(
        r'p="a\"b\\c\$d"'
        '\n',
      );
      expect(doc.toMap()['p'], r'a"b\c$d');
    });

    test('array values kept verbatim', () {
      final doc = ConfDocument.parse('port_forwards=("8080:80" "443:443")\n');
      expect(doc.toMap()['port_forwards'], '("8080:80" "443:443")');
    });

    test('unicode and CRLF tolerated', () {
      final doc = ConfDocument.parse('name="máquina ü"\r\nram="4G"\r\n');
      expect(doc.toMap()['name'], 'máquina ü');
      expect(doc.toMap()['ram'], '4G');
    });

    test('non-entry lines are unparsed but preserved', () {
      const raw = 'ram="4G"\necho pwned\nexport X=1\n';
      final doc = ConfDocument.parse(raw);
      expect(doc.unparsed, hasLength(2));
      expect(doc.serialize(), raw);
    });

    test('file without trailing newline parses fully', () {
      final doc = ConfDocument.parse('ram="4G"');
      expect(doc.toMap()['ram'], '4G');
    });

    test('dangling escape at end is malformed', () {
      final doc = ConfDocument.parse('p="abc\\\n');
      expect(doc.unparsed, hasLength(1));
    });
  });

  group('ConfDocument.applyEdits', () {
    test('edits only the target line, preserving everything else', () {
      const raw = '# keep me\nram="4G"\nunknown_opt="x"\nweird syntax\n';
      final merged = ConfDocument.parse(raw).applyEdits({'ram': '8G'});
      expect(
        merged.serialize(),
        '# keep me\nram="8G"\nunknown_opt="x"\nweird syntax\n',
      );
    });

    test('new keys are appended', () {
      final merged = ConfDocument.parse('ram="4G"\n')
          .applyEdits({'cpu_cores': '2'});
      expect(merged.serialize(), 'ram="4G"\ncpu_cores="2"\n');
    });

    test('edits are re-escaped for bash safety', () {
      final merged = ConfDocument.parse('p="x"\n')
          .applyEdits({'p': 'a"b\n\$(evil)'});
      expect(merged.toMap()['p'], r'a"b$(evil)');
      expect(merged.serialize(), contains(r'\"'));
      expect(merged.serialize(), contains(r'\$'));
    });

    test('unparsable file still merges without losing syntax', () {
      const raw = 'ram="4G"\n???not valid???\n';
      final merged = ConfDocument.parse(raw).applyEdits({'ram': '16G'});
      expect(merged.serialize(), 'ram="16G"\n???not valid???\n');
    });
  });

  group('conflict classification', () {
    test('detects real conflicts, ignores one-sided changes', () {
      final keys = confConflictKeys(
        'a="1"\nb="1"\nc="1"\n',
        'a="2"\nb="2"\nc="1"\n',
        'a="3"\nb="1"\nc="1"\n',
      );
      expect(keys, ['a']);
    });
  });

  group('mergeConfDocuments', () {
    test('auto-merges one-sided changes both ways', () {
      final merged = mergeConfDocuments(
        'ram="8G"\ndisk="64G"\n',
        'ram="4G"\ndisk="64G"\nextra="1"\n',
        original: 'ram="4G"\ndisk="64G"\n',
      );
      expect(merged, contains('ram="8G"'));
      expect(merged, contains('extra="1"'));
    });

    test('conflicts honour per-key choices', () {
      final merged = mergeConfDocuments(
        'ram="6G"\ncpu="4"\n',
        'ram="8G"\ncpu="8"\n',
        original: 'ram="4G"\ncpu="2"\n',
        choices: {'ram': true, 'cpu': false},
      );
      expect(merged, contains('ram="6G"'));
      expect(merged, contains('cpu="8"'));
    });

    test('unresolved conflicts keep disk value', () {
      final merged = mergeConfDocuments(
        'ram="6G"\n',
        'ram="8G"\n',
        original: 'ram="4G"\n',
      );
      expect(merged, contains('ram="8G"'));
    });

    test('preserves comments and unknown lines from disk', () {
      final merged = mergeConfDocuments(
        'ram="8G"\n',
        '# note\nram="4G"\nweird syntax\n',
        original: 'ram="4G"\n',
      );
      expect(merged, contains('# note'));
      expect(merged, contains('weird syntax'));
      expect(merged, contains('ram="8G"'));
    });

    test('local-only new keys are added', () {
      final merged = mergeConfDocuments(
        'ram="4G"\nnewkey="x"\n',
        'ram="4G"\n',
        original: 'ram="4G"\n',
      );
      expect(merged, contains('newkey="x"'));
    });
  });
}
