// UI <-> real CLI: pump the real machines Manager with the real
// QuickemuBackend and check the rendered state matches the CLI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/harness/test_app.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

void main() {
  final hasQemu = Process.runSync('which', ['quickemu']).exitCode == 0;

  testWidgets(
    'Manager renders VMs the real CLI reports',
    (t) async {
      final tmp = Directory.systemTemp.createTempSync('qg_ui_');
      File('${tmp.path}/realvm.conf').writeAsStringSync(
        'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\n',
      );
      // The Manager lists Directory.current, which it sets from the
      // workingDirectory preference — point it at the fixture dir.
      final prefs = FakePreferencesRepository()
        ..store[prefWorkingDirectory] = tmp.path;

      final backend = QuickemuBackend(SystemProcessRunner());
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            backendProvider.overrideWithValue(backend),
            hostProbeProvider.overrideWithValue(FakeHostProbe()),
            preferencesRepositoryProvider.overrideWithValue(prefs),
            osIconsProvider.overrideWithValue(const <String, String>{}),
            osCatalogueProvider.overrideWithValue(
              Future.value(const <OperatingSystem>[]),
            ),
          ],
          child: testApp(home: const Scaffold(body: Manager())),
        ),
      );
      // _getVms chains ~7 sequential real subprocess calls (capabilities →
      // checkAvailability(quickget+quickemu) → list → availability →
      // inspect); real IO never drains inside FakeAsync. Alternate pump
      // (start/continue the chain) and runAsync (let the in-flight
      // process finish), stopping as soon as the VM tile renders.
      var found = false;
      for (var i = 0; i < 15 && !found; i++) {
        // Small fake-clock elapse: fires the zero-delay timer that kicks
        // _getVms (pump() alone never advances the fake clock). Kept well
        // under the 5 s periodic-refresh tick so it never re-triggers.
        await t.pump(const Duration(milliseconds: 50));
        if (find.textContaining('realvm').evaluate().isNotEmpty) {
          found = true;
          break;
        }
        await t.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
      }
      await t.pump();

      final cliOut = await t.runAsync(
        () => Process.run('quickemu', [
          '--vm',
          '${tmp.path}/realvm.conf',
          '--status',
          '--format',
          'json',
        ], workingDirectory: tmp.path),
      );
      final cliState =
          jsonDecode(cliOut!.stdout as String)['data']['state'] as String;

      expect(find.textContaining('realvm'), findsWidgets);
      // The UI title-cases states ("Stopped"); the CLI reports lowercase.
      expect(
        find.textContaining(RegExp(cliState, caseSensitive: false)),
        findsWidgets,
      );
      tmp.deleteSync(recursive: true);
    },
    skip: !hasQemu,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
