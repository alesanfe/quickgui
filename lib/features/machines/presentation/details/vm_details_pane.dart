import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Persistent details pane for the selected VM — the Quickgui equivalent
/// of the details views in VirtualBox, virt-manager and GNOME Boxes
/// (VISTA competitive finding S-01).
///
/// Purely presentational: the Manager supplies the conf values and the
/// callbacks, which delegate to the same flows as the row actions.
class VmDetailsPane extends StatelessWidget {
  const VmDetailsPane({
    required this.name,
    required this.state,
    required this.conf,
    this.onStart,
    this.onStop,
    this.onConfigure,
    this.onSnapshots,
    this.onDelete,
    super.key,
  });

  /// VM name (basename of the .conf), empty when nothing is selected.
  final String name;

  /// Wire state: 'running' | 'paused' | 'stale' | 'stopped'.
  final String state;

  /// Selected .conf values, keyed by conf key
  /// (guest_os, ram, cpu_cores, disk_size, boot, network, display, viewer).
  final Map<String, String?> conf;

  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onConfigure;
  final VoidCallback? onSnapshots;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) {
      return Center(child: Text(context.t('Select a virtual machine')));
    }
    final active = state == 'running' || state == 'paused';
    final fields = <(String, String)>[
      (context.t('Guest OS'), conf['guest_os'] ?? '—'),
      (context.t('RAM'), conf['ram'] ?? '—'),
      (context.t('CPU cores'), conf['cpu_cores'] ?? '—'),
      (context.t('Disk size'), conf['disk_size'] ?? '—'),
      (context.t('Boot mode'), conf['boot'] ?? '—'),
      (context.t('Network'), conf['network'] ?? '—'),
      (context.t('Display'), conf['display'] ?? '—'),
      (context.t('Display viewer'), conf['viewer'] ?? '—'),
    ];
    final scheme = Theme.of(context).colorScheme;
    final (stateLabel, stateColor) = switch (state) {
      'running' => (context.t('Running'), Colors.green),
      'paused' => (context.t('Paused'), scheme.tertiary),
      'stale' => (
        context.t('Stale (process exited unexpectedly)'),
        scheme.error,
      ),
      _ => (context.t('Stopped'), scheme.onSurfaceVariant),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Chip(
                label: Text(stateLabel),
                side: BorderSide(color: stateColor),
                labelStyle: TextStyle(color: stateColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (active)
                FilledButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.power_settings_new),
                  label: Text(context.t('Shut down')),
                )
              else
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(context.t('Start')),
                ),
              OutlinedButton.icon(
                onPressed: onConfigure,
                icon: const Icon(Icons.settings),
                label: Text(context.t('Configure')),
              ),
              OutlinedButton.icon(
                onPressed: onSnapshots,
                icon: const Icon(Icons.history),
                label: Text(context.t('Snapshots')),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete),
                label: Text(context.t('Delete')),
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              ),
            ],
          ),
          const Divider(height: 32),
          for (final (label, value) in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      label,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
