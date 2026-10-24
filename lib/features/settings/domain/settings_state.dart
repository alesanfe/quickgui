import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_state.freezed.dart';

/// Persistence keys shared with the legacy preference store.
abstract final class SettingsKeys {
  static const darkMode = 'themeMode';
  static const locale = 'currentLocale';
}

/// Immutable user-facing app settings (pure Dart: no Flutter types).
@freezed
abstract class SettingsState with _$SettingsState {
  const SettingsState._();

  const factory SettingsState({
    @Default(false) bool darkMode,
    @Default('en') String locale,
  }) = _SettingsState;

  String get languageCode => locale.split('_').first;

  String? get countryCode {
    final parts = locale.split('_');
    return parts.length > 1 ? parts[1] : null;
  }

  /// Maps a raw system/user locale (e.g. `en_US.UTF-8`) onto one of
  /// [supported]: exact match, then language only, then `en`.
  static String normalizeLocale(String raw, List<String> supported) {
    final base = raw.split('.').first;
    if (supported.contains(base)) return base;
    final language = base.split('_').first;
    return supported.contains(language) ? language : 'en';
  }
}
