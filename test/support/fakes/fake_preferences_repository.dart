import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';

class FakePreferencesRepository implements PreferencesRepository {
  final store = <String, Object?>{};

  @override
  Future<Object?> get(String key) async => store[key];

  @override
  Future<void> set(String key, Object? value) async {
    store[key] = value;
  }
}
