/// Compatibility window for pre-contract Quickemu versions.
///
/// `runVmActionOrLegacy` may fall back to the legacy text protocol ONLY
/// when the backend cannot produce the v1 envelope at all (the four
/// envelope-absence codes in `isBackendEnvelopeMissing`). Every other
/// contract defect — incoherent exit code, wrong command, wrong field
/// types, truncated output — stays a typed failure.
///
/// Retirement: the fallback is kept until Quickgui requires
/// [minStructuredQuickemuVersion]; backends older than that show a
/// warning in Diagnostics rather than silently degrading. The plan is
/// to remove the legacy path once the supported window ends.
class LegacyPolicy {
  LegacyPolicy._();

  /// First Quickemu version that speaks the v1 structured contract.
  static const minStructuredQuickemuVersion = '4.9.7';

  /// Commands where a legacy fallback is still permitted. Contract-only
  /// operations (delete-plan, list-vms, capabilities...) already lack
  /// any legacy equivalent and never appear here.
  static const allowedCommands = {
    'start',
    'stop',
    'kill',
    'powerdown',
    'pause',
    'resume',
    'reset',
    'monitor-cmd',
    'send-keys',
    'screenshot',
    'doctor',
    'clone',
    'delete-vm',
    'delete-disk',
    'delete-plan',
    'disk-resize',
    'snapshot-create',
    'snapshot-apply',
    'snapshot-delete',
    'snapshot-list',
    'command',
  };

  /// Commands that must never fall back even on pre-contract backends —
  /// they exist only inside the structured contract.
  static const neverFallback = {
    'capabilities',
    'list-vms',
    'status',
    'vm-status',
  };
}
