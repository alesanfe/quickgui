// Covers the pure QG-050 domain: parsing the `vm.ip` data map into
// GuestIpInfo and classifying the answer — ready / noAddress /
// agentMissing / unsupported must stay distinguishable because the UI
// shows a different remediation for each.
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/guest_ip.dart';

void main() {
  group('GuestIpInfo.parse', () {
    test('ipv4+ipv6+iface -> ready with both families', () {
      final info = GuestIpInfo.parse({
        'vm': 'vm1',
        'ipv4': ['192.168.1.20'],
        'ipv6': ['fe80::1', 'fd00::2'],
        'iface': 'eth0',
      });
      expect(info.status, GuestIpStatus.ready);
      expect(info.ipv4, ['192.168.1.20']);
      expect(info.ipv6, ['fe80::1', 'fd00::2']);
      expect(info.iface, 'eth0');
    });

    test('empty lists -> noAddress, not unsupported', () {
      final info = GuestIpInfo.parse({
        'vm': 'vm1',
        'ipv4': <String>[],
        'ipv6': <String>[],
        'iface': '',
      });
      expect(info.status, GuestIpStatus.noAddress);
    });

    test('missing fields degrade to noAddress and empty iface', () {
      final info = GuestIpInfo.parse(const {});
      expect(info.status, GuestIpStatus.noAddress);
      expect(info.ipv4, isEmpty);
      expect(info.ipv6, isEmpty);
      expect(info.iface, '');
    });

    test('non-list address fields are dropped, not fatal', () {
      final info = GuestIpInfo.parse({
        'ipv4': '192.168.1.20',
        'ipv6': 42,
        'iface': null,
      });
      expect(info.status, GuestIpStatus.noAddress);
    });

    test('ipv6-only answer is still ready', () {
      final info = GuestIpInfo.parse({
        'ipv4': <String>[],
        'ipv6': ['fd00::5'],
      });
      expect(info.status, GuestIpStatus.ready);
      expect(info.ipv6, ['fd00::5']);
    });

    test('address entries are stringified defensively', () {
      final info = GuestIpInfo.parse({
        'ipv4': [12345],
      });
      expect(info.status, GuestIpStatus.ready);
      expect(info.ipv4, ['12345']);
    });
  });

  group('agentMissingCodes', () {
    // These are the codes tools/quickemu-cli/guest.go emits when the
    // QGA channel or agent is absent — the UI maps them to the
    // "install qemu-guest-agent" hint rather than a retry nudge.
    for (final code in [
      'channel_missing',
      'channel_unreachable',
      'agent_not_ready',
      'connection_lost',
    ]) {
      test('$code is classified as agent missing', () {
        expect(GuestIpInfo.agentMissingCodes, contains(code));
      });
    }

    test('plain timeout is NOT agent-missing — it may resolve itself', () {
      expect(GuestIpInfo.agentMissingCodes, isNot(contains('timeout')));
    });
  });
}
