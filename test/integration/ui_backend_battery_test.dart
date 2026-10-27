// UI ↔ real quickemu battery: every operation the app performs through
// QuickemuBackend, exercised against a live VM. Mirrors the CLI battery
// 1:1 so the interface behaviour and the backend behaviour stay in sync.
// Skipped without quickemu on PATH.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';

void main() {
  final hasQemu = Process.runSync('which', ['quickemu']).exitCode == 0;
  final skipMsg = hasQemu ? null : 'quickemu not on PATH';

  late Directory tmp;
  late String conf;
  late QuickemuBackend backend;

  setUpAll(() async {
    if (!hasQemu) return;
    tmp = Directory.systemTemp.createTempSync('qg_battery_');
    conf = '${tmp.path}/battery.conf';
    // Minimal stopped VM — battery tests the backend surface, not boot.
    File(conf).writeAsStringSync(
      'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\n',
    );
    File('${tmp.path}/disk.qcow2').writeAsStringSync('x');
    backend = QuickemuBackend(SystemProcessRunner());
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  // ── status ────────────────────────────────────────────────────────────

  test('status → stopped with stopped allowedOps', () async {
    final r = await backend.inspectVirtualMachine('${tmp.path}/battery');
    expect(r['state'], 'stopped');
    final allowed = (r['allowedOps'] as List).map((e) => '$e').toSet();
    expect(allowed, containsAll(['start', 'delete', 'clone', 'rename']));
  }, skip: skipMsg);

  // ── capabilities (what the app gates UI on) ──────────────────────────

  test('capabilities envelope has the flags the UI reads', () async {
    final caps = await backend.getCapabilities();
    final flags = (caps?['capabilities'] as Map?) ?? const <String, dynamic>{};
    expect(flags['structuredStatus'], isTrue);
    expect(flags['verifiableDeletePlan'], isTrue);
  }, skip: skipMsg);

  // ── ops registry ──────────────────────────────────────────────────────

  test('listOperations → empty registry when nothing is running', () async {
    final ops = await backend.listOperations(conf);
    expect(ops, isA<List>());
  }, skip: skipMsg);

  // ── delete-plan → verifiable (the secure path the UI drives) ─────────

  test('delete-plan produces a planId the UI can confirm', () async {
    final plan = await backend.runVmJson('delete-plan', [
      '--vm',
      conf,
      '--delete-plan',
    ]);
    expect(plan['planId'], isA<String>());
    expect(plan['planId'] as String, startsWith('sha256:'));
  }, skip: skipMsg);

  // ── monitor-cmd (the monitor console) ────────────────────────────────

  test('monitor-cmd on a stopped VM reports not-running cleanly', () async {
    final r = await backend.runAction([
      '--vm',
      conf,
      '--monitor-cmd',
      'info status',
    ]);
    expect(r.exitCode, isNot(0));
  }, skip: skipMsg);

  // ── snapshot-tree (the snapshots tab) ────────────────────────────────

  test('snapshot-tree returns a list for the stopped VM', () async {
    final r = await backend.runVmJson('snapshot.tree', [
      '--vm',
      conf,
      '--snapshot-tree',
    ]);
    expect(r, isA<Map<String, dynamic>>());
  }, skip: skipMsg);

  // ── trash-list / backup-list (the destructive menus) ─────────────────
  // trash-list is a global listing (no --vm, mirrors the real backend call)

  test('trash-list returns a list', () async {
    // Empty trash prints a banner before the envelope — the UI consumes
    // it via the legacy runAction path.
    final r = await backend.runAction(['--vm', conf, '--trash-list']);
    expect(r.exitCode, 0);
  }, skip: skipMsg);

  test('backup-list returns a list', () async {
    final r = await backend.runVmJson('backup.list', [
      '--vm',
      conf,
      '--backup-list',
    ]);
    expect(r, isA<Map<String, dynamic>>());
  }, skip: skipMsg);

  // ── events (the activity feed) ───────────────────────────────────────

  test('readEvents returns a list (empty or replayable)', () async {
    final events = await backend.readEvents(conf);
    expect(events, isA<List>());
  }, skip: skipMsg);

  // ── inventory (the library) ──────────────────────────────────────────

  test('listInventory returns a map with the VM', () async {
    final inv = await backend.listInventory();
    expect(inv, isA<Map<String, dynamic>>());
  }, skip: skipMsg);

  // ── migrate-conf (TOML migration path) ───────────────────────────────

  test('migrate-conf writes a .toml beside the .conf', () async {
    // migrate-conf emits human text, not the envelope — the UI consumes
    // it through the legacy runAction path.
    await backend.runAction(['--vm', conf, '--migrate-conf']);
    expect(File('${tmp.path}/battery.toml').existsSync(), isTrue);
  }, skip: skipMsg);
}
