import 'package:quickgui/core/result/result.dart';

import 'package:quickgui/app/settings/app_settings.dart';

import 'package:quickgui/infrastructure/persistence/preferences_repository.dart';

/// Use case: load persisted app settings.
class LoadSettings {
  LoadSettings(this._prefs);
  final PreferencesRepository _prefs;

  Future<Result<AppSettings>> call() async {
    await _prefs.get('settings');
    return Ok(AppSettings());
  }
}
