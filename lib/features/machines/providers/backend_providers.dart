import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/ports/vm_config_store.dart';
import 'package:quickgui/infrastructure/process/system_process_runner.dart';
import 'package:quickgui/infrastructure/quickemu/api/quickemu_api_client.dart';
import 'package:quickgui/infrastructure/quickemu/quickemu_backend.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

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
// ignore: specify_nonobvious_property_types
final vmStatsProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, vm) => ref.watch(backendProvider).vmStats(vm),
);

/// Probes the optional `quickemu-api` service across discovered
/// endpoints (QG-021). The CLI backend remains authoritative — the API
/// is an optional accelerator for status reads and whitelisted
/// lifecycle commands. Unix-socket candidates are skipped before
/// Result of probing the `quickemu-api` service: the probe itself plus
/// the transport that answered and the configured token — everything
/// the API-routing backend needs to talk to the daemon.
class ApiDiscovery {
  const ApiDiscovery(this.probe, {this.transport, this.token});

  final ApiProbe probe;
  final ApiTransport? transport;
  final String? token;

  static const unavailable = ApiDiscovery(
    ApiProbe(
      status: ApiServiceStatus.unavailable,
      detail: 'Service is not running',
    ),
  );
}

/// dialing when the file does not exist or has loose permissions.
final apiServiceProvider = FutureProvider<ApiDiscovery>((ref) async {
  final prefs = ref.read(preferencesRepositoryProvider);
  final dataDir = await prefs.getAs<String>(prefWorkingDirectory);
  final token = await prefs.getAs<String>(prefQuickemuApiToken);
  for (final transport in ApiEndpointDiscovery().candidates(dataDir: dataDir)) {
    if (transport is UnixSocketApiTransport) {
      final stat = FileStat.statSync(transport.path);
      if (stat.type == FileSystemEntityType.notFound) continue;
      if (SocketSecurity.issues(stat.mode & 0x1FF).isNotEmpty) continue;
    }
    final probe = await QuickemuApiClient(transport, token: token).probe();
    // authRequired still counts as "service found" — surfaces a
    // configuration hint rather than silently falling back to CLI.
    if (probe.usable || probe.status == ApiServiceStatus.authRequired) {
      return ApiDiscovery(probe, transport: transport, token: token);
    }
  }
  return ApiDiscovery.unavailable;
});
