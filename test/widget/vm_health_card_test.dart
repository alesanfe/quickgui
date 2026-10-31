// Widget coverage for the health card (QG-041): the checklist must
// surface each real state — healthy, agent-missing, low disk, recent
// issues, stopped — with the right severity rows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/details/vm_health_card.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';

void main() {
  late Directory dir;
  late FakeVirtualizationBackend backend;
  late FakeHostProbe host;
  late String confPath;

  setUpAll(TestLocalizationsDelegate.preload);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qg-health-');
    Directory(p.join(dir.path, 'vm1')).createSync();
    File(p.join(dir.path, 'vm1', 'vm1.ports'))
        .writeAsStringSync('spice,5930\nssh,2222\n');
    confPath = p.join(dir.path, 'vm1.conf');
    backend = FakeVirtualizationBackend();
    host = FakeHostProbe()..dir = dir.path;
  });

  tearDown(() async {
    // Windows releases file handles asynchronously — a just-read
    // journal can still be locked when teardown runs.
    for (var i = 0; i < 10; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on PathAccessException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    dir.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, {String state = 'running'}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(host),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
          // Real journal parser, sync read — async file I/O launched in
          // the fake-async zone never delivers its completion.
          vmRecentIssuesProvider.overrideWith(
            (ref, vm) =>
                VmEventLog(p.join(dir.path, vm, '$vm.events.jsonl'))
                    .recentIssueCountSync(const Duration(hours: 24)),
          ),
        ],
        child: testApp(
          home: Scaffold(
            body: ListView(
              children: [
                VmHealthCard(vm: 'vm1', confPath: confPath, state: state),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('healthy running VM shows the full checklist', (tester) async {
    backend.guestIp = {
      'ipv4': ['10.0.2.15'],
    };
    await open(tester);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('Machine state'), findsOneWidget);
    expect(find.text('Guest agent'), findsOneWidget);
    expect(find.text('Forwarded ports'), findsOneWidget);
    expect(find.text('Host disk space'), findsOneWidget);
    expect(find.text('Recent issues'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Answering — network details available.'), findsOneWidget);
  });

  testWidgets('missing agent renders the warning row', (tester) async {
    backend.guestIpError = const AppFailure(
      AppFailureKind.connection,
      'agent_not_ready',
      'guest agent is not answering',
    );
    await open(tester);
    expect(find.textContaining('qemu-guest-agent'), findsOneWidget);
  });

  testWidgets('stopped VM omits agent and port rows', (tester) async {
    await open(tester, state: 'stopped');
    expect(find.text('Machine state'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Guest agent'), findsNothing);
    expect(find.text('Forwarded ports'), findsNothing);
  });

  testWidgets('low host disk flags the warn row', (tester) async {
    host.free = 8 * 1024 * 1024 * 1024; // 8 GiB < warn threshold
    await open(tester);
    expect(find.textContaining('GiB free'), findsOneWidget);
  });

  testWidgets('journal issues in the last 24h show the count', (tester) async {
    File(p.join(dir.path, 'vm1', 'vm1.events.jsonl')).writeAsStringSync(
      '{"seq":1,"event":"vm.crashed","vm":"vm1","ts":'
      '"${DateTime.now().toIso8601String()}"}\n'
      '{"seq":2,"event":"vm.started","vm":"vm1"}\n',
    );
    await open(tester);
    expect(
      find.text('1 journal event(s) need attention (24 h).'),
      findsOneWidget,
    );
  });
}
