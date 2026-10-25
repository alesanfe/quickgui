import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/shared/dialogs/conf_conflict.dart';

import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  /// Pumps the harness and opens the dialog; returns the completer
  /// whose future resolves when the dialog pops with its result.
  Future<Completer<ConfConflictResult?>> open(
    WidgetTester tester, {
    required String original,
    required String local,
    required String disk,
  }) async {
    final done = Completer<ConfConflictResult?>();
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                done.complete(
                  await showConfConflictDialog(
                    context,
                    confPath: 'vm.conf',
                    original: original,
                    local: local,
                    disk: disk,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return done;
  }

  testWidgets('non-conflicting changes merge automatically', (tester) async {
    final done = await open(
      tester,
      original: 'ram="4G"\ndisk="64G"\n',
      local: 'ram="8G"\ndisk="64G"\n',
      disk: 'ram="4G"\ndisk="64G"\nextra="1"\n',
    );
    await tester.pumpAndSettle();
    expect(find.text('All changes can be merged.'), findsOneWidget);
    await tester.tap(find.text('Merge and save'));
    await tester.pumpAndSettle();
    final result = await tester.runAsync(() => done.future);
    expect(result?.action, ConfConflictAction.merge);
    expect(result?.merged, contains('ram="8G"'));
    expect(result?.merged, contains('extra="1"'));
  });

  testWidgets('conflict blocks merge until resolved per key', (tester) async {
    final done = await open(
      tester,
      original: 'ram="4G"\n',
      local: 'ram="6G"\n',
      disk: 'ram="8G"\n',
    );
    await tester.pumpAndSettle();
    expect(find.text('Merge and save'), findsOneWidget);
    final mergeBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Merge and save'),
    );
    expect(mergeBtn.onPressed, isNull);

    await tester.ensureVisible(find.text('Use all local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use all local'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge and save'));
    await tester.pumpAndSettle();
    final result = await tester.runAsync(() => done.future);
    expect(result?.merged, contains('ram="6G"'));
  });

  testWidgets('use all on-disk resolves every conflict', (tester) async {
    final done = await open(
      tester,
      original: 'ram="4G"\ncpu="2"\n',
      local: 'ram="6G"\ncpu="4"\n',
      disk: 'ram="8G"\ncpu="8"\n',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use all on-disk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge and save'));
    await tester.pumpAndSettle();
    final result = await tester.runAsync(() => done.future);
    expect(result?.merged, contains('ram="8G"'));
    expect(result?.merged, contains('cpu="8"'));
  });
}
