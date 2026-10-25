import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/app/shell/app_shell.dart';
import 'package:quickgui/features/home/presentation/dashboard_page.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/create/presentation/create_page.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/presentation/details/vm_page.dart';
import 'package:quickgui/features/machines/presentation/details/vm_settings_page.dart';
import 'package:quickgui/features/settings/presentation/settings_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/machines',
                builder: (context, state) => const Manager(),
                routes: [
                  GoRoute(
                    path: ':name',
                    builder: (context, state) =>
                        VmPage(vmName: state.pathParameters['name']!),
                    routes: [
                      GoRoute(
                        path: 'settings',
                        builder: (context, state) => VmSettingsPage(
                          vmName: state.pathParameters['name']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/create',
                builder: (context, state) => const CreatePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activity',
                builder: (context, state) => const ActivityPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/diagnostics',
                builder: (context, state) => const DiagnosticsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Centralised route construction for Navigator pushes.
PageRoute<T> appRoute<T>(Widget page) =>
    MaterialPageRoute<T>(builder: (_) => page);
