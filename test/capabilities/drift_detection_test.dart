// Capability drift detection (pattern: Capability Drift Detection,
// No Orphan Capability).
//
// Two layers:
//  1. Snapshot gate (always on): every canonical backend option recorded in
//     [_knownBackendOptions] is claimed by at least one manifest capability,
//     and every manifest flag resolves to a known option — catches typos.
//  2. Live gate (when the sibling quickemu checkout exists): the option
//     surface extracted from the Go CLI parsers (`case "--x"` arms in
//     tools/quickemu-cli/main.go + subcommandAliases keys, and
//     tools/quickget-cli/main.go) — or the legacy options.sh when present —
//     must equal the snapshot. A new upstream option fails the suite until
//     someone classifies it in the manifest.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/capabilities/capability_manifest.dart';

/// Canonical `--long` option surface of quickemu 5.0.0 (options.sh case
/// arms plus the --help table) and quickget, frozen 2026-10-27.
/// Bareword subcommands dispatched to flags are included as `--x` tokens.
const Set<String> _knownBackendOptions = {
  // quickemu --options
  '--access', '--autostart', '--backup', '--backup-list', '--backup-prune',
  '--backup-restore', '--backup-verify', '--braille', '--capabilities',
  '--check', '--clone', '--cpu-pinning', '--delete', '--delete-disk',
  '--delete-plan', '--delete-shortcut', '--delete-vm', '--disk-compact',
  '--disk-resize', '--display', '--doctor', '--dry-run', '--echo',
  '--events', '--export', '--external', '--extra_args', '--fix',
  '--format', '--full', '--full-screen', '--fullscreen', '--height',
  '--help', '--host-info', '--hotplug-disk', '--hotplug-usb',
  '--hotunplug', '--ignore-msrs-always', '--ignore-tsc-warning', '--import',
  '--inspect-conf', '--inventory', '--keyboard', '--keyboard_layout',
  '--kill', '--linked-clone', '--list-vms', '--migrate-conf', '--monitor',
  '--monitor-cmd', '--monitor-telnet-host', '--monitor-telnet-port',
  '--mouse', '--move', '--offline', '--op-cancel', '--op-list',
  '--op-status', '--op-watch', '--operation-cancel', '--operation-list',
  '--operation-status', '--operation-watch', '--pause', '--persist',
  '--plan-id', '--plugin', '--plugins', '--profile', '--public-dir',
  '--rename', '--reset', '--resume', '--screenshot', '--send-keys',
  '--serial', '--serial-telnet-host', '--serial-telnet-port', '--shortcut',
  '--shutdown', '--snapshot', '--snapshot-tree', '--snapshot-verify',
  '--sound-card', '--sound-duplex', '--spice-port', '--ssh-access',
  '--ssh-port', '--stats', '--status', '--status-quo', '--trash',
  '--trash-empty', '--trash-list', '--trash-restore', '--type',
  '--usb-controller', '--usb-passthrough', '--version', '--vfio-scan',
  '--viewer', '--vm', '--width',
  // go-cli surface additions (flag variants + actions accepted by the
  // Go parser that options.sh reached through normalisation)
  '--start', '--stop', '--extra-args', '--keyboard-layout',
  '--serial-console', '--monitor-console', '--disk-resize-commit',
  // quickemu bareword subcommands (dispatched to --flag form)
  '--restart', '--snapshot-apply', '--snapshot-create', '--snapshot-delete',
  '--snapshot-info', '--snapshot-list', '--create-disk', '--resize-commit',
  '--console', '--vnc', '--spice-console', '--publicdir', '--ignore-msrs',
  '--list', '--vms', '--conf', '--plan', '--scan', '--keys', '--cmd',
  '--disk', '--watch', '--cancel', '--restore', '--verify', '--quo',
  '--msrs', '--msrs-always', '--apply', '--info', '--create', '--resize',
  // quickget --options
  '--arch', '--check-all-arch', '--cloud-init', '--create-config',
  '--disable-unattended', '--download', '--insecure',
  '--list-csv', '--list-json', '--open-homepage', '--show', '--unattended',
  '--update', '--url', '--minimum-trust',
};

/// quickemu checkout candidates (Windows worktree and the WSL mirror).
final _siblingOptionsFiles = [
  '../quickemu/lib/quickemu/cli/options.sh',
  '/mnt/c/Users/alex0/Documents/fyp/quickemu/lib/quickemu/cli/options.sh',
];

/// Go CLI parser sources — the post-migration option surface. The
/// accepted flags are the `case "--x"` arms of the argv parser; the
/// subcommandAliases map keys are accepted bareword spellings.
final _liveGoSources = [
  '../quickemu/tools/quickemu-cli/main.go',
  '/mnt/c/Users/alex0/Documents/fyp/quickemu/tools/quickemu-cli/main.go',
  '../quickemu/tools/quickget-cli/main.go',
  '/mnt/c/Users/alex0/Documents/fyp/quickemu/tools/quickget-cli/main.go',
];

final _caseLineRe = RegExp(r'^\s*case\s[^\n]*', multiLine: true);
final _flagRe = RegExp('--[a-zA-Z][a-zA-Z0-9_-]+');
final _aliasBlockRe = RegExp(
  r'subcommandAliases\s*=\s*map\[string\]bool\{([^}]*)\}',
);
final _aliasKeyRe = RegExp(r'"([a-zA-Z][a-zA-Z0-9_-]+)":\s*true');

Set<String> _liveOptions() {
  for (final path in _siblingOptionsFiles) {
    final f = File(path);
    if (!f.existsSync()) continue;
    return _flagRe.allMatches(f.readAsStringSync()).map((m) => m[0]!).toSet();
  }
  final flags = <String>{};
  for (final path in _liveGoSources) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final src = f.readAsStringSync();
    for (final line in _caseLineRe.allMatches(src)) {
      flags.addAll(_flagRe.allMatches(line[0]!).map((m) => m[0]!));
    }
    final block = _aliasBlockRe.firstMatch(src);
    if (block != null) {
      for (final m in _aliasKeyRe.allMatches(block[1]!)) {
        flags.add('--${m[1]}');
      }
    }
  }
  return flags;
}

void main() {
  late CapabilityManifest manifest;

  setUpAll(() {
    manifest = CapabilityManifest.parse(
      File('assets/capabilities/capability_manifest.json').readAsStringSync(),
    );
  });

  test('every canonical backend option is claimed by a capability', () {
    final covered = manifest.coveredFlags;
    final missing = _knownBackendOptions.difference(covered);
    expect(
      missing,
      isEmpty,
      reason:
          'backend options with no manifest capability: '
          '${missing.toList()..sort()}',
    );
  });

  test('every manifest flag resolves to a known backend option', () {
    final unknown = manifest.coveredFlags.difference(_knownBackendOptions);
    expect(
      unknown,
      isEmpty,
      reason:
          'manifest flags that do not exist on the backend: '
          '${unknown.toList()..sort()}',
    );
  });

  test('no capability is duplicated across manifest flags', () {
    // quickemu and quickget share spellings (e.g. --list) — a flag is
    // only duplicated when the same executable exposes it twice.
    final seen = <String, String>{};
    final dupes = <String>[];
    for (final c in manifest.capabilities) {
      for (final f in c.backend.flags) {
        final key = '${c.backend.executable} $f';
        final owner = seen[key];
        if (owner != null) dupes.add('$f ($owner & ${c.id})');
        seen[key] = c.id;
      }
    }
    expect(dupes, isEmpty, reason: 'flags claimed by two capabilities: $dupes');
  });

  test('live backend option surface matches the snapshot', () {
    final live = _liveOptions();
    if (live.isEmpty) {
      markTestSkipped('sibling quickemu checkout not found');
      return;
    }
    final newOptions = live.difference(_knownBackendOptions);
    expect(
      newOptions,
      isEmpty,
      reason:
          'backend gained unclassified options — classify them in '
          'capability_manifest.json: ${newOptions.toList()..sort()}',
    );
  });
}
