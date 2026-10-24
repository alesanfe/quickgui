import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/settings/domain/supported_locales.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/diagnostics/presentation/debget_not_found_page.dart';
import 'package:quickgui/features/home/presentation/main_page.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/infrastructure/app_info/app_version.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: AppVersion.packageInfo == null
          ? const DebgetNotFoundPage()
          : const MainPage(),
      supportedLocales: supportedLocales.map(
        (s) => s.contains('_')
            ? Locale(s.split('_')[0], s.split('_')[1])
            : Locale(s),
      ),
      localizationsDelegates: [
        GettextLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
        GlobalWidgetsLocalizations.delegate,
      ],
      locale: Locale(settings.languageCode, settings.countryCode),
      localeListResolutionCallback: (locales, supportedLocales) {
        for (final locale in locales ?? const <Locale>[]) {
          final exact = supportedLocales.where(
            (l) =>
                l.languageCode == locale.languageCode &&
                l.countryCode == locale.countryCode,
          );
          if (exact.isNotEmpty) return exact.first;
          final language = supportedLocales.where(
            (l) => l.languageCode == locale.languageCode,
          );
          if (language.isNotEmpty) return language.first;
        }
        return null;
      },
    );
  }
}
