import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/features/settings/application/update_settings.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/core/persistence/preferences_repository.dart';
import 'package:quickgui/infrastructure/persistence/shared_preferences_repository.dart';

/// Preference store; overridden with a fake in tests.
final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>((ref) => SharedPreferencesRepository());

/// Settings loaded before `runApp` (see main.dart) so the first frame
/// already has the right theme and locale.
final Provider<SettingsState> initialSettingsProvider = Provider<SettingsState>(
  (ref) => const SettingsState(),
);

/// App settings state + mutations; every change is persisted.
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => ref.read(initialSettingsProvider);

  void setDarkMode({required bool enabled}) =>
      _update(state.copyWith(darkMode: enabled));

  void setLocale(String locale) => _update(state.copyWith(locale: locale));

  void _update(SettingsState next) {
    if (next == state) return;
    state = next;
    unawaited(UpdateSettings(ref.read(preferencesRepositoryProvider))(next));
  }
}

final NotifierProvider<SettingsController, SettingsState> settingsProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);
