import 'package:quickgui/core/result/result.dart';

import 'package:quickgui/app/settings/app_settings.dart';

import 'package:quickgui/infrastructure/persistence/preferences_repository.dart';

/// Use case: persist changed app settings.
class UpdateSettings {
  UpdateSettings(this._prefs);
  final PreferencesRepository _prefs;

  Future<Result<void>> call(AppSettings settings) async {
    await _prefs.set('settings', settings.themeMode.name);
    return const Ok(null);
  }
}
