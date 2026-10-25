import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/settings/domain/ui_preferences.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// Loads and persists [UiPreferences] through the preference store.
class UiPreferencesController extends Notifier<UiPreferences> {
  @override
  UiPreferences build() {
    unawaited(_load());
    return const UiPreferences();
  }

  Future<void> _load() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    state = UiPreferences(
      refreshIntervalSeconds:
          await prefs.getAs<int>(prefRefreshIntervalSeconds) ?? 5,
      preferredViewer: await prefs.getAs<String>(prefPreferredViewer) ?? '',
      notifyOnComplete: await prefs.getAs<bool>(prefNotifyOnComplete) ?? true,
      confirmRiskyActions:
          await prefs.getAs<bool>(prefConfirmRiskyActions) ?? true,
      advancedConfig: await prefs.getAs<bool>(prefAdvancedConfig) ?? false,
    );
  }

  Future<void> setRefreshIntervalSeconds(int seconds) =>
      _save(state.copyWith(refreshIntervalSeconds: seconds));

  Future<void> setPreferredViewer(String viewer) =>
      _save(state.copyWith(preferredViewer: viewer));

  Future<void> setNotifyOnComplete(bool enabled) =>
      _save(state.copyWith(notifyOnComplete: enabled));

  Future<void> setConfirmRiskyActions(bool enabled) =>
      _save(state.copyWith(confirmRiskyActions: enabled));

  Future<void> setAdvancedConfig(bool enabled) =>
      _save(state.copyWith(advancedConfig: enabled));

  Future<void> _save(UiPreferences next) async {
    state = next;
    final prefs = ref.read(preferencesRepositoryProvider);
    await prefs.set(prefRefreshIntervalSeconds, next.refreshIntervalSeconds);
    await prefs.set(prefPreferredViewer, next.preferredViewer);
    await prefs.set(prefNotifyOnComplete, next.notifyOnComplete);
    await prefs.set(prefConfirmRiskyActions, next.confirmRiskyActions);
    await prefs.set(prefAdvancedConfig, next.advancedConfig);
  }
}

/// UI behaviour preferences; defaults until the persisted values load.
final uiPreferencesProvider =
    NotifierProvider<UiPreferencesController, UiPreferences>(
      UiPreferencesController.new,
    );
