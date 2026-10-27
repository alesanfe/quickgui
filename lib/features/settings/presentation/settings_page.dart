import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/app/app_version.dart';
import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/features/settings/providers/update_check_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// Full settings section: appearance, language and application
/// behaviour (refresh interval, preferred viewer, notifications,
/// confirmations, advanced configuration mode).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsCtl = ref.read(settingsProvider.notifier);
    final prefs = ref.watch(uiPreferencesProvider);
    final prefsCtl = ref.read(uiPreferencesProvider.notifier);
    final workingDir = Directory.current.path;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(context.t('Appearance')),
          SwitchListTile(
            title: Text(context.t('Use dark mode')),
            value: settings.darkMode,
            onChanged: (v) => settingsCtl.setDarkMode(enabled: v),
          ),
          ListTile(
            title: Text(context.t('Language')),
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
          const Divider(),
          _header(context.t('Virtual machines')),
          ListTile(
            title: Text(context.t('Working directory')),
            subtitle: Text(
              workingDir,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            trailing: TextButton(
              onPressed: () async {
                final folder = await FilePicker.getDirectoryPath(
                  dialogTitle: context.t('Pick a folder'),
                );
                if (folder != null && folder.isNotEmpty) {
                  setState(() => Directory.current = folder);
                  ref
                      .read(preferencesRepositoryProvider)
                      .set(prefWorkingDirectory, folder);
                }
              },
              child: Text(context.t('Change')),
            ),
          ),
          ListTile(
            title: Text(context.t('Refresh interval')),
            subtitle: Text(context.t('How often the machine list is updated')),
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
          ListTile(
            title: Text(context.t('Preferred display viewer')),
            subtitle: Text(
              context.t('Used to open the console of running machines'),
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
          SwitchListTile(
            title: Text(context.t('Advanced configuration mode')),
            subtitle: Text(
              context.t('Show every configuration key in the VM settings page'),
            ),
            value: prefs.advancedConfig,
            onChanged: prefsCtl.setAdvancedConfig,
          ),
          const Divider(),
          _header(context.t('Quickemu')),
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
          ListTile(
            leading: const Icon(Icons.handyman_outlined),
            title: Text(context.t('Diagnostics')),
            subtitle: Text(
              context.t('Contract, dependencies and legacy fallback status'),
            ),
            onTap: () => context.go('/diagnostics'),
          ),
          const Divider(),
          _header(context.t('Behaviour')),
          SwitchListTile(
            title: Text(context.t('Notify when downloads finish')),
            value: prefs.notifyOnComplete,
            onChanged: prefsCtl.setNotifyOnComplete,
          ),
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
          const Divider(),
          _header(context.t('About')),
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
          ListTile(
            leading: const Icon(Icons.system_update),
            title: Text(context.t('Check for updates')),
            onTap: _checkUpdates,
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart),
            title: Text(context.t('Quickemu report')),
            onTap: _showReport,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
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
    );
  }

  TextSpan _link(String text, String url) => TextSpan(
    text: text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    ),
    recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url)),
  );

  Future<void> _checkUpdates() async {
    final latest = await ref.read(latestReleaseProvider)();
    if (!mounted) return;
    final current = ref.read(hostProbeProvider).appVersion;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Check for updates')),
        content: Text(
          latest.isEmpty
              ? context.t(
                  'Could not check for updates. Check your network connection and try again later.',
                )
              : context.t(
                  'Installed: {0}\nLatest: {1}',
                  args: [current, latest],
                ),
        ),
        actions: [
          if (latest.isNotEmpty && latest != current)
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://github.com/quickemu-project/quickgui/releases/latest',
                ),
              ),
              child: Text(context.t('Open release page')),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Dismiss')),
          ),
        ],
      ),
    );
  }

  Future<void> _showReport() async {
    final proc = await ref.read(backendProvider).diagnosticsReport();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Quickemu report')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '${proc.stdout}${proc.stderr}'.trim(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Dismiss')),
          ),
        ],
      ),
    );
  }

  /// DropdownButton sizes its button to the widest item's intrinsic
  /// width; unbounded labels get clipped on narrow layouts, which trips
  /// the debug semantics assertion (`!semantics.parentDataDirty`).
  Widget _boundedText(String label) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 120),
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
