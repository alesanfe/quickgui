import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/machines/domain/guest_ip.dart';
import 'package:quickgui/features/machines/domain/vm_health.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';

/// At-a-glance health summary for one VM (QG-041): state, guest-agent
/// reachability, forwarded-port registration, host headroom and
/// recent journal issues. Purely informational — actions still live
/// in the Console/Connection surfaces.
class VmHealthCard extends ConsumerWidget {
  const VmHealthCard({
    required this.vm,
    required this.confPath,
    required this.state,
    super.key,
  });

  final String vm;
  final String confPath;
  final String state;

  (IconData, Color) _icon(HealthLevel level, ColorScheme scheme) =>
      switch (level) {
        HealthLevel.ok => (Icons.check_circle_outline, Colors.green),
        HealthLevel.info => (Icons.info_outline, scheme.onSurfaceVariant),
        HealthLevel.warn => (Icons.warning_amber_outlined, Colors.orange),
        HealthLevel.bad => (Icons.error_outline, scheme.error),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(guestIpProvider(confPath)).asData?.value.status;
    final freeBytes = ref.watch(hostFreeSpaceProvider).asData?.value;
    final issues = ref.watch(vmRecentIssuesProvider(vm)).asData?.value ?? 0;
    final running = state == 'running' || state == 'paused';
    final portsPresent = File(p.join(p.dirname(confPath), vm, '$vm.ports'))
        .existsSync();

    final checks = VmHealthReport.build(
      state: state,
      agent: agent ?? GuestIpStatus.unsupported,
      portsPresent: running && portsPresent,
      freeBytes: freeBytes,
      recentIssues: issues,
    );

    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: Text(context.t('Health')),
            dense: true,
          ),
          const Divider(height: 1),
          for (final check in checks)
            Builder(
              builder: (context) {
                final (icon, color) = _icon(check.level, scheme);
                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: color, size: 20),
                  title: Text(context.t(check.label)),
                  subtitle: Text(
                    context.t(check.detail, args: check.detailArgs),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
