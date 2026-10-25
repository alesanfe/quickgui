import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/app/localization/supported_locales.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/app/router/app_router.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';

import 'package:quickgui/app/localization/quickgui_localizations_delegate.dart';

class App extends ConsumerWidget {
  const App({
    super.key,
    this.localizationsDelegate = const QuickguiLocalizationsDelegate(),
  });

  final LocalizationsDelegate<dynamic> localizationsDelegate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      routerConfig: ref.watch(appRouterProvider),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      supportedLocales: supportedLocales.map(
        (s) => s.contains('_')
            ? Locale(s.split('_')[0], s.split('_')[1])
            : Locale(s),
      ),
      localizationsDelegates: [
        localizationsDelegate,
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
