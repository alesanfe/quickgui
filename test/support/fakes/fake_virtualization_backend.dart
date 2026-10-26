import 'dart:io';

import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

import 'fake_process.dart';

/// Test double for VirtualizationBackend. Tests configure the fields
/// they need; unused members throw UnimplementedError.
class FakeVirtualizationBackend implements VirtualizationBackend {
  bool available = true;
  Map<String, dynamic>? capabilities;
  List<List<String>> catalog = const [];
  List<String> vms = const [];
  Map<String, Map<String, dynamic>> states = const {};
  List<Map<String, dynamic>> snapshots = const [];
  List<String> downloadOutput = const [];
  FakeProcess? downloadProcess;
  Error? downloadError;
  final List<List<String>> downloadCalls = [];
  ProcessResult? lastActionResult;
  final List<List<String>> actionCalls = [];
  final List<List<String>> quickgetCalls = [];
  final List<String> exportCalls = [];
  final List<String> folderCalls = [];
  String backendVersion = '0.0.0-fake';

  @override
  Future<bool> checkAvailability() async => available;

  @override
  Future<String> version() async => backendVersion;

  @override
  Future<Map<String, dynamic>?> getCapabilities() async => capabilities;

  @override
  Future<List<List<String>>> listOperatingSystems() async => catalog;

  @override
  Future<List<String>> listVirtualMachines() async => vms;

  @override
  Future<Map<String, dynamic>> inspectVirtualMachine(String vm) async =>
      states[vm] ?? {'name': vm, 'state': 'stopped', 'pid': null};

  @override
  Future<List<Map<String, dynamic>>> listSnapshots(String confPath) async =>
      snapshots;

  @override
  Future<Process> startDownloadImage(
    String os,
    String release,
    String option,
  ) async {
    downloadCalls.add([os, release, option]);
    if (downloadError != null) throw downloadError!;
    final process = downloadProcess;
    if (process == null) throw UnimplementedError('no downloadProcess set');
    return process;
  }

  @override
  Future<ProcessResult> runAction(List<String> arguments) async {
    actionCalls.add(List.of(arguments));
    return lastActionResult ?? ProcessResult(0, 0, '', '');
  }

  /// Structured-contract calls, recorded separately from [actionCalls]
  /// so tests can assert the legacy path independently of the
  /// envelope attempt.
  final List<List<String>> jsonCalls = [];

  /// Configured per-command `data` payloads for [runVmJson]. When a
  /// command has no entry the fake behaves like a pre-contract backend
  /// and throws an envelope-absence failure — callers exercising the
  /// structured path must opt in via [jsonResponses].
  final Map<String, Map<String, dynamic>> jsonResponses = {};

  @override
  Future<Map<String, dynamic>> runVmJson(
    String command,
    List<String> arguments, {
    Future<void>? cancelSignal,
  }) async {
    jsonCalls.add([command, ...arguments]);
    final response = jsonResponses[command];
    if (response == null) {
      throw const AppFailure(
        AppFailureKind.backendContract,
        'EMPTY_RESPONSE',
        'fake backend: no structured envelope configured',
      );
    }
    return response;
  }

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) async {
    quickgetCalls.add(List.of(arguments));
    return lastActionResult ?? ProcessResult(0, 0, '', '');
  }

  @override
  Future<ProcessResult> exportVm(String vmName) async {
    exportCalls.add(vmName);
    return lastActionResult ?? ProcessResult(0, 0, '', '');
  }

  @override
  Future<ProcessResult> verifyImage(String isoPath) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> killVmProcess(String vmName) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> openVmFolder(String vmName) async {
    folderCalls.add(vmName);
    return lastActionResult ?? ProcessResult(0, 0, '', '');
  }

  @override
  Future<ProcessResult> launchSpiceViewer(
    String spicePort, {
    String viewer = 'spicy',
    bool fullscreen = false,
  }) async => lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> forgetSshHostKey(String sshPort) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> connectSsh({
    required String terminalEmulator,
    required String user,
    required String sshPort,
  }) async => lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> diagnosticsReport() async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  final List<List<String>> convertCalls = [];

  @override
  Future<ProcessResult> convertDiskImage(
    String inputPath,
    String outputPath,
  ) async {
    convertCalls.add([inputPath, outputPath]);
    return lastActionResult ?? ProcessResult(0, 0, '', '');
  }
}
