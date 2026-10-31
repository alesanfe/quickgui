/// Guest network addresses reported by the QEMU Guest Agent through
/// `quickemu guest ip` (backend command `vm.ip`, QG-050).
///
/// The backend answers `{vm, ipv4: [...], ipv6: [...], iface}` on
/// success; typed envelope errors distinguish "agent not installed"
/// (`channel_missing`, `agent_not_ready`) from "no address yet".
enum GuestIpStatus {
  /// At least one address was reported.
  ready,

  /// The agent answered but reported no address — the guest is
  /// probably still booting or the interface is down.
  noAddress,

  /// The agent channel is missing or the agent is not answering —
  /// qemu-guest-agent is not installed/running (or `qga=off`).
  agentMissing,

  /// The backend does not speak the guest verbs at all.
  unsupported,
}

class GuestIpInfo {
  const GuestIpInfo({
    required this.status,
    this.ipv4 = const [],
    this.ipv6 = const [],
    this.iface = '',
  });

  final GuestIpStatus status;

  /// Reported addresses, split by family for display grouping.
  final List<String> ipv4;
  final List<String> ipv6;

  /// Interface the query was scoped to ('' = all).
  final String iface;

  /// Parses the `vm.ip` data map. Anything absent degrades to empty
  /// lists — a partial answer still beats no answer.
  factory GuestIpInfo.parse(Map<String, dynamic> data) {
    List<String> listOf(Object? raw) =>
        raw is List ? [for (final a in raw) '$a'] : const [];
    final v4 = listOf(data['ipv4']);
    final v6 = listOf(data['ipv6']);
    return GuestIpInfo(
      status: v4.isEmpty && v6.isEmpty
          ? GuestIpStatus.noAddress
          : GuestIpStatus.ready,
      ipv4: v4,
      ipv6: v6,
      iface: '${data['iface'] ?? ''}',
    );
  }

  /// QGA error codes that mean "agent not there" rather than
  /// "query failed" — these get the install hint, not a retry nudge.
  static const agentMissingCodes = {
    'channel_missing',
    'channel_unreachable',
    'agent_not_ready',
    'connection_lost',
  };
}
