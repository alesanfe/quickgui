// Generates docs/capability_matrix.md from the capability manifest
// (pattern: Capability Coverage Matrix — generated, never hand-edited).
//
// Run: dart run tool/generate_capability_matrix.dart
import 'dart:io';

import 'package:quickgui/capabilities/capability.dart';
import 'package:quickgui/capabilities/capability_manifest.dart';

const _manifestPath = 'assets/capabilities/capability_manifest.json';
const _outputPath = 'docs/capability_matrix.md';

String _cellStatus(Capability c) {
  switch (c.gui.status) {
    case GuiCapabilityStatus.implemented:
      return 'Sí';
    case GuiCapabilityStatus.partiallyImplemented:
      return 'Parcial';
    case GuiCapabilityStatus.notApplicable:
      return 'Justificada';
    case GuiCapabilityStatus.unsupported:
      return 'No';
    case GuiCapabilityStatus.planned:
      return 'Pendiente';
    case GuiCapabilityStatus.blocked:
      return 'Bloqueada';
    case GuiCapabilityStatus.deprecated:
      return 'Deprecada';
  }
}

String renderMatrix(CapabilityManifest m) {
  final b = StringBuffer()
    ..writeln('# Capability coverage matrix')
    ..writeln()
    ..writeln(
      'Generated from `assets/capabilities/capability_manifest.json` '
      'by `tool/generate_capability_matrix.dart`. Do not edit by hand.',
    )
    ..writeln()
    ..writeln('| Capability | Domain | Backend | Quickgui | Tests | Status |')
    ..writeln('|---|---|---|---|---|---|');

  final byStatus = m.byStatus;
  for (final c in m.capabilities) {
    final flags = c.backend.flags.isEmpty
        ? c.backend.operation
        : c.backend.flags.join(', ');
    final tests = c.testingSurfaces.length;
    b.writeln(
      '| `${c.id}` | ${c.domain} | `$flags` | '
      '${c.gui.entryPoints.isEmpty ? '—' : c.gui.entryPoints.join(', ')} | '
      '$tests | ${_cellStatus(c)} |',
    );
  }

  b
    ..writeln()
    ..writeln('## Metrics')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---|')
    ..writeln('| Capabilities | ${m.capabilities.length} |');
  for (final s in GuiCapabilityStatus.values) {
    final n = (byStatus[s] ?? const []).length;
    if (n > 0) {
      b.writeln('| ${s.name} | $n |');
    }
  }
  final weighted = (m.weightedScore * 100).toStringAsFixed(1);
  b
    ..writeln('| Weighted coverage score | $weighted% |')
    ..writeln();
  return b.toString();
}

void main() {
  final manifest = CapabilityManifest.parse(
    File(_manifestPath).readAsStringSync(),
  );
  File(_outputPath).writeAsStringSync(renderMatrix(manifest));
  // ignore: avoid_print
  print('wrote $_outputPath');
}
