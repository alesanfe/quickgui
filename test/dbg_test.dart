@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/app/theme/app_theme.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/features/settings/domain/settings_state.dart';

import '/home/alesanfe/qemu/quickgui/test/support/fakes/fake_host_probe.dart';
import '/home/alesanfe/qemu/quickgui/test/support/fakes/fake_preferences_repository.dart';
import '/home/alesanfe/qemu/quickgui/test/support/fakes/fake_virtualization_backend.dart';
import '/home/alesanfe/qemu/quickgui/test/support/harness/test_app.dart';

void main() {
  testWidgets('dbg manager', (t) async {
    t.view.physicalSize = const Size(912, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(
            FakeVirtualizationBackend()
              ..available = true
              ..vms = ['ubuntu-24.04', 'windows-11', 'debian-12'],
          ),
          hostProbeProvider.overrideWithValue(FakeHostProbe()),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          initialSettingsProvider.overrideWithValue(SettingsState()),
        ],
        child: testApp(home: const Manager()),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    print('appbars: ${find.byType(AppBar).evaluate().length}');
    print('texts: ${find.byType(Text).evaluate().length}');
    print('vm text: ${find.textContaining("ubuntu").evaluate().length}');
    print('listview: ${find.byType(ListView).evaluate().length}');
    debugDumpApp();
  });
}
