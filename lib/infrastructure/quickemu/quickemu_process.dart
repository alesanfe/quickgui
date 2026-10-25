import 'dart:io';

import 'package:quickgui/infrastructure/process/process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_contract.dart';

/// Process boundary for the quickemu toolchain binaries.
class QuickemuProcess {
  const QuickemuProcess(this._runner);

  final ProcessRunner _runner;

  Future<ProcessResult> quickemu(List<String> arguments) =>
      _runner.run(quickemuBinary, arguments);

  Future<ProcessResult> quickget(List<String> arguments) =>
      _runner.run(quickgetBinary, arguments);

  Future<ProcessResult> quickreport() => _runner.run(quickreportBinary, []);

  Future<ProcessResult> chunkcheck(String isoPath) =>
      _runner.run(chunkcheckBinary, [isoPath]);

  Future<Process> startQuickget(List<String> arguments) =>
      _runner.start(quickgetBinary, arguments);
}
