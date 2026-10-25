import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/diagnostics/application/collect_diagnostics.dart';
import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';
import 'package:quickgui/features/diagnostics/domain/diagnostics_report.dart';
import 'package:quickgui/features/diagnostics/infrastructure/system_host_probe.dart';

/// Host probe; overridden with a fake in tests.
final Provider<HostProbe> hostProbeProvider = Provider<HostProbe>(
  (ref) => SystemHostProbe(ref.watch(preferencesRepositoryProvider)),
);

/// Diagnostics report; `ref.invalidate(diagnosticsProvider)` refreshes it.
final FutureProvider<DiagnosticsReport> diagnosticsProvider =
    FutureProvider<DiagnosticsReport>((ref) async {
      final result = await CollectDiagnostics(
        ref.watch(backendProvider),
        ref.watch(hostProbeProvider),
      )();
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw Exception(
          failure.detail ?? failure.message,
        ),
      };
    });
