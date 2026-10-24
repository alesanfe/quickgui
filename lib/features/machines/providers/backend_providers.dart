import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/vm_config.dart';

/// The app's virtualization backend (quickemu/quickget).
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

/// .conf file access behind the [VmConfigStore] port.
final vmConfigStoreProvider = Provider<VmConfigStore>(
  (ref) => const VmConfigFileStore(),
);
