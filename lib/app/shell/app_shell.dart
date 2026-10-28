import 'dart:async';
import 'dart:io';

import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import 'package:quickgui/features/activity/application/download_notification_policy.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/infrastructure/tray/app_tray.dart';
import 'package:quickgui/shared/widgets/dependency_warning.dart';
import 'package:quickgui/shared/widgets/shortcuts_dialog.dart';

/// Persistent application shell: a NavigationRail on wide windows and a
/// NavigationBar on narrow ones, hosting the six main sections.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // desktop_notifications talks to a Linux session D-Bus; on other
  // platforms constructing the client throws (no UID).
  final NotificationsClient? _notificationsClient = Platform.isLinux
      ? NotificationsClient()
      : null;
  final DownloadNotificationPolicy _notificationPolicy =
      DownloadNotificationPolicy();
  AppTray? _tray;

  @override
  void dispose() {
    unawaited(_tray?.dispose() ?? Future.value());
    _notificationsClient?.close();
    super.dispose();
  }

  /// Fires a desktop notification when a download reaches a terminal
  /// state. The activity history is the canonical record — each finished
  /// op appears there exactly once, so dedupe by id and notify only the
  /// new entries. Honours the "notify when downloads finish" preference.
  void _onActivityChanged() {
    final client = _notificationsClient;
    if (client == null) return;
    if (!ref.read(uiPreferencesProvider).notifyOnComplete) return;
    for (final entry in _notificationPolicy.pending(
      ref.read(activityProvider).history,
    )) {
      final (title, body) = switch (entry.status) {
        OperationStatus.succeeded => (
          context.t('Download finished.'),
          context.t('Download of {0} has completed.', args: [entry.target]),
        ),
        OperationStatus.cancelled => (
          context.t('Download cancelled'),
          context.t('Download of {0} has been canceled.', args: [entry.target]),
        ),
        OperationStatus.failed => (
          context.t('Download failed'),
          context.t('Download of {0} has failed.', args: [entry.target]),
        ),
        _ => (null, null),
      };
      if (title == null || body == null) continue;
      // Notifications are best-effort: a missing session bus
      // (headless/SSH/container) must not break the app. The client
      // reports D-Bus errors through an internal stream, so a guarded
      // zone is needed on top of the try/catch.
      unawaited(
        runZonedGuarded(() async {
          try {
            await client.notify(
              title,
              body: body,
              appName: 'Quickgui',
              expireTimeoutMs: 10000 /* 10 seconds */,
            );
          } catch (_) {}
        }, (_, _) {}),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    windowManager.setTitle(
      context.t('Quickgui : a Flutter frontend for Quickget and Quickemu'),
    );
    // Tray labels need a Localizations context, unavailable in initState.
    _tray ??= AppTray(
      onRefresh: () {
        ref.invalidate(vmLibraryProvider);
        ref.invalidate(backendInventoryProvider);
      },
      showLabel: context.t('Show QuickGUI'),
      refreshLabel: context.t('Refresh'),
      quitLabel: context.t('Quit'),
    )..init().ignore(); // best-effort — failure leaves the app tray-less
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
    ref.listen(activityProvider, (_, _) => _onActivityChanged());
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
        // Ctrl+1..6 jumps between the six sections from anywhere in the
        // app — section keys are not consumed by text fields, so they
        // bubble up to this root-level binding.
        return CallbackShortcuts(
          bindings: {
            for (final (i, _) in destinations.indexed)
              SingleActivator(
                LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
                control: true,
              ): () =>
                  _go(i),
            const SingleActivator(LogicalKeyboardKey.f1): () =>
                ShortcutsDialog.show(context),
          },
          child: Scaffold(
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
                              icon: i == 3
                                  ? _activityIcon(d.icon)
                                  : Icon(d.icon),
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
          ),
        );
      },
    );
  }
}
