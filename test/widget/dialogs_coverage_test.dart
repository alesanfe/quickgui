import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/presentation/operation_tile.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/ssh_connect_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/stop_vm_dialog.dart';

import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

import 'package:quickgui/features/machines/application/ports/proc.dart';

Widget _launcher(void Function(BuildContext) go) {
  return ProviderScope(
    child: testApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => go(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  testWidgets('HistoryEntryTile renders each status', (tester) async {
    for (final status in OperationStatus.values) {
      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: HistoryEntryTile(
              entry: OperationHistoryEntry(
                id: 'id-${status.name}',
                kind: OperationKind.download,
                target: 'ubuntu',
                startedAt: DateTime(2026),
                completedAt: DateTime(2026, 1, 1, 0, 30),
                status: status,
                message: 'm',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HistoryEntryTile), findsOneWidget);
    }
  });

  testWidgets('stop dialog offers graceful and forced paths', (tester) async {
    final backend = FakeVirtualizationBackend();
    await tester.pumpWidget(
      _launcher(
        (context) => showStopVmDialog(
          context,
          backend: backend,
          vm: 'win10',
          confPath: '/tmp/win10.conf',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('win10'), findsWidgets);
    // Dismiss
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('process output dialog shows merged output', (tester) async {
    await tester.pumpWidget(
      _launcher(
        (context) => showProcessOutputDialog(context, [
          const ProcResult(1, 'some output', 'some error'),
        ]),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('some output'), findsWidgets);
  });

  testWidgets('process output dialog ignores empty output', (tester) async {
    await tester.pumpWidget(
      _launcher(
        (context) =>
            showProcessOutputDialog(context, [const ProcResult(0, '', '')]),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('ssh dialog asks for user and connects', (tester) async {
    final backend = FakeVirtualizationBackend();
    final prefs = FakePreferencesRepository();
    await tester.pumpWidget(
      _launcher(
        (context) => showSshConnectDialog(
          context,
          backend: backend,
          prefs: prefs,
          vm: 'vm1',
          sshPort: '2222',
          terminalEmulator: 'xterm',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('connection view renders for a stopped vm', (tester) async {
    final backend = FakeVirtualizationBackend();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [backendProvider.overrideWithValue(backend)],
        child: testApp(
          home: const Scaffold(
            body: VmConnectionView(vm: 'x', confPath: '/nonexistent/x.conf'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VmConnectionView), findsOneWidget);
  });
}
