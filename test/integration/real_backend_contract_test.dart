// Real-backend contract test: exercises QuickemuBackend against an
// actual `quickemu` binary (v1, >=4.9.9). Skipped unless the binary is
// on PATH (Linux CI / dev boxes) — unit/fake suites cover Windows.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';

void main() {
  final hasQemu = Process.runSync('which', ['quickemu']).exitCode == 0;
  final backend = QuickemuBackend(const ProcessRunner());

  test('real quickemu exposes the 4.9.9 v1 surface', () async {
    final caps = await backend.getCapabilities();
    expect(caps, isNotNull);
    expect(caps!['structuredStatus'], isTrue);
    expect(caps['asyncOperations'], isTrue);
    expect(caps['tomlConfig'], isTrue);
  }, skip: !hasQemu ? 'quickemu not on PATH' : null);

  test('real --capabilities envelope matches the contract shape', () async {
    final res = await Process.run('quickemu', ['--capabilities', '--format', 'json']);
    expect(res.exitCode, 0);
    expect(res.stdout, contains('"schemaVersion":1'));
    expect(res.stdout, contains('"command":"capabilities"'));
  }, skip: !hasQemu ? 'quickemu not on PATH' : null);
}
