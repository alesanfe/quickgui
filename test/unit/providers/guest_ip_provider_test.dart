// Covers guestIpProvider (QG-050): it must translate the backend's
// data map AND its typed failures into the GuestIpInfo states the UI
// renders — "agent not installed" is a hint, other failures surface.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/domain/guest_ip.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

import '../../support/fakes/fake_host_probe.dart';
import '../../support/fakes/fake_preferences_repository.dart';
import '../../support/fakes/fake_virtualization_backend.dart';

void main() {
  late FakeVirtualizationBackend backend;
  late ProviderContainer container;

  Future<GuestIpInfo> read() =>
      container.read(guestIpProvider('vm1.conf').future);

  setUp(() {
    backend = FakeVirtualizationBackend();
    container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(
          FakePreferencesRepository(),
        ),
        hostProbeProvider.overrideWithValue(FakeHostProbe()),
        backendProvider.overrideWithValue(backend),
        apiServiceProvider.overrideWithValue(
          const AsyncValue.data(ApiDiscovery.unavailable),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('addresses from the backend map to ready', () async {
    backend.guestIp = {
      'vm': 'vm1',
      'ipv4': ['10.0.2.15'],
      'ipv6': ['fe80::1'],
      'iface': 'enp0s3',
    };
    final info = await read();
    expect(info.status, GuestIpStatus.ready);
    expect(info.ipv4, ['10.0.2.15']);
    expect(info.ipv6, ['fe80::1']);
    expect(info.iface, 'enp0s3');
    expect(backend.guestIpCalls, 1);
  });

  test('null data -> unsupported (old backend)', () async {
    final info = await read();
    expect(info.status, GuestIpStatus.unsupported);
  });

  test('empty data -> noAddress', () async {
    backend.guestIp = {'vm': 'vm1', 'ipv4': <String>[], 'ipv6': <String>[]};
    expect((await read()).status, GuestIpStatus.noAddress);
  });

  test('agent-missing QGA code -> agentMissing hint state', () async {
    backend.guestIpError = const AppFailure(
      AppFailureKind.connection,
      'agent_not_ready',
      'guest agent is not answering',
      retryable: true,
    );
    expect((await read()).status, GuestIpStatus.agentMissing);
  });

  test('unrelated failure surfaces as provider error, not a state', () async {
    backend.guestIpError = const AppFailure(
      AppFailureKind.internal,
      'BACKEND_ERROR',
      'unexpected',
    );
    final sub = container.listen(
      guestIpProvider('vm1.conf'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    AsyncValue<GuestIpInfo> state = const AsyncLoading();
    for (var i = 0; i < 50; i++) {
      state = container.read(guestIpProvider('vm1.conf'));
      if (state is! AsyncLoading) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(state.hasError, isTrue, reason: 'state was: $state');
    expect(state.error, isA<AppFailure>());
  });

  test('invalidation re-queries the backend', () async {
    backend.guestIp = {
      'ipv4': ['10.0.0.1'],
    };
    await read();
    backend.guestIp = {
      'ipv4': ['10.0.0.2'],
    };
    container.invalidate(guestIpProvider('vm1.conf'));
    expect((await read()).ipv4, ['10.0.0.2']);
    expect(backend.guestIpCalls, 2);
  });
}
