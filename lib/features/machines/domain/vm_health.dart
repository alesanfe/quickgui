import 'package:quickgui/features/machines/domain/guest_ip.dart';

/// Severity of one health indicator — maps to icon + colour in the
/// presentation layer; the domain stays widget-free (QG-041).
enum HealthLevel { ok, info, warn, bad }

class HealthCheck {
  const HealthCheck(this.label, this.level, this.detail, [this.detailArgs]);

  /// English label — presentation translates via context.t.
  final String label;
  final HealthLevel level;

  /// English detail — may contain `{0}`… placeholders filled by
  /// [detailArgs] so the msgid stays translatable.
  final String detail;
  final List<String>? detailArgs;
}

/// Aggregates per-VM health signals into a small, ordered checklist:
/// runtime state, guest-agent reachability, forwarded-port readiness,
/// host headroom and recent journal issues. Pure so the mapping can
/// be asserted without pumping widgets.
class VmHealthReport {
  VmHealthReport._();

  static const int lowDiskBadBytes = 5 * 1024 * 1024 * 1024; // 5 GiB
  static const int lowDiskWarnBytes = 20 * 1024 * 1024 * 1024; // 20 GiB

  static List<HealthCheck> build({
    required String state,
    required GuestIpStatus agent,
    required bool portsPresent,
    required int? freeBytes,
    required int recentIssues,
  }) {
    final running = state == 'running' || state == 'paused';
    final checks = <HealthCheck>[
      HealthCheck(
        'Machine state',
        switch (state) {
          'stale' => HealthLevel.bad,
          'running' => HealthLevel.ok,
          _ => HealthLevel.info,
        },
        switch (state) {
          'stale' => 'Stale — the process exited unexpectedly.',
          'running' => 'Running',
          'paused' => 'Paused',
          _ => 'Stopped',
        },
      ),
    ];
    if (running) {
      checks.addAll([
        HealthCheck(
          'Guest agent',
          switch (agent) {
            GuestIpStatus.ready => HealthLevel.ok,
            GuestIpStatus.noAddress ||
            GuestIpStatus.agentMissing => HealthLevel.warn,
            GuestIpStatus.unsupported => HealthLevel.info,
          },
          switch (agent) {
            GuestIpStatus.ready => 'Answering — network details available.',
            GuestIpStatus.noAddress => 'Up, but no network address yet.',
            GuestIpStatus.agentMissing =>
              'Not answering — qemu-guest-agent missing or stopped.',
            GuestIpStatus.unsupported => 'This backend cannot query the agent.',
          },
        ),
        HealthCheck(
          'Forwarded ports',
          portsPresent ? HealthLevel.ok : HealthLevel.warn,
          portsPresent
              ? 'SPICE/SSH port forwards registered.'
              : 'No forwarded ports registered yet.',
        ),
      ]);
    }
    checks.add(
      HealthCheck(
        'Host disk space',
        switch (freeBytes) {
          null => HealthLevel.info,
          < lowDiskBadBytes => HealthLevel.bad,
          < lowDiskWarnBytes => HealthLevel.warn,
          _ => HealthLevel.ok,
        },
        freeBytes == null ? 'Free space unknown.' : '{0} GiB free.',
        freeBytes == null
            ? null
            : [(freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)],
      ),
    );
    checks.add(
      HealthCheck(
        'Recent issues',
        recentIssues == 0 ? HealthLevel.ok : HealthLevel.warn,
        recentIssues == 0
            ? 'No crashes or failed operations in the last 24 h.'
            : '{0} journal event(s) need attention (24 h).',
        recentIssues == 0 ? null : ['$recentIssues'],
      ),
    );
    return checks;
  }
}
