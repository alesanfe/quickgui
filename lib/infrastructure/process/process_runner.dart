import 'dart:io';

/// Abstraction over external process execution so the backend can be
/// tested with fakes and so all quickemu invocations honour the Flatpak
/// sandbox escape.
abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

/// Decorates a [ProcessRunner] so every spawned process resolves
/// relative paths inside the working directory the app selected —
/// not the ambient process cwd, which is process-global and can be
/// deleted under us (QGUI-M-005). An explicit per-call
/// `workingDirectory` wins over the injected default.
class WorkingDirectoryRunner implements ProcessRunner {
  const WorkingDirectoryRunner(this._inner, this._workingDirectory);

  final ProcessRunner _inner;
  final String Function()? _workingDirectory;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => _inner.run(
    executable,
    arguments,
    workingDirectory: workingDirectory ?? _workingDirectory?.call(),
  );

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) => _inner.start(
    executable,
    arguments,
    workingDirectory: workingDirectory ?? _workingDirectory?.call(),
  );
}
