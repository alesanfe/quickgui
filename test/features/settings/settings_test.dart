import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/settings/application/load_settings.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import '../../support/fakes/fake_preferences_repository.dart';

void main() {
  const supported = ['en', 'es', 'fr', 'pt_BR'];

  group('SettingsState.normalizeLocale', () {
    test('strips the encoding and keeps an exact match', () {
      expect(SettingsState.normalizeLocale('pt_BR.UTF-8', supported), 'pt_BR');
    });
    test('falls back to the language code', () {
      expect(SettingsState.normalizeLocale('es_ES.UTF-8', supported), 'es');
    });
    test('falls back to en for unsupported locales', () {
      expect(SettingsState.normalizeLocale('xx_YY', supported), 'en');
    });
    test('exposes language and country codes', () {
      const s = SettingsState(locale: 'pt_BR');
      expect(s.languageCode, 'pt');
      expect(s.countryCode, 'BR');
      expect(const SettingsState().countryCode, isNull);
    });
  });

  group('LoadSettings', () {
    test('reads persisted values', () async {
      final prefs = FakePreferencesRepository()
        ..store[SettingsKeys.darkMode] = true
        ..store[SettingsKeys.locale] = 'fr';
      final r = await LoadSettings(
        prefs,
        supportedLocales: supported,
        systemLocale: 'en_US.UTF-8',
      )();
      expect(
        (r as Ok<SettingsState>).value,
        const SettingsState(darkMode: true, locale: 'fr'),
      );
    });

    test('uses the normalised system locale when nothing is stored', () async {
      final r = await LoadSettings(
        FakePreferencesRepository(),
        supportedLocales: supported,
        systemLocale: 'es_MX.UTF-8',
      )();
      expect((r as Ok<SettingsState>).value, const SettingsState(locale: 'es'));
    });
  });

  group('SettingsController', () {
    late FakePreferencesRepository prefs;
    late ProviderContainer container;

    setUp(() {
      prefs = FakePreferencesRepository();
      container = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(prefs),
          initialSettingsProvider.overrideWithValue(
            const SettingsState(locale: 'es'),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test('starts from the initial settings', () {
      expect(container.read(settingsProvider).locale, 'es');
    });

    test('setDarkMode updates state and persists', () async {
      container.read(settingsProvider.notifier).setDarkMode(enabled: true);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(settingsProvider).darkMode, isTrue);
      expect(prefs.store[SettingsKeys.darkMode], true);
      expect(prefs.store[SettingsKeys.locale], 'es');
    });

    test('setLocale updates state and persists', () async {
      container.read(settingsProvider.notifier).setLocale('fr');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(settingsProvider).locale, 'fr');
      expect(prefs.store[SettingsKeys.locale], 'fr');
    });
  });
}
