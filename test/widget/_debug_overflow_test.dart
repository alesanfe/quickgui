import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/app/shell/app_shell.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_preferences_repository.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  testWidgets('shell alone at 692x580 with 2x text', (tester) async {
    tester.view.physicalSize = const Size(692, 580);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            for (final p in ['/a', '/b', '/c', '/d', '/e', '/f'])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: p,
                    builder: (_, _) => const Center(child: Text('x')),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [TestLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
