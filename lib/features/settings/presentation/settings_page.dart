import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/app/app_version.dart';
import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/activity/presentation/operation_tile.dart';
import 'package:quickgui/features/notifications/domain/vm_event_notification.dart';
import 'package:quickgui/features/notifications/providers/notification_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';
import 'package:quickgui/features/settings/domain/ui_preferences.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/features/settings/providers/update_check_providers.dart';
import 'package:quickgui/shared/providers/working_directory_provider.dart';
import 'package:quickgui/shared/widgets/scroll_dialog.dart';
import 'package:quickgui/shared/widgets/shortcuts_dialog.dart';

/// Full settings section: appearance, language and application
/// behaviour (refresh interval, preferred viewer, notifications,
/// confirmations, advanced configuration mode).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// QGUI-SET-002: settings are searchable by name and synonym — the
  /// page structure is data-driven so a query can hide non-matching
  /// tiles without touching their behaviour.
  String _search = '';
  final _searchFocus = FocusNode(debugLabel: 'settings-search');

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsCtl = ref.read(settingsProvider.notifier);
    final prefs = ref.watch(uiPreferencesProvider);
    final prefsCtl = ref.read(uiPreferencesProvider.notifier);
    final workingDir = ref.watch(workingDirectoryProvider);
    // Sections as (header, [(search keywords, tile)]) — a header stays
    // hidden when none of its tiles match the query.
    final sections = <(String, List<(String, Widget)>)>[
      (
        context.t('Appearance'),
        [
          (
            'dark mode theme appearance',
            SwitchListTile(
              title: Text(context.t('Use dark mode')),
              subtitle: Text(context.t('Applies immediately')),
              value: settings.darkMode,
              onChanged: (v) => settingsCtl.setDarkMode(enabled: v),
            ),
          ),
          (
            'language locale idioma',
            ListTile(
              title: Text(context.t('Language')),
              subtitle: Text(context.t('Applies immediately')),
              trailing: DropdownButton<String>(
                value: settings.locale,
                items: supportedLocales
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: _boundedText(localeNames[e] ?? e),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) settingsCtl.setLocale(v);
                },
              ),
            ),
          ),
        ],
      ),
      (
        context.t('Virtual machines'),
        [
          (
            'working directory folder path machines',
            ListTile(
              title: Text(context.t('Working directory')),
              subtitle: Text(
                '$workingDir — ${context.t('Applies to new machines and scans')}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              trailing: TextButton(
                onPressed: () async {
                  final folder = await FilePicker.getDirectoryPath(
                    dialogTitle: context.t('Pick a folder'),
                  );
                  if (folder != null && folder.isNotEmpty) {
                    await ref
                        .read(workingDirectoryProvider.notifier)
                        .set(folder);
                  }
                },
                child: Text(context.t('Change')),
              ),
            ),
          ),
          (
            'refresh interval update frequency poll',
            ListTile(
              title: Text(context.t('Refresh interval')),
              subtitle: Text(
                context.t(
                  'How often the machine list is updated — applies immediately',
                ),
              ),
              trailing: DropdownButton<int>(
                value: prefs.refreshIntervalSeconds,
                items: [
                  for (final s in const [2, 5, 10, 30])
                    DropdownMenuItem(value: s, child: Text('$s s')),
                ],
                onChanged: (v) {
                  if (v != null) prefsCtl.setRefreshIntervalSeconds(v);
                },
              ),
            ),
          ),
          (
            'preferred display viewer spicy remote-viewer console',
            ListTile(
              title: Text(context.t('Preferred display viewer')),
              subtitle: Text(
                context.t(
                  'Used to open the console of running machines — applies on next connect',
                ),
              ),
              trailing: DropdownButton<String>(
                value: prefs.preferredViewer,
                items: [
                  for (final (v, label) in [
                    ('', context.t('Automatic')),
                    ('spicy', 'spicy'),
                    ('remote-viewer', 'remote-viewer'),
                    ('none', 'none'),
                  ])
                    DropdownMenuItem(value: v, child: _boundedText(label)),
                ],
                onChanged: (v) {
                  if (v != null) prefsCtl.setPreferredViewer(v);
                },
              ),
            ),
          ),
          (
            'advanced configuration keys expert',
            SwitchListTile(
              title: Text(context.t('Advanced configuration mode')),
              subtitle: Text(
                context.t(
                  'Show every configuration key in the VM settings page — applies on next open',
                ),
              ),
              value: prefs.advancedConfig,
              onChanged: prefsCtl.setAdvancedConfig,
            ),
          ),
        ],
      ),
      (
        context.t('Quickemu'),
        [
          (
            'backend version quickemu installation',
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(context.t('Backend version')),
              subtitle: Text(context.t('Detected Quickemu installation')),
              trailing: ref
                  .watch(backendVersionProvider)
                  .when(
                    data: (v) => Text(v.isEmpty ? context.t('Not found') : v),
                    loading: () => const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    error: (_, _) => Text(context.t('Unknown')),
                  ),
            ),
          ),
          (
            'diagnostics integration tools compatibility',
            ListTile(
              leading: const Icon(Icons.handyman_outlined),
              title: Text(context.t('Diagnostics')),
              // User-facing wording, not internal jargon (QGUI-SET-001).
              subtitle: Text(
                context.t(
                  'Quickemu integration, required tools and compatibility status',
                ),
              ),
              onTap: () => context.go('/diagnostics'),
            ),
          ),
        ],
      ),
      (
        context.t('Behaviour'),
        [
          (
            'notify downloads finish notification',
            SwitchListTile(
              title: Text(context.t('Notify when downloads finish')),
              subtitle: Text(context.t('Applies immediately')),
              value: prefs.notifyOnComplete,
              onChanged: prefsCtl.setNotifyOnComplete,
            ),
          ),
          (
            'confirm risky actions delete stop reset',
            SwitchListTile(
              title: Text(context.t('Confirm risky actions')),
              subtitle: Text(
                context.t(
                  'Ask before resetting machines, forcing stops or applying snapshots. Deleting always asks.',
                ),
              ),
              value: prefs.confirmRiskyActions,
              onChanged: prefsCtl.setConfirmRiskyActions,
            ),
          ),
        ],
      ),
      (
        context.t('About'),
        [
          (
            'quickgui version about',
            ListTile(
              title: const Text('Quickgui'),
              subtitle: Text(
                context.t(
                  'Version {0} — Powered by Quickemu',
                  args: [
                    AppVersion.packageInfo?.version ??
                        ref.read(hostProbeProvider).appVersion,
                  ],
                ),
              ),
            ),
          ),
          (
            'check updates release upgrade',
            ListTile(
              leading: const Icon(Icons.system_update),
              title: Text(context.t('Check for updates')),
              onTap: _checkUpdates,
            ),
          ),
          (
            'quickemu report system diagnostics',
            ListTile(
              leading: const Icon(Icons.monitor_heart),
              title: Text(context.t('Quickemu report')),
              onTap: _showReport,
            ),
          ),
          (
            'keyboard shortcuts hotkeys',
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: Text(context.t('Keyboard shortcuts')),
              onTap: () => ShortcutsDialog.show(context),
            ),
          ),
        ],
      ),
    ];
    final query = _search.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Settings')),
        actions: [
          // SET-101: granular restore — a preview lists exactly which
          // settings differ from defaults before anything is reset.
          IconButton(
            tooltip: context.t('Restore defaults'),
            icon: const Icon(Icons.restore),
            onPressed: () => _restoreDefaults(settings, prefs),
          ),
        ],
      ),
      body: CallbackShortcuts(
        // Keyboard parity: Ctrl+F jumps straight to the search field.
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _searchFocus.requestFocus,
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              focusNode: _searchFocus,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: context.t('Search settings'),
                border: const OutlineInputBorder(),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.t('Clear search'),
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _search = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            for (final (header, items) in sections)
              if (query.isEmpty ||
                  items.any((e) => e.$1.toLowerCase().contains(query))) ...[
                _header(header),
                for (final (keywords, item) in items)
                  if (query.isEmpty || keywords.toLowerCase().contains(query))
                    item,
                const Divider(),
              ],
            _vmNotificationSection(context),
            Padding(
              padding: const EdgeInsets.all(16),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  // Not DefaultTextStyle.of(context): this context is the
                  // page's own element, above the Scaffold's Material, so
                  // it resolves the WidgetsApp fallback style (48px
                  // monospace) instead of the body style.
                  style: Theme.of(context).textTheme.bodySmall,
                  children: [
                    const TextSpan(
                      text: 'Authors\n',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    _link('Yannick Mauray', 'https://github.com/ymauray'),
                    const TextSpan(text: ', '),
                    _link('Mark Johnson', 'https://github.com/marxjohnson'),
                    const TextSpan(text: ', '),
                    _link('Martin Wimpress', 'https://wimpysworld.io'),
                    TextSpan(text: '\n© 2021 - ${DateTime.now().year} '),
                    _link(
                      'Quickemu Project',
                      'https://github.com/quickemu-project',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// VM-event notification preferences (QG-081): master switch, per
  /// event-kind toggles, temporary silence and per-VM mutes.
  Widget _vmNotificationSection(BuildContext context) {
    final notif = ref.watch(notificationSettingsProvider);
    final notifCtl = ref.read(notificationSettingsProvider.notifier);
    final muted = notif.mutedNow(DateTime.now().millisecondsSinceEpoch);
    final kindLabels = {
      NotificationEventKind.vmStarted: context.t('Machine started'),
      NotificationEventKind.vmStopped: context.t('Machine stopped'),
      NotificationEventKind.vmCrashed: context.t('Machine crashed'),
      NotificationEventKind.vmPausedResumed: context.t(
        'Machine paused or resumed',
      ),
      NotificationEventKind.vmDeleted: context.t('Machine deleted'),
      NotificationEventKind.opCompleted: context.t('Operation finished'),
      NotificationEventKind.opFailed: context.t('Operation failed'),
      NotificationEventKind.snapshot: context.t('Snapshot finished'),
      NotificationEventKind.backup: context.t('Backup problem'),
      NotificationEventKind.qga: context.t('Guest agent lost'),
      NotificationEventKind.lowDisk: context.t('Low disk space'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(context.t('Notify about machine events')),
          subtitle: Text(
            context.t('Starts, stops, crashes and operation results'),
          ),
          value: notif.enabled,
          onChanged: notifCtl.setEnabled,
        ),
        if (notif.enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.t('Event types')),
              children: [
                for (final kind in NotificationEventKind.values)
                  SwitchListTile(
                    dense: true,
                    title: Text(kindLabels[kind] ?? kind.name),
                    value: notif.kindEnabled(kind),
                    onChanged: (v) => notifCtl.setKind(kind, v),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(context.t('Muted machines')),
              children: [
                for (final vm
                    in ref
                            .watch(vmLibraryProvider)
                            .asData
                            ?.value
                            .map((m) => m.name)
                            .toList() ??
                        const <String>[])
                  SwitchListTile(
                    dense: true,
                    title: Text(vm),
                    value: notif.mutedVms.contains(vm),
                    onChanged: (v) => notifCtl.setVmMuted(vm, v),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.do_not_disturb_on_outlined),
            title: Text(
              muted
                  ? context.t('Notifications silenced')
                  : context.t('Silence notifications for an hour'),
            ),
            trailing: muted
                ? TextButton(
                    onPressed: notifCtl.unmute,
                    child: Text(context.t('Unmute')),
                  )
                : null,
            onTap: muted
                ? null
                : () => notifCtl.muteFor(const Duration(hours: 1)),
          ),
        ],
      ],
    );
  }

  /// SET-101: shows the diff from defaults before resetting — nothing
  /// is restored silently.
  Future<void> _restoreDefaults(
    SettingsState settings,
    UiPreferences prefs,
  ) async {
    const defaults = UiPreferences();
    final systemLocale = SettingsState.normalizeLocale(
      Platform.localeName,
      supportedLocales,
    );
    final changes = <(String, String)>[
      if (settings.darkMode) (context.t('Use dark mode'), context.t('Enabled')),
      if (settings.locale != systemLocale)
        (
          context.t('Language'),
          localeNames[settings.locale] ?? settings.locale,
        ),
      if (prefs.refreshIntervalSeconds != defaults.refreshIntervalSeconds)
        (context.t('Refresh interval'), '${prefs.refreshIntervalSeconds} s'),
      if (prefs.preferredViewer != defaults.preferredViewer)
        (context.t('Preferred display viewer'), prefs.preferredViewer),
      if (prefs.advancedConfig)
        (context.t('Advanced configuration mode'), context.t('Enabled')),
      if (!prefs.notifyOnComplete)
        (context.t('Notify when downloads finish'), context.t('Disabled')),
      if (!prefs.confirmRiskyActions)
        (context.t('Confirm risky actions'), context.t('Disabled')),
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => QDialog(
        title: context.t('Restore defaults'),
        width: 420,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: changes.isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: Text(context.t('Restore')),
          ),
        ],
        child: changes.isEmpty
            ? Text(context.t('Everything is already at its default value.'))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('These settings will return to their defaults:'),
                  ),
                  const SizedBox(height: 8),
                  for (final (name, current) in changes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $name — $current'),
                    ),
                ],
              ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final settingsCtl = ref.read(settingsProvider.notifier);
    final prefsCtl = ref.read(uiPreferencesProvider.notifier);
    settingsCtl.setDarkMode(enabled: false);
    settingsCtl.setLocale(systemLocale);
    await prefsCtl.setRefreshIntervalSeconds(defaults.refreshIntervalSeconds);
    await prefsCtl.setPreferredViewer(defaults.preferredViewer);
    await prefsCtl.setNotifyOnComplete(defaults.notifyOnComplete);
    await prefsCtl.setConfirmRiskyActions(defaults.confirmRiskyActions);
    await prefsCtl.setAdvancedConfig(defaults.advancedConfig);
  }

  TextSpan _link(String text, String url) => TextSpan(
    text: text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
  );

  /// QGUI-UPD-001/002/101: the result dialog keeps its own state — a
  /// failed check offers Retry without leaving the dialog, errors are
  /// classified (connection vs service vs unexpected response) and the
  /// last check timestamp stays visible.
  Future<void> _checkUpdates() async {
    var checking = true;
    var latest = '';
    String? error;
    DateTime? checkedAt;
    final current = ref.read(hostProbeProvider).appVersion;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> check() async {
            setState(() => checking = true);
            final r = await ref.read(latestReleaseProvider)();
            if (context.mounted) {
              setState(() {
                latest = r.version;
                error = r.errorKind;
                checkedAt = DateTime.now();
                checking = false;
              });
            }
          }

          if (checking && latest.isEmpty && error == null) {
            // First frame — kick the initial request.
            Future.microtask(check);
          }
          final errorText = switch (error) {
            'connection' => context.t(
              'Could not reach the update service — check your internet connection.',
            ),
            'timeout' => context.t(
              'The update service did not respond in time — try again later.',
            ),
            'tls' => context.t(
              'The update service failed the security check — do not retry on an untrusted network.',
            ),
            'service' => context.t(
              'The update service is temporarily unavailable (HTTP error).',
            ),
            'response' => context.t(
              'The update service returned an unexpected response.',
            ),
            'unknown' => context.t('The update check failed unexpectedly.'),
            _ => '',
          };
          return QDialog(
            title: context.t('Check for updates'),
            width: 420,
            actions: [
              if (!checking && error != null)
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.t('Retry')),
                  onPressed: check,
                ),
              if (!checking && latest.isNotEmpty && latest != current)
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://github.com/quickemu-project/quickgui/releases/latest',
                    ),
                  ),
                  child: Text(context.t('Open release page')),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('Dismiss')),
              ),
            ],
            child: checking
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        errorText.isNotEmpty
                            ? errorText
                            : context.t(
                                'Installed: {0}\nLatest: {1}',
                                args: [current, latest],
                              ),
                      ),
                      if (checkedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            // Relative label — an absolute timestamp would
                            // make this dialog non-deterministic in
                            // capture tests.
                            context.t(
                              'Last checked: {0}',
                              args: [formatOperationAgo(context, checkedAt!)],
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _showReport() async {
    final proc = await ref.read(backendProvider).diagnosticsReport();
    if (!mounted) return;
    final report = '${proc.stdout}${proc.stderr}'.trim();
    showDialog<void>(
      context: context,
      // QGUI-SYSDIAG-001/002: monospace at the 12px repo floor, explicit
      // copy action, fixed action bar via the shared dialog shell.
      builder: (context) => QDialog(
        title: context.t('Quickemu report'),
        width: 720,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: Text(context.t('Copy')),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(context.t('Copied'))));
              }
            },
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Dismiss')),
          ),
        ],
        child: SelectableText(
          report,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }

  /// DropdownButton sizes its button to the widest item's intrinsic
  /// width; unbounded labels get clipped on narrow layouts, which trips
  /// the debug semantics assertion (`!semantics.parentDataDirty`).
  Widget _boundedText(String label) => ConstrainedBox(
    // VISTA-027 V-200-3: scale the bound with the text scaler — a fixed
    // 120px clips "Automatic" to "Autom…" at 200%.
    constraints: BoxConstraints(
      maxWidth: 120 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
    ),
    child: Text(label, overflow: TextOverflow.ellipsis),
  );

  Widget _header(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}
