import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/core/persistence/preferences_repository.dart';

/// Use case: persist changed app settings.
class UpdateSettings {
  UpdateSettings(this._prefs);
  final PreferencesRepository _prefs;

  Future<Result<void>> call(SettingsState settings) async {
    await _prefs.set(SettingsKeys.darkMode, settings.darkMode);
    await _prefs.set(SettingsKeys.locale, settings.locale);
    return const Ok(null);
  }
}
