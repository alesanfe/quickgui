/// UI behaviour preferences persisted alongside the settings state.
/// Kept out of the freezed model so they can evolve without codegen.
class UiPreferences {
  const UiPreferences({
    this.refreshIntervalSeconds = 5,
    this.preferredViewer = '',
    this.notifyOnComplete = true,
    this.confirmRiskyActions = true,
    this.advancedConfig = false,
  });

  /// Machines list refresh period (seconds).
  final int refreshIntervalSeconds;

  /// Preferred SPICE viewer ('' = autodetect, 'spicy', 'remote-viewer').
  final String preferredViewer;

  /// Send a desktop notification when a download finishes.
  final bool notifyOnComplete;

  /// Ask before mid-risk actions (reset, force stop, snapshot apply).
  final bool confirmRiskyActions;

  /// Default the VM settings page to the advanced editor.
  final bool advancedConfig;

  UiPreferences copyWith({
    int? refreshIntervalSeconds,
    String? preferredViewer,
    bool? notifyOnComplete,
    bool? confirmRiskyActions,
    bool? advancedConfig,
  }) => UiPreferences(
    refreshIntervalSeconds:
        refreshIntervalSeconds ?? this.refreshIntervalSeconds,
    preferredViewer: preferredViewer ?? this.preferredViewer,
    notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
    confirmRiskyActions: confirmRiskyActions ?? this.confirmRiskyActions,
    advancedConfig: advancedConfig ?? this.advancedConfig,
  );
}
