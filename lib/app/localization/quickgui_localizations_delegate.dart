import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Loads `assets/translations/<locale>.po` instead of the package-default
/// `assets/i18n/` path hardcoded by [GettextLocalizationsDelegate].
class QuickguiLocalizationsDelegate
    extends LocalizationsDelegate<GettextLocalizations> {
  const QuickguiLocalizationsDelegate({this.defaultLanguage = 'en'});

  final String defaultLanguage;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GettextLocalizations> load(Locale locale) async {
    var poContent = '';
    try {
      poContent = await rootBundle.loadString(
        'assets/translations/${locale.languageCode}_${locale.countryCode}.po',
      );
    } catch (e) {
      try {
        poContent = await rootBundle.loadString(
          'assets/translations/${locale.languageCode}.po',
        );
      } catch (e) {
        try {
          poContent = await rootBundle.loadString(
            'assets/translations/$defaultLanguage.po',
          );
        } catch (e) {
          // Ignore error, default strings will be used.
        }
      }
    }

    if (poContent == '') {
      poContent = 'msgid ""\nmsgstr ""\n"Language: $defaultLanguage\\n"\n';
    }

    return GettextLocalizations.fromPO(poContent);
  }

  @override
  bool shouldReload(
    covariant LocalizationsDelegate<GettextLocalizations> old,
  ) => true;
}
