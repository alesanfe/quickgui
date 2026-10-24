import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const dir = 'test/fixtures/backend-responses/quickqemu-v1';

  test('capabilities fixture is schema v1 with capability map', () {
    final j = jsonDecode(File('$dir/capabilities.json').readAsStringSync());
    expect(j['schemaVersion'], 1);
    expect(j['capabilities'], isA<Map<String, dynamic>>());
    expect(j['capabilities']['structuredStatus'], isTrue);
  });

  test('vm-status fixture parses to name/state/pid', () {
    final j = jsonDecode(File('$dir/vm-status.json').readAsStringSync());
    expect(j['state'], 'running');
    expect(j['pid'], 42);
  });
}
