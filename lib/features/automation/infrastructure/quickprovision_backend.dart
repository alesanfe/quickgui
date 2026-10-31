import 'dart:convert';
import 'dart:io';

import 'package:quickgui/features/automation/application/ports/automation_backend.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/process/running_proc.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';

/// AutomationBackend backed by the `quickprovision` executable. All process
/// spawns go through [ProcessRunner] so the Flatpak sandbox escape is
/// honoured exactly like the quickemu/quickget paths.
class QuickprovisionBackend implements AutomationBackend {
  const QuickprovisionBackend(this._runner);

  final ProcessRunner _runner;

  @override
  Future<bool> checkAvailability() async {
    try {
      final r = await _runner.run(quickprovisionBinary, ['--version']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> plan(String profilePath) async {
    try {
      final r = await _runner.run(quickprovisionBinary, [
        'plan',
        '--profile',
        profilePath,
      ]);
      if (r.exitCode != 0) return null;
      final decoded = jsonDecode('${r.stdout}');
      if (decoded is! Map) return null;
      // v1 envelope: {name, data: {...}} — accept a bare map too so a
      // pre-envelope binary still yields its payload.
      final data = decoded['data'] ?? decoded;
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } on ProcessException {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<RunningProc> startRun(String profilePath, String workDir) async =>
      SystemRunningProc(
        await _runner.start(quickprovisionBinary, [
          'run',
          '--profile',
          profilePath,
          '--dir',
          workDir,
        ]),
      );

  @override
  Future<RunningProc> resumeRun(String vmDir) async => SystemRunningProc(
    await _runner.start(quickprovisionBinary, ['resume', '--vmdir', vmDir]),
  );

  @override
  Future<ProcResult> cancel(String vmDir, String operationId) async {
    final r = await _runner.run(quickprovisionBinary, [
      'cancel',
      '--vmdir',
      vmDir,
      '--id',
      operationId,
    ]);
    return ProcResult(r.exitCode, r.stdout, r.stderr);
  }
}
