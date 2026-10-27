// UI <-> real CLI: pump the real machines Manager with the real
// QuickemuBackend and check the rendered state matches the CLI.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('Manager renders VMs the real CLI reports', (t) async {
    final tmp = Directory.systemTemp.createTempSync('qg_ui_');
    File('${tmp.path}/realvm.conf').writeAsStringSync(
      'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\n',
    );

    final backend = QuickemuBackend(SystemProcessRunner());
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(FakeHostProbe()),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          osIconsProvider.overrideWithValue(const <String, String>{}),
          osCatalogueProvider.overrideWithValue(
            Future.value(const <OperatingSystem>[]),
          ),
        ],
        child: testApp(home: const Scaffold(body: Manager())),
      ),
    );
    await t.pump();
    await t.pump(const Duration(seconds: 2));

    final cliOut = await Process.run('quickemu', [
      '--vm',
      '${tmp.path}/realvm.conf',
      '--status',
      '--format',
      'json',
    ], workingDirectory: tmp.path);
    final cliState =
        jsonDecode(cliOut.stdout as String)['data']['state'] as String;

    expect(find.textContaining('realvm'), findsWidgets);
    expect(find.textContaining(cliState), findsWidgets);
    tmp.deleteSync(recursive: true);
  }, skip: !hasQemu);
}
