import 'package:shared_preferences/shared_preferences.dart';

import 'package:quickgui/infrastructure/persistence/preferences_repository.dart';

class SharedPreferencesRepository implements PreferencesRepository {
  @override
  Future<Object?> get(String key) async =>
      (await SharedPreferences.getInstance()).get(key);

  @override
  Future<void> set(String key, Object? value) async {
    final p = await SharedPreferences.getInstance();
    if (value is String) await p.setString(key, value);
    if (value is int) await p.setInt(key, value);
    if (value is bool) await p.setBool(key, value);
    if (value is double) await p.setDouble(key, value);
  }
}
