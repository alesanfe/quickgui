import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/app/app.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester, SettingsState initial) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(
              FakeVirtualizationBackend()..vms = ['vm1'],
            ),
            preferencesRepositoryProvider.overrideWithValue(
              FakePreferencesRepository(),
            ),
            initialSettingsProvider.overrideWithValue(initial),
          ],
          child: const App(),
        ),
      );

  testWidgets('app builds a MaterialApp with a fake backend', (tester) async {
    await pumpApp(tester, const SettingsState());
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('theme mode follows the settings provider', (tester) async {
    await pumpApp(tester, const SettingsState(darkMode: true));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.locale, const Locale('en'));
  });
}
