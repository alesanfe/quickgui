import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// A labelled cascading submenu inside [VmActionsMenu] — low-frequency
/// actions group under it so the root menu fits the window.
class _Submenu {
  const _Submenu(this.label, this.values, this.icon);
  final String label;
  final Set<String> values;
  final IconData icon;
}

/// Overflow menu for a VM: converts the builder's flat
/// PopupMenuEntry list into a grouped menu with section headers
/// (Configure / Lifecycle / Maintenance / Snapshots / Delete).
/// Rarely-used clusters cascade into submenus so the root menu
/// stays short enough to show without scrolling.
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
    // Compact density keeps the full menu inside the window: less
    // vertical padding per row means the destructive Delete stays
    // visible without scrolling at ~800px heights.
    Widget item(PopupMenuItem<String> entry) => MenuItemButton(
      style: MenuItemButton.styleFrom(
        visualDensity: const VisualDensity(vertical: -2),
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 32),
      ),
      onPressed: !entry.enabled || entry.value == null
          ? null
          : () => onSelected(entry.value!),
      child: SizedBox(
        width: 240,
        // Strip the default vertical tile padding — the menu is dense
        // by design so every entry fits the window height.
        child: ListTileTheme(
          data: const ListTileThemeData(
            minVerticalPadding: 0,
            minTileHeight: 32,
          ),
          child: entry.child ?? const SizedBox(),
        ),
      ),
    );
    Widget header(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
    // A group is (header label, members); a member is either a flat
    // value or a _Submenu that cascades the listed values one level.
    // Snapshots/backups/exports share a Data & recovery group so the
    // snapshot entry is no longer an orphan at the bottom (QGUI-MENU-001).
    const groups = <(String, List<Object>)>[
      (
        'Configure',
        [
          'settings',
          _Submenu('Hardware', {
            'resources',
            'display',
            'bootnet',
            'devices',
            'shared',
          }, Icons.memory),
        ],
      ),
      (
        'Lifecycle',
        [
          'start',
          'pause',
          'resume',
          _Submenu('Guest & power', {
            'reset',
            'suspend',
            'screenshot',
            'send-keys',
            'guest-agent',
            'serial-console',
            'monitor-console',
          }, Icons.terminal),
          _Submenu('Start options', {
            'start-profile',
            'start-offline',
            'launch-plan',
          }, Icons.tune),
        ],
      ),
      ('Data & recovery', ['snapshot', 'backup', 'export']),
      (
        'Maintenance',
        [
          'resize',
          'clone',
          _Submenu('Advanced', {
            'folder',
            'config',
            'doctor',
            'verify',
            'migrate-toml',
            'move',
            'hotplug',
            'shortcut',
            'remove-shortcut',
          }, Icons.handyman),
        ],
      ),
    ];
    bool claimed(String? value) => groups.any(
      (g) => g.$2.any(
        (m) => m is _Submenu ? m.values.contains(value) : m == value,
      ),
    );
    List<Widget> groupChildren(List<Object> members) => [
      for (final member in members)
        if (member is _Submenu) ...[
          if (entries.any((e) => member.values.contains(e.value)))
            SubmenuButton(
              style: SubmenuButton.styleFrom(
                visualDensity: const VisualDensity(vertical: -2),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
              leadingIcon: Icon(member.icon),
              menuChildren: [
                for (final entry in entries.where(
                  (e) => member.values.contains(e.value),
                ))
                  item(entry),
              ],
              child: SizedBox(width: 240, child: Text(context.t(member.label))),
            ),
        ] else ...[
          for (final entry in entries.where((e) => e.value == member))
            // Slight indent under the group header makes the visual
            // hierarchy readable without relying on order alone
            // (QGUI-MENU-002).
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: item(entry),
            ),
        ],
    ];
    return MenuAnchor(
      // Lift the menu so its top clears the anchor row: the panel can
      // then extend to the viewport bottom and the full grouped list —
      // including Snapshots and Delete — shows without scrolling.
      alignmentOffset: const Offset(0, -112),
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
          if (entries.any(
            (e) => group.$2.any(
              (m) => m is _Submenu ? m.values.contains(e.value) : m == e.value,
            ),
          )) ...[
            header(context.t(group.$1)),
            ...groupChildren(group.$2),
          ],
        ],
        // Safety net: values not claimed by any group still render —
        // silently dropping them makes menu entries unreachable.
        for (final entry in entries.where(
          (e) => e.value != 'delete' && !claimed(e.value),
        ))
          item(entry),
        if (entries.any((e) => e.value == 'delete')) ...[
          const Divider(height: 8),
          for (final entry in entries.where((e) => e.value == 'delete'))
            item(entry),
        ],
      ],
    );
  }
}
