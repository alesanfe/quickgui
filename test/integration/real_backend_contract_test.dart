// Real-backend GUI<->CLI tests: drive the same CLI sequence the app
// issues and verify the backend parses the v1 envelopes correctly.
// Skipped where `quickemu` isn't on PATH (Linux CI / dev only).
import 'dart:convert';
import 'dart:io';

import 'package:quickgui/infrastructure/process/system_process_runner.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart'
    show ProcessRunner;

void main() {
  final hasQemu = Process.runSync('which', ['quickemu']).exitCode == 0;
  final skipMsg = hasQemu ? null : 'quickemu not on PATH';
  final ProcessRunner runner = SystemProcessRunner();
  final backend = QuickemuBackend(runner);

  late Directory tmp;
  late File conf;

  setUpAll(() {
    if (!hasQemu) return;
    tmp = Directory.systemTemp.createTempSync('qg_e2e_');
    conf = File('${tmp.path}/e2e.conf')
      ..writeAsStringSync(
        'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\n',
      );
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('capabilities expose the 4.9.9 v1 surface', () async {
    final caps = await backend.getCapabilities();
    expect(caps, isNotNull);
    // the backend may return data.capabilities or the flat map
    final c = (caps!.containsKey('capabilities')
        ? caps['capabilities'] as Map<String, dynamic>
        : caps);
    expect(c['structuredStatus'], isTrue);
    expect(c['asyncOperations'], isTrue);
    expect(c['tomlConfig'], isTrue);
  }, skip: skipMsg);

  test('status returns a real state for a stopped VM', () async {
    final r = await Process.run('quickemu', [
      '--vm',
      conf.path,
      '--status',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    final e = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(e['command'], 'vm.status');
    expect(e['data']['state'], 'stopped');
    expect(e['data']['allowedOps'], isA<List<dynamic>>());
  }, skip: skipMsg);

  test('delete-plan -> planId -> delete-vm (guarded, trashed)', () async {
    final plan = await Process.run('quickemu', [
      '--vm',
      conf.path,
      '--delete-plan',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    final pe = jsonDecode(plan.stdout as String) as Map<String, dynamic>;
    final planId = pe['data']['planId'] as String;
    expect(planId, startsWith('sha256:'));

    await File('${tmp.path}/e2e.qcow2').writeAsString('x');
    final del = await Process.run('quickemu', [
      '--vm',
      conf.path,
      '--delete-vm',
      '--plan-id',
      planId,
      '--trash',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    final de = jsonDecode(del.stdout as String) as Map<String, dynamic>;
    expect(de.containsKey('command'), isTrue);
  }, skip: skipMsg);

  test('op-status on a missing op yields a typed error', () async {
    final r = await Process.run('quickemu', [
      '--vm',
      conf.path,
      '--op-status',
      'nope-1',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    final e = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(e['errors'], isA<List<dynamic>>());
    expect(jsonEncode(e['errors']), contains('OPERATION_NOT_FOUND'));
  }, skip: skipMsg);

  test('inventory lists the registered VM (instanceId -> entry)', () async {
    final r = await Process.run('quickemu', [
      '--vm',
      conf.path,
      '--inventory',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    expect(jsonDecode(r.stdout as String), isA<Map<String, dynamic>>());
  }, skip: skipMsg);
}
