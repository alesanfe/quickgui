import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_preferences_repository.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  String entry({
    required String kind,
    required String status,
    String target = 'vm',
    bool retryable = false,
    String code = 'X',
  }) {
    final r = retryable ? ',"retryable":true,"failureCode":"$code"' : '';
    return '{"kind":"$kind","target":"$target","startedAt":'
        '"2026-01-01T00:00:00.000Z","completedAt":'
        '"2026-01-01T00:05:00.000Z","status":"$status",'
        '"message":"m"$r}';
  }

  Future<void> pump(
    WidgetTester tester,
    FakePreferencesRepository prefs,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesRepositoryProvider.overrideWithValue(prefs)],
        child: testApp(home: const ActivityPage()),
      ),
    );
    // Let the async history restore finish.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  testWidgets('tabs filter history by status', (tester) async {
    final prefs = FakePreferencesRepository()
      ..store['activityHistory'] = [
        entry(kind: 'start', status: 'succeeded', target: 'ok-vm'),
        entry(kind: 'stop', status: 'failed', target: 'bad-vm'),
        entry(kind: 'delete', status: 'cancelled', target: 'gone-vm'),
      ];
    await pump(tester, prefs);

    // All tab: three entries visible.
    expect(find.textContaining('ok-vm'), findsOneWidget);
    expect(find.textContaining('bad-vm'), findsOneWidget);
    expect(find.textContaining('gone-vm'), findsOneWidget);

    await tester.tap(find.text('Failed (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bad-vm'), findsOneWidget);
    expect(find.textContaining('ok-vm'), findsNothing);

    await tester.tap(find.text('Cancelled (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gone-vm'), findsOneWidget);
    expect(find.textContaining('bad-vm'), findsNothing);
  });

  testWidgets('kind filter narrows entries', (tester) async {
    final prefs = FakePreferencesRepository()
      ..store['activityHistory'] = [
        entry(kind: 'start', status: 'succeeded', target: 'a'),
        entry(kind: 'delete', status: 'succeeded', target: 'b'),
      ];
    await pump(tester, prefs);

    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete — b'), findsOneWidget);
    expect(find.textContaining('Start — a'), findsNothing);
  });

  testWidgets('retryable-only filter hides plain failures', (tester) async {
    final prefs = FakePreferencesRepository()
      ..store['activityHistory'] = [
        entry(kind: 'start', status: 'failed', target: 'hard'),
        entry(
          kind: 'stop',
          status: 'failed',
          target: 'soft',
          retryable: true,
          code: 'BACKEND_TIMEOUT',
        ),
      ];
    await pump(tester, prefs);

    await tester.tap(find.text('Retryable only'));
    await tester.pumpAndSettle();
    expect(find.textContaining('soft'), findsOneWidget);
    expect(find.textContaining('hard'), findsNothing);
    expect(find.textContaining('BACKEND_TIMEOUT'), findsOneWidget);
  });

  testWidgets('empty filtered state explains filters', (tester) async {
    final prefs = FakePreferencesRepository()
      ..store['activityHistory'] = [
        entry(kind: 'start', status: 'succeeded', target: 'a'),
      ];
    await pump(tester, prefs);

    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(
      find.text('No operations match the current filters.'),
      findsOneWidget,
    );
  });
}
