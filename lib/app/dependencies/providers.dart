import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';

/// Providers: the app's DI surface.
final backendProvider = Provider<VirtualizationBackend>(
  (ref) => QuickemuBackend(SystemProcessRunner()),
);

/// Backend availability (quickemu+quickget on PATH).
final backendAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(backendProvider).checkAvailability(),
);

/// Backend capabilities map (schema v1), null on older releases.
final backendCapabilitiesProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) {
  return ref.watch(backendProvider).getCapabilities();
});

/// OS catalogue loaded at startup; null while the backend is missing or
/// the catalogue has not been loaded yet.
final osCatalogueProvider = Provider<Future<List<OperatingSystem>>?>(
  (ref) => null,
);

/// OS icon asset paths keyed by OS code; populated at startup from the
/// bundled asset manifest.
final osIconsProvider = Provider<Map<String, String>>((ref) => const {});
