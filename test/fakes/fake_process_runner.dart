import 'dart:io';

import 'package:quickgui/infrastructure/process/process_runner.dart';

/// Records invocations and returns canned results.
class FakeProcessRunner implements ProcessRunner {
  final results = <String, ProcessResult>{};
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    return results[executable] ?? ProcessResult(0, 0, '', '');
  }

  @override
  Future<Process> start(String executable, List<String> arguments) {
    calls.add([executable, ...arguments]);
    return Process.start('echo', []);
  }
}
