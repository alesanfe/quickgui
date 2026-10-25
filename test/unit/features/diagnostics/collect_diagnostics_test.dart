import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/diagnostics/application/collect_diagnostics.dart';
import 'package:quickgui/features/diagnostics/domain/diagnostics_report.dart';

import '../../../support/fakes/fake_host_probe.dart';
import '../../../support/fakes/fake_virtualization_backend.dart';

void main() {
  final caps = jsonDecode(
    File(
      'test/support/fixtures/backend-responses/quickqemu-v1/capabilities.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;

  test('builds a report from backend capabilities and host facts', () async {
    final backend = FakeVirtualizationBackend()..capabilities = caps;
    final r = await CollectDiagnostics(backend, FakeHostProbe())();
    final report = (r as Ok<DiagnosticsReport>).value;
    expect(report.backendAvailable, isTrue);
    expect(report.backendVersion, '4.9.9');
    expect(report.contractVersion, 1);
    expect(report.contractCompatible, isTrue);
    expect(report.capabilities['snapshots'], isTrue);
    expect(report.capabilities['safeDeletePlan'], isFalse);
    expect(report.tools['quickemu'], isTrue);
    expect(report.tools['swtpm'], isFalse);
    expect(report.quickguiVersion, '1.2.3');
  });

  test('missing backend yields an unavailable report, not a failure', () async {
    final backend = FakeVirtualizationBackend()..available = false;
    final r = await CollectDiagnostics(backend, FakeHostProbe())();
    final report = (r as Ok<DiagnosticsReport>).value;
    expect(report.backendAvailable, isFalse);
    expect(report.capabilities, isEmpty);
    expect(report.contractVersion, isNull);
  });

  test('future contract versions are flagged incompatible', () {
    const r = DiagnosticsReport(
      quickguiVersion: 'x',
      backendAvailable: true,
      contractVersion: 2,
      kvmAvailable: true,
      workingDirectory: '/',
    );
    expect(r.contractCompatible, isFalse);
  });

  test('sanitised text hides the home directory', () async {
    final r = await CollectDiagnostics(
      FakeVirtualizationBackend()..capabilities = caps,
      FakeHostProbe(),
    )();
    final text = (r as Ok<DiagnosticsReport>).value.toSanitizedText(
      homeDirectory: '/home/tester',
    );
    expect(text, contains('Working directory: ~/vms'));
    expect(text, isNot(contains('/home/tester')));
    expect(text, contains('swtpm: missing'));
  });
}
