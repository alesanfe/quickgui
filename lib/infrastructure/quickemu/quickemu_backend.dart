import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// VirtualizationBackend backed by the quickemu/quickget executables.
/// Uses the structured CLI contract (--capabilities, --format json)
/// when present and degrades gracefully on older versions.
class QuickemuBackend implements VirtualizationBackend {
  QuickemuBackend(this._runner);

  final ProcessRunner _runner;

  @override
  Future<bool> checkAvailability() async {
    final get = await _runner.run('quickget', ['--version']);
    final emu = await _runner.run('quickemu', ['--version']);
    return get.exitCode == 0 && emu.exitCode == 0;
  }

  @override
  Future<Map<String, dynamic>?> getCapabilities() async {
    try {
      final r = await _runner.run('quickemu', ['--capabilities']);
      if (r.exitCode != 0) return null;
      final decoded = jsonDecode('${r.stdout}'.trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null; // older quickemu without --capabilities
    }
  }

  @override
  Future<List<List<String>>> listOperatingSystems() async {
    // Prefer the structured JSON catalogue, fall back to CSV.
    final json = await _runner.run('quickget', ['--list-json']);
    if (json.exitCode == 0 && '${json.stdout}'.trim().isNotEmpty) {
      try {
        return [
          for (final e in jsonDecode('${json.stdout}') as List)
            [
              '${e['Display Name']}',
              '${e['OS']}',
              '${e['Release']}',
              '${e['Option']}',
              '${e['Downloader']}',
            ],
        ];
      } catch (_) {}
    }
    final csv = await _runner.run('quickget', ['--list-csv']);
    return '${csv.stdout}'
        .split('\n')
        .skip(1)
        .where((l) => l.isNotEmpty)
        .map((l) => l.trim().split(','))
        .toList();
  }

  @override
  Future<List<String>> listVirtualMachines() async {
    // Structured path first (quickemu --list-vms --format json);
    // fall back to scanning *.conf files.
    final r = await _runner.run('quickemu', ['--list-vms', '--format', 'json']);
    if (r.exitCode == 0) {
      try {
        final decoded = jsonDecode('${r.stdout}'.trim());
        if (decoded is Map) {
          final vms = decoded['vms'];
          if (vms is List) {
            return [for (final v in vms) '${(v as Map)['name']}'];
          }
        }
      } catch (_) {}
    }
    return Directory.current
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.conf'))
        .map(
          (f) =>
              f.path.split(Platform.pathSeparator).last.replaceAll('.conf', ''),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm) async {
    final r = await _runner.run('quickemu', [
      '--vm',
      '$vm.conf',
      '--status',
      '--format',
      'json',
    ]);
    if (r.exitCode == 0) {
      try {
        final decoded = jsonDecode('${r.stdout}'.trim());
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    // Fallback: legacy "running <pid>" / "stopped" text.
    final text = '${r.stdout}'.trim();
    return {
      'name': vm,
      'state': text.startsWith('running') ? 'running' : 'stopped',
      'pid': int.tryParse(text.split(' ').last),
    };
  }

  @override
  Stream<String> downloadImage(String os, String release, String option) {
    final args = <String>[os, release];
    if (option.isNotEmpty) args.add(option);
    final controller = StreamController<String>();
    _runner.start('quickget', args).then((process) {
      process.stdout
          .transform(utf8.decoder)
          .listen(controller.add, onDone: controller.close);
      process.stderr.transform(utf8.decoder).listen(controller.add);
    });
    return controller.stream;
  }

  @override
  Future<ProcessResult> runAction(List<String> arguments) =>
      _runner.run('quickemu', arguments);

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) =>
      _runner.run('quickget', arguments);

  @override
  Future<String> version() async {
    final result = await _runner.run('quickemu', ['--version']);
    return result.exitCode == 0 ? '${result.stdout}'.trim() : '';
  }
}
