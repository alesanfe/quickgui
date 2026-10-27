/// Capability model for the backend capability-to-GUI contract.
///
/// Every public capability of the quickemu/quickget CLI surface must be
/// registered in `assets/capabilities/capability_manifest.json` and carry an
/// explicit GUI support decision — the "no orphan capability" invariant is
/// enforced by `test/capabilities/`.
library;

/// GUI support decision for a backend capability (pattern: Backend
/// Capability-to-GUI Contract).
enum GuiCapabilityStatus {
  /// Fully discoverable, usable and covered by tests.
  implemented,

  /// Partially available — some parameters, states or errors are missing.
  partiallyImplemented,

  /// Accepted on the roadmap, not built yet.
  planned,

  /// Depends on backend/platform changes outside quickgui.
  blocked,

  /// Deliberate decision not to expose it.
  unsupported,

  /// Internal detail with no user-observable action.
  notApplicable,

  /// Kept temporarily for compatibility.
  deprecated,
}

/// How strongly the feature needs a GUI surface.
enum CapabilityRequirement { required, recommended, optional, notApplicable }

/// Weight bucket used by the weighted coverage score.
enum Criticality {
  critical(8),
  high(5),
  medium(3),
  low(1);

  Criticality(this.weight);
  final int weight;
}

/// Backend-side identity of a capability: which executable and which
/// operation/flags implement it.
final class CapabilityBackend {
  const CapabilityBackend({
    required this.executable,
    required this.operation,
    required this.flags,
  });

  factory CapabilityBackend.fromJson(Map<String, dynamic> j) =>
      CapabilityBackend(
        executable: j['executable'] as String? ?? 'quickemu',
        operation: j['operation'] as String? ?? '',
        flags: [for (final f in (j['flags'] as List?) ?? const []) f as String],
      );

  final String executable;
  final String operation;
  final List<String> flags;
}

/// GUI-side decision: requirement, status, entry points and (when the
/// capability is not implemented) a mandatory justification.
final class CapabilityGui {
  const CapabilityGui({
    required this.requirement,
    required this.status,
    required this.entryPoints,
    this.justification,
  });

  factory CapabilityGui.fromJson(Map<String, dynamic> j) => CapabilityGui(
    requirement: CapabilityRequirement.values.byName(
      _requirementName(j['requirement'] as String?),
    ),
    status: GuiCapabilityStatus.values.byName(
      _statusName(j['status'] as String?),
    ),
    entryPoints: [
      for (final e in (j['entry_points'] as List?) ?? const []) e as String,
    ],
    justification: j['justification'] as String?,
  );

  static String _requirementName(String? raw) {
    switch (raw) {
      case 'not_applicable':
      case 'notApplicable':
        return 'notApplicable';
      default:
        return raw ?? 'notApplicable';
    }
  }

  static String _statusName(String? raw) {
    switch (raw) {
      case 'partially_implemented':
      case 'partiallyImplemented':
        return 'partiallyImplemented';
      case 'not_applicable':
      case 'notApplicable':
        return 'notApplicable';
      default:
        return raw ?? 'notApplicable';
    }
  }

  final CapabilityRequirement requirement;
  final GuiCapabilityStatus status;
  final List<String> entryPoints;
  final String? justification;

  bool get exposesUserAction =>
      status == GuiCapabilityStatus.implemented ||
      status == GuiCapabilityStatus.partiallyImplemented;
}

/// Architecture wiring: which `VirtualizationBackend` port method carries
/// the capability to the backend boundary.
final class CapabilityArchitecture {
  const CapabilityArchitecture({this.adapterMethod});

  factory CapabilityArchitecture.fromJson(Map<String, dynamic>? j) =>
      CapabilityArchitecture(adapterMethod: j?['adapter_method'] as String?);

  final String? adapterMethod;
}

/// A single registered capability.
final class Capability {
  const Capability({
    required this.id,
    required this.domain,
    required this.title,
    required this.criticality,
    required this.backend,
    required this.gui,
    required this.architecture,
    required this.testingSurfaces,
  });

  factory Capability.fromJson(Map<String, dynamic> j) => Capability(
    id: j['id'] as String,
    domain: j['domain'] as String? ?? 'misc',
    title: j['title'] as String? ?? '',
    criticality: Criticality.values.byName(
      j['criticality'] as String? ?? 'low',
    ),
    backend: CapabilityBackend.fromJson(
      (j['backend'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    gui: CapabilityGui.fromJson(
      (j['gui'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    architecture: CapabilityArchitecture.fromJson(
      (j['architecture'] as Map?)?.cast<String, dynamic>(),
    ),
    testingSurfaces: [
      for (final s
          in ((j['testing'] as Map?)?['surfaces'] as List?) ?? const [])
        s as String,
    ],
  );

  final String id;
  final String domain;
  final String title;
  final Criticality criticality;
  final CapabilityBackend backend;
  final CapabilityGui gui;
  final CapabilityArchitecture architecture;
  final List<String> testingSurfaces;
}
