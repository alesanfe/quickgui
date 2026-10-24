import 'package:json_annotation/json_annotation.dart';

/// Lifecycle status of a VM as reported by the backend (contract v1:
/// `vm-status` → running|stopped, `vm-list` → running|stopped|stale).
@JsonEnum(alwaysCreate: true)
enum VmStatus {
  running,
  stopped,
  paused,

  /// A pid file exists but the process is gone.
  stale,
  @JsonValue('unknown')
  unknown;

  /// Lenient mapping for wire values: unknown strings never throw.
  static VmStatus fromWire(Object? value) => switch (value) {
    'running' => VmStatus.running,
    'stopped' => VmStatus.stopped,
    'paused' => VmStatus.paused,
    'stale' => VmStatus.stale,
    _ => VmStatus.unknown,
  };

  String toWire() => name;
}
