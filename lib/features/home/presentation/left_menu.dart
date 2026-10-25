import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/app/router/app_router.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/settings/presentation/settings_section.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/networking/quickgui_releases.dart';

class LeftMenu extends ConsumerStatefulWidget {
  const LeftMenu({super.key});

  @override
  ConsumerState<LeftMenu> createState() => _LeftMenuState();
}

class _LeftMenuState extends ConsumerState<LeftMenu> {
  @override
  void initState() {
    super.initState();
    ref.read(backendProvider).version();
  }

  TextSpan _linkSpan(
    String text,
    String url,
    BuildContext context, {
    bool bold = false,
  }) {
    return TextSpan(
      text: text,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () => launchUrl(Uri.parse(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = ref.read(hostProbeProvider).appVersion;
    return Builder(
      builder: (context) {
        return Drawer(
          child: ListView(
            children: [
              Padding(
                // Minimal bottom padding
                padding: const EdgeInsets.only().add(
                  const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    "Quickgui $version",
                    style: const TextStyle(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              FutureBuilder<String>(
                future: ref.read(backendProvider).version(),
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator(); // or some other widget while waiting
                      } else {
                        String poweredByText =
                            "${context.t('Powered by')} Quickemu";
                        if (snapshot.hasData) {
                          poweredByText += " ${snapshot.data}";
                        }
                        return Padding(
                          // Minimal top padding
                          padding: const EdgeInsets.only().add(
                            const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: Text(
                            poweredByText,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }
                    },
              ),
              const SettingsSection(),
              Container(height: 32.0),
              ListTile(
                leading: const Icon(Icons.health_and_safety),
                title: Text(context.t('Diagnostics')),
                dense: true,
                onTap: () =>
                    Navigator.of(context)
                        .push(appRoute<void>(const DiagnosticsPage())),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(context.t('Download history')),
                dense: true,
                onTap: () async {
                  final history = await ref
                      .read(preferencesRepositoryProvider)
                      .getAs<List<String>>(prefDownloadHistory);
                  if (!context.mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.t('Download history')),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: history == null || history.isEmpty
                            ? Text(context.t('No downloads yet'))
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: history.reversed
                                      .map(Text.new)
                                      .toList(),
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
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: Text(context.t('Check for updates')),
                dense: true,
                onTap: () async {
                  final latest = await fetchLatestQuickguiRelease();
                  if (!context.mounted) return;
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
                },
              ),
              ListTile(
                leading: const Icon(Icons.monitor_heart),
                title: Text(context.t('Quickemu report')),
                dense: true,
                onTap: () async {
                  final proc = await ref
                      .read(backendProvider)
                      .diagnosticsReport();
                  if (!context.mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.t('Quickemu report')),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            '${proc.stdout}${proc.stderr}'.trim(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
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
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: <TextSpan>[
                          const TextSpan(
                            text: 'Authors\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          _linkSpan(
                            'Yannick Mauray\n',
                            'https://github.com/ymauray',
                            context,
                          ),
                          _linkSpan(
                            'Mark Johnson\n',
                            'https://github.com/marxjohnson',
                            context,
                          ),
                          _linkSpan(
                            'Martin Wimpress\n',
                            'https://wimpysworld.io',
                            context,
                          ),
                        ],
                      ),
                    ),
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: <TextSpan>[
                          TextSpan(text: '© 2021 - ${DateTime.now().year}\n'),
                          _linkSpan(
                            'Quickemu Project\n',
                            'https://github.com/quickemu-project',
                            context,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
