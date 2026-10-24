import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:quickgui/src/supported_locales.dart';

import '../globals.dart';
import '../mixins/app_version.dart';
import '../mixins/preferences_mixin.dart';
import '../model/app_settings.dart';

class LeftMenu extends StatefulWidget {
  const LeftMenu({super.key});

  @override
  State<LeftMenu> createState() => _LeftMenuState();
}

class _LeftMenuState extends State<LeftMenu> with PreferencesMixin {
  List<DropdownMenuItem<String>> _dropdownMenuItems = [];
  late String currentLocale;

  @override
  void initState() {
    super.initState();
    fetchQuickemuVersion();
    _dropdownMenuItems = supportedLocales
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList();
  }

  @override
  void didChangeDependencies() {
    var appSettings = context.read<AppSettings>();
    currentLocale = appSettings.activeLocale;
    if (!supportedLocales.contains(currentLocale)) {
      currentLocale = currentLocale.split("_")[0];
      if (!supportedLocales.contains(currentLocale)) {
        currentLocale = "en";
      }
    }
    super.didChangeDependencies();
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
    var version = AppVersion.packageInfo!.version;
    return Consumer<AppSettings>(
      builder: (context, appSettings, _) {
        return Drawer(
          child: ListView(
            children: [
              Padding(
                // Minimal bottom padding
                padding: const EdgeInsets.only(bottom: 0)
                    .add(const EdgeInsets.symmetric(horizontal: 16)),
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
                future: fetchQuickemuVersion(),
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
                          padding: const EdgeInsets.only(top: 0)
                              .add(const EdgeInsets.symmetric(horizontal: 16)),
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
              Container(height: 4.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      context.t('Use dark mode'),
                      style: TextStyle(color: Colors.grey[300]),
                    ),
                    Expanded(child: Container()),
                    Switch(
                      value:
                          Theme.of(context).colorScheme.brightness ==
                          Brightness.dark,
                      activeThumbColor: Colors.black26,
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveThumbColor: Colors.grey[500],
                      inactiveTrackColor: Colors.grey[300],

                      onChanged: (value) {
                        appSettings.useDarkMode = value;
                        savePreference(prefThemeMode, value);
                      },
                      // activeColor: Colors.white,
                      // activeTrackColor: Colors.black26,
                      // inactiveThumbColor:
                      //     Theme.of(context).colorScheme.onPrimary,
                      // inactiveTrackColor: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              Container(height: 4.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(context.t('Language')),
                    Expanded(child: Container()),
                    DropdownButton<String>(
                      value: currentLocale,
                      items: _dropdownMenuItems,
                      onChanged: (value) {
                        setState(() {
                          currentLocale = value!;
                          appSettings.activeLocale = currentLocale;
                          savePreference(prefCurrentLocale, currentLocale);
                        });
                      },
                    ),
                  ],
                ),
              ),
              Container(height: 32.0),
              ListTile(
                leading: const Icon(Icons.monitor_heart),
                title: Text(context.t('System diagnostics')),
                dense: true,
                onTap: () async {
                  final proc = await runHost('quickreport', []);
                  if (!context.mounted) return;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.t('System diagnostics')),
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
                          const TextSpan(text: '© 2021 - 2024\n'),
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
