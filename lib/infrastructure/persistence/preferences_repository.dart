/// Abstraction over the app preference store so use cases can be
/// tested against fakes.
abstract class PreferencesRepository {
  Future<Object?> get(String key);
  Future<void> set(String key, Object? value);
}
