// Covers the health-check mapping (QG-041): every signal renders a
// deterministic level so the card can trust the domain output.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/guest_ip.dart';
import 'package:quickgui/features/machines/domain/vm_health.dart';

List<HealthCheck> report({
  String state = 'running',
  GuestIpStatus agent = GuestIpStatus.ready,
  bool ports = true,
  int? free = 40 * 1024 * 1024 * 1024,
  int issues = 0,
}) => VmHealthReport.build(
  state: state,
  agent: agent,
  portsPresent: ports,
  freeBytes: free,
  recentIssues: issues,
);

void main() {
  HealthCheck check(List<HealthCheck> checks, String label) =>
      checks.singleWhere((c) => c.label == label);

  test('healthy running VM is all ok/info', () {
    final checks = report();
    expect(
      checks.every(
        (c) => c.level == HealthLevel.ok || c.level == HealthLevel.info,
      ),
      isTrue,
    );
    expect(check(checks, 'Machine state').level, HealthLevel.ok);
    expect(check(checks, 'Guest agent').level, HealthLevel.ok);
  });

  test('stopped VM skips agent/port checks entirely', () {
    final checks = report(state: 'stopped');
    expect(check(checks, 'Machine state').level, HealthLevel.info);
    expect(checks.any((c) => c.label == 'Guest agent'), isFalse);
    expect(checks.any((c) => c.label == 'Forwarded ports'), isFalse);
  });

  test('stale state is bad — it means an unexpected exit', () {
    expect(
      check(report(state: 'stale'), 'Machine state').level,
      HealthLevel.bad,
    );
  });

  test('paused keeps agent checks but shows info state', () {
    final checks = report(state: 'paused', agent: GuestIpStatus.noAddress);
    expect(check(checks, 'Machine state').level, HealthLevel.info);
    expect(check(checks, 'Guest agent').level, HealthLevel.warn);
  });

  test('missing agent warns, unsupported only informs', () {
    expect(
      check(report(agent: GuestIpStatus.agentMissing), 'Guest agent').level,
      HealthLevel.warn,
    );
    expect(
      check(report(agent: GuestIpStatus.unsupported), 'Guest agent').level,
      HealthLevel.info,
    );
  });

  test('absent ports file warns while running', () {
    expect(
      check(report(ports: false), 'Forwarded ports').level,
      HealthLevel.warn,
    );
  });

  test('disk space: <5 GiB bad, <20 GiB warn, else ok, null informs', () {
    expect(
      check(report(free: 4 * 1024 * 1024 * 1024), 'Host disk space').level,
      HealthLevel.bad,
    );
    expect(
      check(report(free: 10 * 1024 * 1024 * 1024), 'Host disk space').level,
      HealthLevel.warn,
    );
    expect(
      check(report(), 'Host disk space').level,
      HealthLevel.ok,
    );
    expect(
      check(report(free: null), 'Host disk space').level,
      HealthLevel.info,
    );
  });

  test('recent journal issues warn, none is ok', () {
    expect(check(report(issues: 3), 'Recent issues').level, HealthLevel.warn);
    expect(check(report(), 'Recent issues').detail, contains('24 h'));
  });
}
