import 'dart:convert';

import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';

/// Pure decoders for the structured CLI contract payloads (schemas/v1)
/// plus the legacy text fallbacks for older quickemu versions.

/// `--capabilities` payload; null when absent or malformed (older quickemu).
Map<String, dynamic>? parseCapabilitiesPayload(String stdout) {
  try {
    final decoded = jsonDecode(stdout.trim());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// `--list-vms --format json` payload; null when malformed.
List<String>? parseVmListPayload(String stdout) {
  try {
    final decoded = jsonDecode(stdout.trim());
    if (decoded is Map && decoded[contractKeyVms] is List) {
      return [
        for (final v in decoded[contractKeyVms] as List)
          '${(v as Map)[contractKeyVmName]}',
      ];
    }
  } catch (_) {}
  return null;
}

/// `quickemu --vm x.conf --status --format json` payload; null when malformed.
Map<String, dynamic>? parseVmStatusPayload(String stdout) {
  try {
    final decoded = jsonDecode(stdout.trim());
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// `--snapshot list --format json` payload (v1 vm-snapshots contract);
/// null when malformed. Returns the normalized snapshot maps verbatim.
List<Map<String, dynamic>>? parseVmSnapshotsPayload(String stdout) {
  try {
    final decoded = jsonDecode(stdout.trim());
    if (decoded is Map && decoded['snapshots'] is List) {
      return [
        for (final s in decoded['snapshots'] as List)
          Map<String, dynamic>.from(s as Map),
      ];
    }
  } catch (_) {}
  return null;
}

/// Legacy `running <pid>` / `stopped` text status.
Map<String, dynamic> parseLegacyVmStatus(String vm, String stdout) {
  final text = stdout.trim();
  return {
    'name': vm,
    'state': text.startsWith('running') ? 'running' : 'stopped',
    'pid': int.tryParse(text.split(' ').last),
  };
}

/// `quickget --list-json` payload; null when absent or malformed.
List<List<String>>? parseOsCatalogueJson(String stdout) {
  if (stdout.trim().isEmpty) return null;
  try {
    return [
      for (final e in jsonDecode(stdout) as List)
        [
          '${e['Display Name']}',
          '${e['OS']}',
          '${e['Release']}',
          '${e['Option']}',
          '${e['Downloader']}',
        ],
    ];
  } catch (_) {
    return null;
  }
}

/// `quickget --list-csv` legacy catalogue (header row skipped).
List<List<String>> parseOsCatalogueCsv(String stdout) => stdout
    .split('\n')
    .skip(1)
    .where((l) => l.isNotEmpty)
    .map((l) => l.trim().split(','))
    .toList();
