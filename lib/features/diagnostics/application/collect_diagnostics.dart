import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';
import 'package:quickgui/features/diagnostics/domain/diagnostics_report.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: collect a local diagnostics report for the diagnostics page.
class CollectDiagnostics {
  CollectDiagnostics(this._backend, this._host);
  final VirtualizationBackend _backend;
  final HostProbe _host;

  static const tools = [
    'quickemu',
    'quickget',
    'qemu-img',
    'swtpm',
    'spicy',
    'zsync',
    'socat',
  ];

  Future<Result<DiagnosticsReport>> call() async {
    try {
      final available = await _backend.checkAvailability();
      final caps = available ? await _backend.getCapabilities() : null;
      final rawFlags = caps?['capabilities'];
      final dir = await _host.workingDirectory();
      return Ok(
        DiagnosticsReport(
          quickguiVersion: _host.appVersion,
          backendAvailable: available,
          backendVersion: caps?['applicationVersion'] as String?,
          contractVersion: caps?['schemaVersion'] as int?,
          capabilities: rawFlags is Map
              ? {for (final e in rawFlags.entries) '${e.key}': e.value == true}
              : const {},
          tools: {for (final t in tools) t: await _host.hasTool(t)},
          kvmAvailable: await _host.hasKvm(),
          workingDirectory: dir,
          freeSpaceBytes: await _host.freeSpaceBytes(dir),
        ),
      );
    } on Exception catch (e) {
      return Err(
        Failure(
          'diagnostics.failed',
          'Could not collect diagnostics',
          detail: '$e',
        ),
      );
    }
  }
}
