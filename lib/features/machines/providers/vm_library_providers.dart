import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/domain/guest_ip.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';

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

/// Guest network addresses via QGA for the VM at `confPath` (QG-050) —
/// one query per open details page, refreshed by journal events rather
/// than by polling: `vm.started`/`qga.*` events invalidate it.
// ignore: specify_nonobvious_property_types
final guestIpProvider = FutureProvider.family<GuestIpInfo, String>((
  ref,
  confPath,
) async {
  try {
    final data = await ref.watch(trackedBackendProvider).guestIpInfo(confPath);
    if (data == null) {
      return const GuestIpInfo(status: GuestIpStatus.unsupported);
    }
    return GuestIpInfo.parse(data);
  } on AppFailure catch (e) {
    if (GuestIpInfo.agentMissingCodes.contains(e.code)) {
      return const GuestIpInfo(status: GuestIpStatus.agentMissing);
    }
    rethrow;
  }
});

/// Issue events (crashes, failed ops) in the last 24 h for the
/// health card (QG-041) — one-shot read, no journal tail.
// ignore: specify_nonobvious_property_types
final vmRecentIssuesProvider = FutureProvider.family<int, String>((
  ref,
  vm,
) async {
  final probe = ref.watch(hostProbeProvider);
  final directory = await probe.workingDirectory();
  final root = directory.isEmpty ? Directory.current.path : directory;
  return await VmEventLog(p.join(root, vm, '$vm.events.jsonl'))
      .recentIssueCount(const Duration(hours: 24));
});

/// Live journal for one VM (`<vm>/<vm>.events.jsonl`) — replays from
/// the journal start, then tails appends. State-changing events and
/// gaps invalidate the library so the UI reacts without polling the
/// backend for every card (QG-022/QG-023).
// ignore: specify_nonobvious_property_types
final vmEventJournalProvider = StreamProvider.family<VmEvent, String>((
  ref,
  vm,
) async* {
  final probe = ref.watch(hostProbeProvider);
  final directory = await probe.workingDirectory();
  final root = directory.isEmpty ? Directory.current.path : directory;
  final log = VmEventLog(p.join(root, vm, '$vm.events.jsonl'));
  await for (final event in log.watch()) {
    if (event is VmEventGap || event.changesState) {
      ref.invalidate(vmLibraryProvider);
    }
    yield event;
  }
});
