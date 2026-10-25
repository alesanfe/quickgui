import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/app/app.dart';

import '../support/harness/test_app.dart';

import 'package:quickgui/app/router/app_router.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);
  Future<void> pumpApp(WidgetTester tester, SettingsState initial) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostProbeProvider.overrideWithValue(FakeHostProbe()),
          backendProvider.overrideWithValue(
            FakeVirtualizationBackend()..vms = ['vm1'],
          ),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          initialSettingsProvider.overrideWithValue(initial),
        ],
        child: const App(localizationsDelegate: TestLocalizationsDelegate()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('app builds a MaterialApp with a fake backend', (tester) async {
    await pumpApp(tester, const SettingsState());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    final context = tester.element(find.byType(App));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/home',
    );
    container.read(appRouterProvider).go('/machines');
    await tester.pumpAndSettle();
    expect(find.byType(Manager), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets(
    'resizing across the breakpoint preserves route and branch state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(901, 800);
      addTearDown(tester.view.reset);
      await pumpApp(tester, const SettingsState());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(App)),
      );
      final router = container.read(appRouterProvider);
      router.go('/machines');
      await tester.pumpAndSettle();
      final managerState = tester.state(find.byType(Manager));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Settings'),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      for (final width in [
        649.0,
        650.0,
        651.0,
        1099.0,
        1100.0,
        1101.0,
        649.0,
      ]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        expect(
          find.byType(NavigationRail),
          width >= 650 ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          width < 650 ? findsOneWidget : findsNothing,
        );
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(
          ProviderScope.containerOf(tester.element(find.byType(App))),
          same(container),
        );
        expect(tester.takeException(), isNull);
      }
      router.go('/machines');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(Manager)), same(managerState));
    },
  );

  testWidgets('minimum window supports large text in the shell', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(692, 580);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, const SettingsState());
    expect(tester.takeException(), isNull, reason: 'machines at 2x text');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(App)),
    );
    final router = container.read(appRouterProvider);
    for (final path in ['/settings', '/activity']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, path);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('theme mode follows the settings provider', (tester) async {
    await pumpApp(tester, const SettingsState(darkMode: true));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.locale, const Locale('en'));
  });
}
