import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/automation/presentation/automation_page.dart';
import 'package:quickgui/features/automation/providers/automation_providers.dart';

import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  testWidgets('renders the profile form when quickprovision is available', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          automationAvailableProvider.overrideWith((ref) async => true),
        ],
        child: testApp(home: const AutomationPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Machine'), findsOneWidget);
    expect(find.text('Operating system'), findsOneWidget);
    expect(find.text('Preview plan'), findsOneWidget);
    expect(find.text('Start automation run'), findsOneWidget);
    // No OS picked yet — actions stay disabled.
    final start = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start automation run'),
    );
    expect(start.onPressed, isNull);
  });

  testWidgets('shows the unavailable notice when quickprovision is missing', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          automationAvailableProvider.overrideWith((ref) async => false),
        ],
        child: testApp(home: const AutomationPage()),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text('The quickprovision binary was not found on PATH.'),
      findsOneWidget,
    );
    expect(find.text('Machine'), findsNothing);
  });
}
