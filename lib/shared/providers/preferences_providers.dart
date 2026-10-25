import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';
import 'package:quickgui/infrastructure/settings/shared_preferences_repository.dart';

/// Preference store; overridden with a fake in tests.
final Provider<PreferencesRepository> preferencesRepositoryProvider =
    Provider<PreferencesRepository>((ref) => SharedPreferencesRepository());
