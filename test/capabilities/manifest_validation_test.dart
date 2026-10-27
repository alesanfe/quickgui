// Capability manifest gates (patterns: Capability Manifest, No Orphan
// Capability, CI Quality Gates 1-3).
//
// Invariants enforced here:
//  - the manifest parses and declares schema_version 1;
//  - capability ids are unique and namespaced;
//  - every capability carries an explicit GUI status;
//  - non-exposed statuses require a justification;
//  - implemented capabilities require entry points and either an adapter
//    method or a justification, plus at least one declared test surface
//    that exists on disk;
//  - every adapter_method exists on the VirtualizationBackend port;
//  - the weighted coverage score stays above the agreed floor.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/capabilities/capability.dart';
import 'package:quickgui/capabilities/capability_manifest.dart';

import '../../tool/generate_capability_matrix.dart';

final _manifestFile = File('assets/capabilities/capability_manifest.json');
final _portFile = File(
  'lib/features/machines/application/ports/virtualization_backend.dart',
);

CapabilityManifest _load() =>
    CapabilityManifest.parse(_manifestFile.readAsStringSync());

void main() {
  late CapabilityManifest manifest;
  late Map<String, dynamic> raw;

  setUpAll(() {
    expect(
      _manifestFile.existsSync(),
      isTrue,
      reason: 'capability_manifest.json is the coverage source of truth',
    );
    manifest = _load();
    raw = (jsonDecode(_manifestFile.readAsStringSync()) as Map)
        .cast<String, dynamic>();
  });

  test('schema v1, quickemu backend, unique namespaced ids', () {
    expect(manifest.schemaVersion, 1);
    expect(manifest.backendName, 'quickemu');
    expect(manifest.contractVersion, 1);

    final ids = manifest.capabilities.map((c) => c.id).toList();
    expect(
      ids.toSet(),
      hasLength(ids.length),
      reason: 'capability ids must be unique',
    );
    for (final id in ids) {
      expect(
        id,
        contains('.'),
        reason: '$id should be namespaced (domain.name)',
      );
    }
  });

  test('every capability has an explicit GUI status', () {
    final rawCaps = raw['capabilities'] as List;
    expect(rawCaps, hasLength(manifest.capabilities.length));
    for (final c in rawCaps) {
      final m = (c as Map).cast<String, dynamic>();
      expect(m['id'], isNotNull);
      expect(
        ((m['gui'] as Map?) ?? const {}).containsKey('status'),
        isTrue,
        reason: '${m['id']} has no explicit GUI support decision',
      );
    }
  });

  test('non-exposed statuses carry a justification', () {
    const needsJustification = {
      GuiCapabilityStatus.notApplicable,
      GuiCapabilityStatus.unsupported,
      GuiCapabilityStatus.planned,
      GuiCapabilityStatus.blocked,
      GuiCapabilityStatus.deprecated,
    };
    for (final c in manifest.capabilities) {
      if (!needsJustification.contains(c.gui.status)) continue;
      expect(
        c.gui.justification,
        isNotNull,
        reason: '${c.id} is ${c.gui.status.name} without justification',
      );
      expect(
        c.gui.justification,
        isNotEmpty,
        reason: '${c.id} justification must explain the decision',
      );
    }
  });

  test('implemented capabilities expose entry points and wiring', () {
    for (final c in manifest.capabilities) {
      if (c.gui.status != GuiCapabilityStatus.implemented) continue;
      expect(
        c.gui.entryPoints,
        isNotEmpty,
        reason: '${c.id} is implemented but has no entry point',
      );
      final hasWiring =
          c.architecture.adapterMethod != null || c.gui.justification != null;
      expect(
        hasWiring,
        isTrue,
        reason:
            '${c.id} is implemented with neither adapter_method nor justification',
      );
    }
  });

  test('implemented capabilities declare an existing test surface', () {
    for (final c in manifest.capabilities) {
      if (c.gui.status != GuiCapabilityStatus.implemented) continue;
      expect(
        c.testingSurfaces,
        isNotEmpty,
        reason: '${c.id} is implemented with no declared test surface',
      );
    }
    for (final c in manifest.capabilities) {
      for (final surface in c.testingSurfaces) {
        expect(
          File(surface).existsSync(),
          isTrue,
          reason: '${c.id} references missing test file $surface',
        );
      }
    }
  });

  test('every adapter_method exists on the VirtualizationBackend port', () {
    final portSource = _portFile.readAsStringSync();
    for (final c in manifest.capabilities) {
      final m = c.architecture.adapterMethod;
      if (m == null) continue;
      expect(
        portSource,
        contains(' $m('),
        reason:
            '${c.id} declares adapter_method $m which is not a VirtualizationBackend member',
      );
    }
  });

  test('weighted coverage score stays above the floor', () {
    // Floor guards silent capability regression; raise it as planned
    // capabilities land.
    expect(
      manifest.weightedScore,
      greaterThanOrEqualTo(0.70),
      reason: 'weighted capability coverage regressed',
    );
    // ignore: avoid_print
    print(
      'capability weighted score: '
      '${(manifest.weightedScore * 100).toStringAsFixed(1)}%',
    );
  });

  test('coverage matrix doc is in sync with the manifest', () {
    final doc = File('docs/capability_matrix.md');
    expect(
      doc.existsSync(),
      isTrue,
      reason: 'run tool/generate_capability_matrix.dart',
    );
    expect(
      doc.readAsStringSync(),
      renderMatrix(manifest),
      reason:
          'docs/capability_matrix.md is stale — regenerate it with '
          'dart run tool/generate_capability_matrix.dart',
    );
  });
}
