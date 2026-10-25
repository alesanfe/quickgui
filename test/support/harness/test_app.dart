import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Synchronous gettext localizations for tests. The production
/// localizations delegate resolves its .po assets over the
/// `flutter/assets` platform channel; in `flutter test` that reply only
/// arrives for the first widget tree, so later trees stall forever in
/// [Localizations] and build nothing. The harness preloads `en.po` once
/// in `setUpAll` (outside the fake-async zone) and serves it
/// synchronously on every tree.
class TestLocalizationsDelegate
    extends LocalizationsDelegate<GettextLocalizations> {
  const TestLocalizationsDelegate();

  static String _po = 'msgid ""\nmsgstr ""\n"Language: en\\n"\n';

  /// Loads the real `en.po`; call once from `setUpAll` in each test file.
  static Future<void> preload() async {
    try {
      _po = await rootBundle.loadString('assets/translations/en.po');
    } catch (_) {
      // Keep the minimal fallback above — msgids pass through unchanged.
    }
  }

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GettextLocalizations> load(Locale locale) =>
      SynchronousFuture(GettextLocalizations.fromPO(_po));

  @override
  bool shouldReload(TestLocalizationsDelegate old) => false;
}

/// MaterialApp with the gettext delegate wired, so widgets using
/// `context.t(...)` can be pumped in tests (English locale).
MaterialApp testApp({required Widget home, ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  locale: const Locale('en'),
  supportedLocales: const [Locale('en')],
  localizationsDelegates: const [
    TestLocalizationsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
    GlobalWidgetsLocalizations.delegate,
  ],
  home: home,
);
