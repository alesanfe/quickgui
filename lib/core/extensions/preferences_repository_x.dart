import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';

extension PreferencesRepositoryX on PreferencesRepository {
  /// Typed read of [key]; returns null when unset or of another type.
  Future<T?> getAs<T>(String key) async {
    final value = await get(key);
    return value is T ? value : null;
  }
}
