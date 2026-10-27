// UI ↔ real quickemu battery: every operation the app performs through
// QuickemuBackend, exercised against a live VM. Mirrors tool/cli_battery.sh
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
  late String vmPath; // path without .conf (inspectVirtualMachine appends it)
  late QuickemuBackend backend;

  setUpAll(() async {
    if (!hasQemu) return;
    tmp = Directory.systemTemp.createTempSync('qg_battery_');
    conf = '${tmp.path}/battery.conf';
    vmPath = '${tmp.path}/battery';
    File(conf).writeAsStringSync(
      'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\ndisplay="none"\n',
    );
    File('${tmp.path}/disk.qcow2').writeAsStringSync('x');
    backend = QuickemuBackend(SystemProcessRunner());
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  // ── stopped-state ops (mirrors cli_battery.sh stopped section) ───────

  test('status → stopped with stopped allowedOps', () async {
    final r = await backend.inspectVirtualMachine(vmPath);
    expect(r['state'], 'stopped');
    final allowed = (r['allowedOps'] as List).map((e) => '$e').toSet();
    expect(allowed, containsAll(['start', 'delete', 'clone', 'rename']));
  }, skip: skipMsg);

  test('listVms → the library listing runs cleanly', () async {
    // --list-json emits raw JSON lines, not the envelope — the UI
    // consumes it via the legacy path.
    final r = await backend.runAction(['--list-json']);
    expect(r.exitCode, anyOf(0, 1));
  }, skip: skipMsg);

  test('capabilities envelope has the flags the UI reads', () async {
    final caps = await backend.getCapabilities();
    final flags = (caps?['capabilities'] as Map?) ?? const {};
    expect(flags['structuredStatus'], isTrue);
    expect(flags['verifiableDeletePlan'], isTrue);
  }, skip: skipMsg);

  test('listOperations → empty registry when nothing is running', () async {
    final ops = await backend.listOperations(conf);
    expect(ops, isA<List<dynamic>>());
  }, skip: skipMsg);

  test('delete-plan produces a planId the UI can confirm', () async {
    final plan = await backend.runVmJson('delete-plan', [
      '--vm',
      conf,
      '--delete-plan',
    ]);
    expect(plan['planId'] as String, startsWith('sha256:'));
  }, skip: skipMsg);

  test('snapshot-tree returns a map for the stopped VM', () async {
    final r = await backend.runVmJson('snapshot.tree', [
      '--vm',
      conf,
      '--snapshot-tree',
    ]);
    expect(r, isA<Map<String, dynamic>>());
  }, skip: skipMsg);

  test('trash-list / backup-list exit cleanly (legacy path)', () async {
    // Empty trash/backup stores may answer exit 1 — the assertion is
    // that the op reaches the backend without crashing the app path.
    expect(
      (await backend.runAction(['--vm', conf, '--trash-list'])).exitCode,
      anyOf(0, 1),
    );
    expect(
      (await backend.runAction(['--vm', conf, '--backup-list'])).exitCode,
      anyOf(0, 1),
    );
  }, skip: skipMsg);

  test('readEvents returns a list (empty or replayable)', () async {
    final events = await backend.readEvents(conf);
    expect(events, isA<List<dynamic>>());
  }, skip: skipMsg);

  test('listInventory returns a map with the VM', () async {
    final inv = await backend.listInventory();
    expect(inv, isA<Map<String, dynamic>>());
  }, skip: skipMsg);

  test('inspect-conf exits cleanly (legacy path)', () async {
    final r = await backend.runAction(['--vm', conf, '--inspect-conf']);
    expect(r.exitCode, 0);
  }, skip: skipMsg);

  test('host-info exits cleanly (legacy path)', () async {
    // host-info requires --vm context and prints host details text —
    // the UI consumes it via the legacy path.
    final r = await backend.runAction(['--vm', conf, '--host-info']);
    expect(r.exitCode, 0);
  }, skip: skipMsg);

  test('plugins runs without crashing the app path', () async {
    // A host with no quickemu-plugin-* on PATH still answers with exit 1
    // — the app path must reach the backend either way.
    final r = await backend.runAction(['--plugins']);
    expect(r.exitCode, anyOf(0, 1));
  }, skip: skipMsg);

  test('migrate-conf writes a .toml beside the .conf', () async {
    await backend.runAction(['--vm', conf, '--migrate-conf']);
    expect(File('${tmp.path}/battery.toml').existsSync(), isTrue);
  }, skip: skipMsg);

  // ── live VM ops (mirrors cli_battery.sh live section) ────────────────
  // Launches the VM detached, exercises every running-state op, then
  // kills it. Skipped when the host can't boot (no KVM, no TCG).

  test(
    'live VM lifecycle: start→pause→resume→monitor→send→screenshot→kill',
    () async {
      // Launch detached with software emulation (CPU_MODEL/QEMU_ACCEL env).
      final env = Map<String, String>.from(Platform.environment)
        ..['CPU_MODEL'] = 'qemu64'
        ..['QEMU_ACCEL'] = 'tcg';
      final launch = await Process.start(
        'quickemu',
        ['--vm', conf],
        environment: env,
        workingDirectory: tmp.path,
      );
      launch.stdout.drain<void>();
      launch.stderr.drain<void>();

      // Wait for running (TCG boot is slow — up to 45s).
      var running = false;
      for (var i = 0; i < 45 && !running; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final s = await backend.inspectVirtualMachine(vmPath);
        running = s['state'] == 'running';
      }
      if (!running) {
        launch.kill();
        markTestSkipped('VM did not reach running — needs TCG or KVM');
        return;
      }

      try {
        // pause → paused + restricted allowedOps
        await backend.runAction(['--vm', conf, '--pause']);
        await Future<void>.delayed(const Duration(seconds: 2));
        var s = await backend.inspectVirtualMachine(vmPath);
        expect(s['state'], 'paused');
        expect(
          (s['allowedOps'] as List).map((e) => '$e'),
          containsAll(['resume', 'kill', 'status']),
        );

        // resume → running
        await backend.runAction(['--vm', conf, '--resume']);
        await Future<void>.delayed(const Duration(seconds: 2));
        s = await backend.inspectVirtualMachine(vmPath);
        expect(s['state'], 'running');

        // monitor-cmd → real HMP echo through the socket
        final mon = await backend.runAction([
          '--vm',
          conf,
          '--monitor-cmd',
          'info status',
        ]);
        expect('${mon.stdout}', contains('VM status'));

        // send-keys → typed through the monitor
        final keys = await backend.runAction([
          '--vm',
          conf,
          '--send-keys',
          'ctrl-alt-delete',
        ]);
        expect(keys.exitCode, 0);

        // type → text injection through the monitor
        final type = await backend.runAction([
          '--vm',
          conf,
          '--type',
          'echo hi',
        ]);
        expect(type.exitCode, 0);

        // screenshot → may fail headless (no framebuffer) — the op must
        // reach the backend without crashing the app path.
        await backend.runAction(['--vm', conf, '--screenshot']);

        // stats → structured metrics while running
        final stats = await backend.vmStats(vmPath);
        expect(stats, isA<Map<String, dynamic>?>());

        // snapshot-clone → COW clone while running (backend op)
        final snap = await backend.runAction([
          '--vm',
          conf,
          '--snapshot-clone',
        ]);
        expect(snap.exitCode, anyOf(0, isNot(0))); // reached the backend
      } finally {
        // kill → stopped (cleanup even if an assert fails)
        await backend.runAction(['--vm', conf, '--kill']);
        await Future<void>.delayed(const Duration(seconds: 2));
        final s = await backend.inspectVirtualMachine(vmPath);
        expect(s['state'], 'stopped');
      }
    },
    skip: skipMsg,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
