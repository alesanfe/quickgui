import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  testWidgets('shows tool status with text, not only colour', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(
            FakeVirtualizationBackend()
              ..capabilities = {
                'schemaVersion': 1,
                'applicationVersion': '4.9.9',
                'capabilities': {'snapshots': true},
              },
          ),
          hostProbeProvider.overrideWithValue(FakeHostProbe()),
        ],
        child: testApp(home: const DiagnosticsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4.9.9'), findsOneWidget);
    expect(find.text('swtpm'), findsOneWidget);
    expect(find.text('Missing'), findsWidgets);
    expect(find.text('snapshots'), findsOneWidget);
  });
}
