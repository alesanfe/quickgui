/// Shared preference keys.
const String prefWorkingDirectory = 'workingDirectory';
const String prefNewlyInstalledVms = 'newlyInstalledVms';

/// Abstraction over the app preference store so use cases can be
/// tested against fakes.
abstract class PreferencesRepository {
  Future<Object?> get(String key);
  Future<void> set(String key, Object? value);
}

extension PreferencesRepositoryX on PreferencesRepository {
  /// Typed read of [key]; returns null when unset or of another type.
  Future<T?> getAs<T>(String key) async {
    final value = await get(key);
    return value is T ? value : null;
  }
}
