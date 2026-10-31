// Widget coverage for the guest-address card in VmConnectionView
// (QG-050): each GuestIpInfo state renders a distinct, actionable UI —
// addresses, "still booting", "install the agent" — and refresh/copy
// work through the backend port, never through direct process calls.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../support/fakes/fake_host_probe.dart';
import '../support/fakes/fake_preferences_repository.dart';
import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  late Directory dir;
  late FakeVirtualizationBackend backend;
  late String confPath;

  setUpAll(TestLocalizationsDelegate.preload);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qg-gip-');
    Directory(p.join(dir.path, 'vm1')).createSync();
    File(p.join(dir.path, 'vm1', 'vm1.ports'))
        .writeAsStringSync('spice,5930\nssh,2222\n');
    confPath = p.join(dir.path, 'vm1.conf');
    backend = FakeVirtualizationBackend();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(backend),
          hostProbeProvider.overrideWithValue(FakeHostProbe()..dir = dir.path),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: testApp(
          home: Scaffold(
            body: VmConnectionView(vm: 'vm1', confPath: confPath),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ready: addresses shown grouped by family with iface', (
    tester,
  ) async {
    backend.guestIp = {
      'vm': 'vm1',
      'ipv4': ['10.0.2.15'],
      'ipv6': ['fe80::1'],
      'iface': 'enp0s3',
    };
    await open(tester);
    expect(find.text('Guest addresses'), findsOneWidget);
    expect(find.text('10.0.2.15', findRichText: true), findsOneWidget);
    expect(find.text('fe80::1', findRichText: true), findsOneWidget);
    expect(find.text('enp0s3'), findsOneWidget);
    // Port tiles still render — guest IPs complement, never replace,
    // the forwarded-port connection paths.
    expect(find.text('127.0.0.1:5930'), findsOneWidget);
    expect(find.text('127.0.0.1:2222'), findsOneWidget);
  });

  testWidgets('agent missing shows the install hint', (tester) async {
    backend.guestIpError = const AppFailure(
      AppFailureKind.connection,
      'agent_not_ready',
      'guest agent is not answering',
    );
    await open(tester);
    expect(find.text('Guest addresses'), findsOneWidget);
    expect(find.textContaining('qemu-guest-agent'), findsOneWidget);
  });

  testWidgets('no address yet shows a transient state with refresh', (
    tester,
  ) async {
    backend.guestIp = {'vm': 'vm1', 'ipv4': <String>[], 'ipv6': <String>[]};
    await open(tester);
    expect(find.textContaining('still be booting'), findsOneWidget);
    // Refresh re-queries the backend — the card's IconButton, not the
    // "Refresh ports" OutlinedButton. ensureVisible scrolls it into the
    // ListView viewport before tapping.
    backend.guestIp = {
      'ipv4': ['10.9.9.9'],
    };
    final refresh = find.widgetWithIcon(IconButton, Icons.refresh);
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(backend.guestIpCalls, 2);
    expect(find.text('10.9.9.9', findRichText: true), findsOneWidget);
  });

  testWidgets('unsupported backend hides the card entirely', (tester) async {
    await open(tester);
    expect(find.text('Guest addresses'), findsNothing);
  });

  testWidgets('generic failure shows retryable error tile', (tester) async {
    backend.guestIpError = const AppFailure(
      AppFailureKind.internal,
      'BACKEND_ERROR',
      'unexpected',
    );
    await open(tester);
    expect(find.textContaining('query failed'), findsOneWidget);
  });

  testWidgets('copy action puts the address on the clipboard', (tester) async {
    backend.guestIp = {
      'ipv4': ['10.0.2.15'],
    };
    await open(tester);
    final copy = find.byIcon(Icons.copy).first;
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(find.text('Address copied'), findsOneWidget);
  });
}
