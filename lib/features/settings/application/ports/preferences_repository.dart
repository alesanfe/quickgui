/// Abstraction over the app preference store so use cases can be
/// tested against fakes.
///
/// Keys live in `core/constants/preference_keys.dart`; typed reads are
/// provided by `core/extensions/preferences_repository_x.dart`.
abstract class PreferencesRepository {
  Future<Object?> get(String key);
  Future<void> set(String key, Object? value);
}
