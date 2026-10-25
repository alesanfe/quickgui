import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

/// Settings controls shown inside the home drawer: dark mode toggle and
/// language selector. Changes are persisted via [settingsProvider].
class SettingsSection extends ConsumerWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final dropdownMenuItems = supportedLocales
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList();
    return Column(
      children: [
        Container(height: 4.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(context.t('Use dark mode')),
              Expanded(child: Container()),
              Switch(
                value: settings.darkMode,
                onChanged: (value) {
                  controller.setDarkMode(enabled: value);
                },
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
                value: settings.locale,
                items: dropdownMenuItems,
                onChanged: (value) {
                  if (value != null) controller.setLocale(value);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
