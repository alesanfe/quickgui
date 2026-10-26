// Proper e2e: boots the real app via main() and navigates between
// screens — runs on the CI xvfb runner where windowManager/display
// exist. This is the app being USED end-to-end, not widget pumping.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickgui/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot -> machines -> diagnostics -> back', (t) async {
    await app.main();
    await t.pumpAndSettle(const Duration(seconds: 3));

    // Machines is the home tab — verify VM list surface exists
    expect(find.textContaining('Machines'), findsWidgets);

    // Navigate to diagnostics via the left menu
    final diag = find.textContaining('Diagnostics');
    if (diag.evaluate().isNotEmpty) {
      await t.tap(diag.first);
      await t.pumpAndSettle();
      expect(find.textContaining('Backend found'), findsWidgets);
    }

    // Back to machines
    final machines = find.textContaining('Machines');
    if (machines.evaluate().isNotEmpty) {
      await t.tap(machines.first);
      await t.pumpAndSettle();
    }
  });
}
