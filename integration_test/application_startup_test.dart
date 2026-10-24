import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickgui/app/app.dart';
import 'package:quickgui/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Quickgui e2e', () {
    testWidgets('app boots to the main page', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));
      expect(find.byType(App), findsOneWidget);
    });
  });
}
