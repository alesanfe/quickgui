import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

class LibraryMachine {
  const LibraryMachine({
    required this.name,
    required this.confPath,
    required this.state,
    required this.values,
    this.pid,
    this.diskBytes,
  });

  final String name;
  final String confPath;
  final String state;
  final Map<String, String?> values;
  final int? pid;
  final int? diskBytes;

  bool get active => state == 'running' || state == 'paused';
}

final vmLibraryProvider = FutureProvider<List<LibraryMachine>>((ref) async {
  final backend = ref.watch(backendProvider);
  final store = ref.watch(vmConfigStoreProvider);
  final probe = ref.watch(hostProbeProvider);
  final directory = await probe.workingDirectory();
  final root = Directory(
    directory.isEmpty ? Directory.current.path : directory,
  );
  if (!root.existsSync()) return [];
  final timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final machines = <LibraryMachine>[];
  await for (final entry in root.list(followLinks: false)) {
    if (entry is! File || !entry.path.endsWith('.conf')) continue;
    if (store.read(entry.path, 'guest_os') == null) continue;
    final name = p.basenameWithoutExtension(entry.path);
    final values = <String, String?>{
      for (final key in [
        'guest_os',
        'ram',
        'cpu_cores',
        'disk_size',
        'disk_img',
        'boot',
        'network',
        'display',
        'viewer',
        'ssh_port',
        'spice_port',
        'iso',
        'public_dir',
      ])
        key: store.read(entry.path, key),
    };
    final status = await backend.inspectVirtualMachine(
      p.withoutExtension(entry.path),
    );
    var state = '${status['state'] ?? 'stopped'}';
    final pidFile = File(p.join(root.path, name, '$name.pid'));
    int? vmPid = int.tryParse('${status['pid']}');
    if (pidFile.existsSync()) {
      vmPid ??= int.tryParse(pidFile.readAsStringSync().trim());
      if (vmPid != null && !await probe.isPidAlive(vmPid)) {
        state = 'stale';
      }
    }
    final disk = values['disk_img'];
    final diskFile = disk == null
        ? null
        : File(p.isAbsolute(disk) ? disk : p.join(root.path, disk));
    machines.add(
      LibraryMachine(
        name: name,
        confPath: entry.path,
        state: state,
        values: values,
        pid: vmPid,
        diskBytes: diskFile != null && diskFile.existsSync()
            ? diskFile.lengthSync()
            : null,
      ),
    );
  }
  machines.sort((a, b) => a.name.compareTo(b.name));
  return machines;
});

final hostFreeSpaceProvider = FutureProvider<int?>((ref) async {
  final probe = ref.watch(hostProbeProvider);
  return await probe.freeSpaceBytes(await probe.workingDirectory());
});
