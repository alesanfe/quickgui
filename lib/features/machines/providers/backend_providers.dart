import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

/// The app's virtualization backend (quickemu/quickget).
final backendProvider = Provider<VirtualizationBackend>(
  (ref) => QuickemuBackend(SystemProcessRunner()),
);

/// Backend availability (quickemu+quickget on PATH).
final backendAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(backendProvider).checkAvailability(),
);

/// Detected backend version string, empty when unavailable.
final backendVersionProvider = FutureProvider<String>(
  (ref) => ref.watch(backendProvider).version(),
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

/// Global VM inventory (`--inventory` -> vms.json): the local DB of
/// every VM the backend knows about, keyed by instanceId.
final FutureProvider<Map<String, dynamic>> backendInventoryProvider =
    FutureProvider<Map<String, dynamic>>(
      (ref) => ref.watch(backendProvider).listInventory(),
    );

/// Installed plugins (`--plugins` -> quickemu-plugin-* on PATH).
final FutureProvider<List<String>> backendPluginsProvider =
    FutureProvider<List<String>>(
      (ref) => ref.watch(backendProvider).listPlugins(),
    );

/// Per-VM QMP metrics (`--stats`). Null when the VM isn't running.
final vmStatsProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, vm) => ref.watch(backendProvider).vmStats(vm),
);
