import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/widgets/dependency_warning.dart';

/// Persistent application shell: a NavigationRail on wide windows and a
/// NavigationBar on narrow ones, hosting the six main sections.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    windowManager.setTitle(
      context.t('Quickgui : a Flutter frontend for Quickget and Quickemu'),
    );
  }

  List<({IconData icon, String label})> _destinations(BuildContext context) => [
    (icon: Icons.home_outlined, label: context.t('Home')),
    (icon: Icons.computer, label: context.t('Machines')),
    (icon: Icons.add_circle_outline, label: context.t('Create')),
    (icon: Icons.notifications_none, label: context.t('Activity')),
    (icon: Icons.health_and_safety, label: context.t('Diagnostics')),
    (icon: Icons.settings, label: context.t('Settings')),
  ];

  void _go(int index) => widget.shell.goBranch(
    index,
    initialLocation: index == widget.shell.currentIndex,
  );

  Widget _activityIcon(IconData icon) {
    final running = ref.watch(runningOperationsProvider);
    return Badge.count(
      count: running,
      isLabelVisible: running > 0,
      child: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations(context);
    final selected = widget.shell.currentIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        final expanded = constraints.maxWidth >= 1100;
        final body = Column(
          children: [
            const DependencyWarning(),
            Expanded(child: widget.shell),
          ],
        );
        return Scaffold(
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selected,
                      onDestinationSelected: _go,
                      extended: expanded,
                      labelType: expanded
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      leading: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Image.asset(
                          'assets/images/logo_pink.png',
                          height: 48,
                          semanticLabel: 'Quickgui',
                        ),
                      ),
                      destinations: [
                        for (final (i, d) in destinations.indexed)
                          NavigationRailDestination(
                            icon: i == 3 ? _activityIcon(d.icon) : Icon(d.icon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: _go,
                  destinations: [
                    for (final (i, d) in destinations.indexed)
                      NavigationDestination(
                        icon: i == 3 ? _activityIcon(d.icon) : Icon(d.icon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
