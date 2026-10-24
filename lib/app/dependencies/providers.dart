import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/app/globals.dart' show backend;
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Providers: the app's DI surface. The legacy `backend` global in
/// globals.dart is re-exported here so Riverpod consumers get the same
/// instance while callers migrate.
final backendProvider = Provider<VirtualizationBackend>((ref) => backend);

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
