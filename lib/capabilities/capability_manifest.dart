/// Loader and queries for `assets/capabilities/capability_manifest.json` —
/// the human- and machine-readable source of truth for backend capability
/// coverage (pattern: Capability Manifest).
library;

import 'dart:convert';

import 'capability.dart';

/// The parsed manifest: backend identity plus every registered capability.
final class CapabilityManifest {
  const CapabilityManifest({
    required this.schemaVersion,
    required this.backendName,
    required this.provider,
    required this.upstream,
    required this.minimumVersion,
    required this.contractVersion,
    required this.capabilities,
  });

  factory CapabilityManifest.fromJson(Map<String, dynamic> j) {
    final backend = (j['backend'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CapabilityManifest(
      schemaVersion: j['schema_version'] as int? ?? 0,
      backendName: backend['name'] as String? ?? '',
      provider: backend['provider'] as String? ?? '',
      upstream: backend['upstream'] as String? ?? '',
      minimumVersion: backend['minimum_version'] as String? ?? '',
      contractVersion: backend['contract_version'] as int? ?? 0,
      capabilities: [
        for (final c in (j['capabilities'] as List?) ?? const [])
          Capability.fromJson((c as Map).cast<String, dynamic>()),
      ],
    );
  }

  factory CapabilityManifest.parse(String source) =>
      CapabilityManifest.fromJson(
        (jsonDecode(source) as Map).cast<String, dynamic>(),
      );

  final int schemaVersion;
  final String backendName;
  final String provider;
  final String upstream;
  final String minimumVersion;
  final int contractVersion;
  final List<Capability> capabilities;

  Capability? byId(String id) {
    for (final c in capabilities) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Every CLI flag claimed by at least one capability.
  Set<String> get coveredFlags => {
    for (final c in capabilities) ...c.backend.flags,
  };

  Map<GuiCapabilityStatus, List<Capability>> get byStatus {
    final m = <GuiCapabilityStatus, List<Capability>>{};
    for (final c in capabilities) {
      m.putIfAbsent(c.gui.status, () => []).add(c);
    }
    return m;
  }

  /// Weighted coverage score — implemented counts 1, partial 0.5,
  /// notApplicable entries are excluded entirely.
  double get weightedScore {
    var achieved = 0.0;
    var total = 0.0;
    for (final c in capabilities) {
      if (c.gui.status == GuiCapabilityStatus.notApplicable) continue;
      final w = c.criticality.weight.toDouble();
      total += w;
      achieved += switch (c.gui.status) {
        GuiCapabilityStatus.implemented => w,
        GuiCapabilityStatus.partiallyImplemented => w * 0.5,
        GuiCapabilityStatus.deprecated => w * 0.5,
        _ => 0.0,
      };
    }
    return total == 0 ? 0 : achieved / total;
  }
}
