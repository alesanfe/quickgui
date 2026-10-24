import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes/fake_virtualization_backend.dart';

import 'package:quickgui/app/app.dart';
import 'package:quickgui/app/globals.dart';
import 'package:quickgui/app/settings/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeVirtualizationBackend()..vms = ['vm1'];
  });

  testWidgets('app builds a MaterialApp with a fake backend', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>(
        create: (_) => AppSettings(),
        child: const App(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
