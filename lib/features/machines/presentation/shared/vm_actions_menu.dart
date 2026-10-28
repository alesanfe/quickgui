import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Overflow menu for a VM: converts the builder's flat
/// PopupMenuEntry list into a grouped menu with section headers
/// (Configure / Lifecycle / Maintenance / Snapshots / Delete).
class VmActionsMenu extends StatelessWidget {
  const VmActionsMenu({
    required this.icon,
    required this.tooltip,
    required this.constraints,
    required this.onSelected,
    required this.itemBuilder,
    super.key,
  });

  final Widget icon;
  final String tooltip;
  final BoxConstraints constraints;
  final void Function(String) onSelected;
  final List<PopupMenuEntry<String>> Function(BuildContext) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final entries = itemBuilder(context)
        .whereType<PopupMenuItem<String>>()
        .toList();
    Widget item(PopupMenuItem<String> entry) => MenuItemButton(
      onPressed: !entry.enabled || entry.value == null
          ? null
          : () => onSelected(entry.value!),
      child: SizedBox(width: 240, child: entry.child),
    );
    Widget header(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
    const groups = [
      (
        'Configure',
        {
          'config',
          'resources',
          'display',
          'bootnet',
          'devices',
          'shared',
          'settings',
        },
      ),
      ('Lifecycle', {'pause', 'resume', 'screenshot', 'send-keys', 'reset'}),
      (
        'Maintenance',
        {
          'folder',
          'doctor',
          'verify',
          'resize',
          'clone',
          'export',
          'migrate-toml',
          'move',
          'hotplug',
          'backup',
        },
      ),
    ];
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        tooltip: tooltip,
        icon: icon,
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      menuChildren: [
        for (final group in groups) ...[
          if (entries.any((e) => group.$2.contains(e.value))) ...[
            header(context.t(group.$1)),
            for (final entry in entries.where(
              (e) => group.$2.contains(e.value),
            ))
              item(entry),
          ],
        ],
        // Safety net: values not claimed by any group still render —
        // silently dropping them makes menu entries unreachable.
        for (final entry in entries.where(
          (e) =>
              e.value != 'snapshot' &&
              e.value != 'delete' &&
              !groups.any((g) => g.$2.contains(e.value)),
        ))
          item(entry),
        if (entries.any((e) => e.value == 'snapshot')) ...[
          const Divider(),
          for (final entry in entries.where((e) => e.value == 'snapshot'))
            item(entry),
        ],
        if (entries.any((e) => e.value == 'delete')) ...[
          const Divider(),
          for (final entry in entries.where((e) => e.value == 'delete'))
            item(entry),
        ],
      ],
    );
  }
}
