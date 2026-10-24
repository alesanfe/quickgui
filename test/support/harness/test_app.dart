import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// MaterialApp with the gettext delegate wired, so widgets using
/// `context.t(...)` can be pumped in tests (English locale).
MaterialApp testApp({required Widget home, ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  locale: const Locale('en'),
  supportedLocales: const [Locale('en')],
  localizationsDelegates: [
    GettextLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
    GlobalWidgetsLocalizations.delegate,
  ],
  home: home,
);
