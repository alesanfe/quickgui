import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/core/persistence/preferences_repository.dart';

/// Use case: load persisted app settings, normalising the locale against
/// the locales quickgui ships translations for.
class LoadSettings {
  LoadSettings(
    this._prefs, {
    required this.supportedLocales,
    required this.systemLocale,
  });
  final PreferencesRepository _prefs;
  final List<String> supportedLocales;
  final String systemLocale;

  Future<Result<SettingsState>> call() async {
    final dark = await _prefs.get(SettingsKeys.darkMode);
    final locale = await _prefs.get(SettingsKeys.locale);
    return Ok(
      SettingsState(
        darkMode: dark is bool && dark,
        locale: SettingsState.normalizeLocale(
          locale is String ? locale : systemLocale,
          supportedLocales,
        ),
      ),
    );
  }
}
