import '../../domain/common/result.dart';

import 'package:quickgui/app/app_settings.dart';

import '../../infrastructure/preferences/preferences_repository.dart';

/// Use case: load persisted app settings.
class LoadSettings {
  LoadSettings(this._prefs);
  final PreferencesRepository _prefs;

  Future<Result<AppSettings>> call() async {
    await _prefs.get('settings');
    return Ok(AppSettings());
  }
}
