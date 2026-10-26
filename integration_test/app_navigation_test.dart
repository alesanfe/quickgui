// Proper e2e: boots the real app via main() and drives navigation
// through page objects — POM per Martin Fowler's pattern: tests read
// as user journeys, locators live in the page objects.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickgui/main.dart' as app;

import 'pages/app_pages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot -> navigate machines -> diagnostics -> back', (t) async {
    await app.main();
    await t.pumpAndSettle(const Duration(seconds: 3));

    final menu = LeftMenuPage(t);
    final machines = MachinesPage(t);
    final diag = DiagnosticsPageObject(t);

    expect(machines.isVisible, isTrue);

    if (menu.diagnostics.evaluate().isNotEmpty) {
      await menu.goToDiagnostics();
      expect(diag.backendOk, isTrue);
      await menu.goToMachines();
      expect(machines.isVisible, isTrue);
    }
  });
}
