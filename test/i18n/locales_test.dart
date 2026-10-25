import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/app/localization/supported_locales.dart';

/// i18n tests: every supported locale ships a .po file, and the .pot
/// template stays parseable.
void main() {
  final translations = Directory('assets/translations');

  test('each supported locale has a .po file', () {
    for (final locale in supportedLocales) {
      final f = File('${translations.path}/$locale.po');
      expect(f.existsSync(), isTrue, reason: 'missing $locale.po');
    }
  });

  test('the .pot template exists and carries msgid entries', () {
    final pot = File('${translations.path}/quickgui.pot');
    expect(pot.existsSync(), isTrue);
    final content = pot.readAsStringSync();
    expect(content, contains('msgid'));
  });

  test('all .po files declare a Language header', () {
    for (final f in translations.listSync().where(
      (e) => e.path.endsWith('.po'),
    )) {
      final head = File(f.path).readAsStringSync();
      expect(head, contains('Language:'), reason: f.path);
    }
  });
}
