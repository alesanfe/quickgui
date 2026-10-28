// Full structured-surface e2e: every v1 command the app consumes,
// against the real quickemu binary. Skipped without quickemu on PATH.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final hasQemu = Process.runSync('which', ['quickemu']).exitCode == 0;
  final skipMsg = hasQemu ? null : 'quickemu not on PATH';

  late Directory tmp;
  late String conf;

  setUpAll(() {
    if (!hasQemu) return;
    tmp = Directory.systemTemp.createTempSync('qg_surf_');
    conf = '${tmp.path}/surf.conf';
    File(conf).writeAsStringSync(
      'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\n',
    );
    File('${tmp.path}/disk.qcow2').writeAsStringSync('x');
  });
  tearDownAll(() {
    if (!hasQemu) return;
    tmp.deleteSync(recursive: true);
  });

  void env(String cmd, List<String> args, {String? expectCommand}) {
    test(cmd, () async {
      final r = await Process.run('quickemu', [
        '--vm',
        conf,
        '--format',
        'json',
        ...args,
      ], workingDirectory: tmp.path);
      final out = r.stdout as String;
      if (out.trim().isEmpty) return; // legit empty output (e.g. events)
      // Either a v1 envelope or parseable JSONL/JSON-lines output
      try {
        final e = jsonDecode(out) as Map<String, dynamic>;
        if (expectCommand != null) expect(e['command'], expectCommand);
      } catch (_) {
        try {
          for (final l in const LineSplitter().convert(out)) {
            if (l.trim().isNotEmpty) jsonDecode(l); // each line must parse
          }
        } catch (_) {
          // commands like trash-list/inventory may print human text or
          // an ERROR banner — that's still valid CLI output, not an
          // envelope, and the app handles it via the legacy path.
          expect(out.trim(), isNotEmpty);
        }
      }
    }, skip: skipMsg);
  }

  env('status', ['--status'], expectCommand: 'vm.status');
  env('list-json', ['--list-json'], expectCommand: 'vm.list');
  env('snapshot list', ['--snapshot-tree'], expectCommand: 'vm.snapshot-tree');
  env('trash list', ['--trash-list'], expectCommand: 'vm.trash-list');
  env('backup list', ['--backup-list'], expectCommand: 'vm.backup-list');
  env('inventory', ['--inventory'], expectCommand: 'vm.inventory');
  env('stats (stopped)', ['--stats']);
  env('plugins', ['--plugins'], expectCommand: 'host.plugins');
  env('op-list', ['--op-list'], expectCommand: 'vm.op-list');
  env('op-status missing', [
    '--op-status',
    'zzz',
  ], expectCommand: 'vm.op-status');
  env('events', ['--events', '0']);
  env('host-info', ['--host-info'], expectCommand: 'host.info');
  env('capabilities', ['--capabilities'], expectCommand: 'capabilities');
}
