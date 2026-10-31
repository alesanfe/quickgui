/// Shared preference keys.
const String prefWorkingDirectory = 'workingDirectory';
const String prefNewlyInstalledVms = 'newlyInstalledVms';
const String prefDownloadHistory = 'downloadHistory';
const String prefActivityHistory = 'activityHistory';
const String prefActiveOperations = 'activeOperations';
const String prefActivityFilters = 'activityFilters';
const String prefQuickemuApiToken = 'quickemuApiToken';
const String prefVmTags = 'vmTags';
const String prefRefreshIntervalSeconds = 'refreshIntervalSeconds';
const String prefPreferredViewer = 'preferredViewer';
const String prefNotifyOnComplete = 'notifyOnComplete';
const String prefVmNotifications = 'vmNotifications';
const String prefConfirmRiskyActions = 'confirmRiskyActions';
const String prefAdvancedConfig = 'advancedConfig';

/// Whether the first-run onboarding hint has been shown.
const String prefFirstRunHintShown = 'firstRunHintShown';

/// Console: capture the physical keyboard while the console has focus.
const String prefConsoleKeyboardGrab = 'consoleKeyboardGrab';

/// Console: synchronise clipboard between host and guest (RFB cut text).
const String prefConsoleClipboardSync = 'consoleClipboardSync';

/// Console scale mode prefix — stored per VM as `'$prefConsoleScaleMode<vm>'`.
const String prefConsoleScaleMode = 'consoleScaleMode_';
