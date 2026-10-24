import 'dart:io';

import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Test double for VirtualizationBackend. Tests configure the fields
/// they need; unused members throw UnimplementedError.
class FakeVirtualizationBackend implements VirtualizationBackend {
  bool available = true;
  Map<String, dynamic>? capabilities;
  List<List<String>> catalog = const [];
  List<String> vms = const [];
  Map<String, Map<String, dynamic>> states = const {};
  List<String> downloadOutput = const [];
  ProcessResult? lastActionResult;

  @override
  Future<bool> checkAvailability() async => available;

  @override
  Future<String> version() async => '0.0.0-fake';

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
  Future<Process> startDownloadImage(
    String os,
    String release,
    String option,
  ) => throw UnimplementedError();

  @override
  Future<ProcessResult> runAction(List<String> arguments) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> runQuickget(List<String> arguments) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> exportVm(String vmName) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> verifyImage(String isoPath) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> killVmProcess(String vmName) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> openVmFolder(String vmName) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

  @override
  Future<ProcessResult> launchSpiceViewer(String spicePort) async =>
      lastActionResult ?? ProcessResult(0, 0, '', '');

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
}
