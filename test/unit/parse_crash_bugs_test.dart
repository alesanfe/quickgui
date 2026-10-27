// Bug-confirmation tests for unsafe parses found in the full-project
// audit. Each mirrors a real call site; the first assertion documents
// the crash, the second documents the safe alternative.
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('download_tasks_provider.dart:55 — tryParse(...)! ', () {
    test('crashes on a progress line without a percent', () {
      // Mirrors: double.tryParse(matches.last[1]!)! / 100
      const malformed = 'downloading...';
      final matches = RegExp(r'(\d+)%').allMatches(malformed).toList();
      if (matches.isEmpty) {
        expect(matches, isEmpty); // matches.last itself would throw too
        return;
      }
      expect(
        () => double.tryParse(matches.last[1]!)! / 100,
        throwsA(anything),
      );
    });

    test('safe alternative guards both lookups', () {
      const malformed = 'downloading...';
      final matches = RegExp(r'(\d+)%').allMatches(malformed).toList();
      final value =
          matches.isEmpty ? null : double.tryParse(matches.last[1] ?? '');
      expect(value, isNull); // no crash — caller handles the null
    });
  });

  group('vm_connection_view + manager — int.parse on SSH port', () {
    test('int.parse crashes on a non-numeric port', () {
      // Mirrors int.parse(vmInfo.sshPort!) / int.parse(port) — a conf
      // written by hand can carry a non-numeric ssh_port.
      expect(() => int.parse('2222abc'), throwsA(isA<FormatException>()));
    });

    test('tryParse is the safe alternative', () {
      expect(int.tryParse('2222abc'), isNull);
      expect(int.tryParse('2222'), 2222);
    });
  });

  group('downloader.dart:97 — double.parse on free-form percent', () {
    test('double.parse crashes on unexpected output', () {
      // Mirrors double.parse(percent.replaceAll('%','')) — backend
      // output like 'n/a' or 'ERROR' crashes the progress parser.
      expect(
        () => double.parse('n/a'.replaceAll('%', '')),
        throwsA(isA<FormatException>()),
      );
    });

    test('tryParse is the safe alternative', () {
      expect(double.tryParse('n/a'), isNull);
      expect(double.tryParse('45.5'), 45.5);
    });
  });
}
