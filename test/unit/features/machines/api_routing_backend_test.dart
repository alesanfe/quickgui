import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/providers/api_routing_backend_provider.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/quickemu/api/quickemu_api_client.dart';

import '../../../support/fakes/fake_virtualization_backend.dart';

/// Real loopback daemon speaking the v1 envelope — exercises the
/// routing decisions end-to-end without mocking the wire.
class FakeApiDaemon {
  late HttpServer _server;

  bool writesEnabled = true;
  Map<String, dynamic> vmsData = {};
  Map<String, dynamic> stateData = {'state': 'running'};
  List<Map<String, dynamic>> opsData = const [];
  final List<Map<String, dynamic>> receivedCommands = [];

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
    return _server.port;
  }

  Future<void> stop() => _server.close(force: true);

  void _reply(HttpResponse res, int code, Map<String, dynamic> body) {
    res
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  void _handle(HttpRequest req) {
    final path = req.uri.path;
    if (path == '/v1/vms') {
      _reply(req.response, 200, {'data': vmsData});
    } else if (path.startsWith('/v1/vm/') && path.endsWith('/state')) {
      _reply(req.response, 200, {'data': stateData});
    } else if (path.startsWith('/v1/vm/') && path.endsWith('/ops')) {
      _reply(req.response, 200, {
        'data': {'operations': opsData},
      });
    } else if (path == '/v1/vm-cmd/' && req.method == 'POST') {
      if (!writesEnabled) {
        _reply(req.response, 403, {
          'errors': [
            {'code': 'WRITE_DISABLED'},
          ],
        });
        return;
      }
      utf8.decoder.bind(req).join().then((body) {
        receivedCommands.add(jsonDecode(body) as Map<String, dynamic>);
        _reply(req.response, 200, {
          'data': {'accepted': true},
        });
      });
    } else {
      _reply(req.response, 404, {
        'errors': [
          {'code': 'NOT_FOUND'},
        ],
      });
    }
  }
}

void main() {
  final daemon = FakeApiDaemon();
  late int port;
  late FakeVirtualizationBackend cli;

  ApiRoutingBackend routing({bool writes = true}) => ApiRoutingBackend(
    cli,
    HttpApiTransport('127.0.0.1', port),
    token: writes ? 'tok' : null,
    writesEnabled: writes,
  );

  setUpAll(() async {
    port = await daemon.start();
  });

  tearDownAll(daemon.stop);

  setUp(() {
    cli = FakeVirtualizationBackend();
    daemon.receivedCommands.clear();
    daemon.writesEnabled = true;
    daemon.vmsData = {};
    daemon.stateData = {'state': 'running'};
    daemon.opsData = const [];
  });

  group('reads route to the API', () {
    test('listVirtualMachines comes from /v1/vms', () async {
      daemon.vmsData = {
        'b': {'vm': 'b'},
        'a': {'vm': 'a'},
      };
      cli.vms = ['cli-vm'];
      expect(await routing().listVirtualMachines(), ['a', 'b']);
    });

    test('listInventory comes from /v1/vms', () async {
      daemon.vmsData = {
        'a': {'vm': 'a', 'state': 'running'},
      };
      expect(await routing().listInventory(), daemon.vmsData);
    });

    test('inspectVirtualMachine maps daemon state', () async {
      daemon.stateData = {
        'state': 'running',
        'runtime': {'pid': 42},
      };
      final data = await routing().inspectVirtualMachine('vm1');
      expect(data['state'], 'running');
      expect(data['pid'], 42);
    });

    test('listOperations maps daemon ops', () async {
      daemon.opsData = [
        {'operationId': 'op-9', 'state': 'completed'},
      ];
      final ops = await routing().listOperations('vm1');
      expect(ops.single['operationId'], 'op-9');
    });
  });

  group('mutations route to the API only when writes are enabled', () {
    test('whitelisted command posts to /v1/vm-cmd', () async {
      await routing().runVmJson('start', ['--vm', 'vm1.conf']);
      expect(daemon.receivedCommands.single, {'vm': 'vm1', 'cmd': 'start'});
      expect(cli.jsonCalls, isEmpty);
    });

    test('powerdown maps to the daemon shutdown verb', () async {
      await routing().runVmJson('powerdown', ['--vm', 'vm1.conf']);
      expect(daemon.receivedCommands.single['cmd'], 'shutdown');
    });

    test('monitor-cmd system_reset maps to reset', () async {
      await routing().runVmJson('monitor-cmd', [
        '--vm',
        'vm1.conf',
        'system_reset',
      ]);
      expect(daemon.receivedCommands.single['cmd'], 'reset');
    });

    test('read-only mode keeps mutations on the CLI', () async {
      cli.jsonResponses['start'] = {'ok': true};
      await routing(writes: false).runVmJson('start', ['--vm', 'vm1.conf']);
      expect(daemon.receivedCommands, isEmpty);
      expect(cli.jsonCalls.single.first, 'start');
    });

    test('unsupported commands stay on the CLI even with writes', () async {
      cli.jsonResponses['doctor'] = {'ok': true};
      await routing().runVmJson('doctor', ['--vm', 'vm1.conf']);
      expect(daemon.receivedCommands, isEmpty);
      expect(cli.jsonCalls.single.first, 'doctor');
    });
  });

  group('fallback behaviour', () {
    test('API transport failure falls back to the CLI read', () async {
      final dead = ApiRoutingBackend(
        cli,
        HttpApiTransport('127.0.0.1', 1), // nothing listening
      );
      cli.vms = ['cli-vm'];
      expect(await dead.listVirtualMachines(), ['cli-vm']);
    });

    test('write-denied daemon falls back to the CLI', () async {
      daemon.writesEnabled = false;
      cli.jsonResponses['start'] = {'ok': true};
      await routing().runVmJson('start', ['--vm', 'vm1.conf']);
      expect(cli.jsonCalls.single.first, 'start');
    });

    test('names the daemon would reject fall back to the CLI', () async {
      cli.jsonResponses['start'] = {'ok': true};
      // `[odd].conf` produces a basename the daemon's glob guard rejects.
      await routing().runVmJson('start', ['--vm', '[odd].conf']);
      expect(daemon.receivedCommands, isEmpty);
      expect(cli.jsonCalls.single.first, 'start');
    });

    test('missing --vm argument stays on the CLI', () async {
      cli.jsonResponses['start'] = {'ok': true};
      await routing().runVmJson('start', ['--display', 'spice']);
      expect(daemon.receivedCommands, isEmpty);
      expect(cli.jsonCalls.single.first, 'start');
    });

    test('CLI-only methods never touch the API', () async {
      cli.capabilities = {'schema': 'v1'};
      final b = routing();
      expect(await b.getCapabilities(), {'schema': 'v1'});
      await b.listTrash();
      await b.diagnosticsReport();
      expect(daemon.receivedCommands, isEmpty);
    });
  });

  group('provider wiring', () {
    test('returns the raw CLI backend when the probe is not usable', () {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(cli),
          apiServiceProvider.overrideWith(
            (ref) async => ApiDiscovery.unavailable,
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(apiRoutingBackendProvider), same(cli));
    });

    test('wraps the CLI backend when the daemon is usable', () async {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(cli),
          apiServiceProvider.overrideWith(
            (ref) async => ApiDiscovery(
              const ApiProbe(status: ApiServiceStatus.ready),
              transport: HttpApiTransport('127.0.0.1', port),
              token: 'tok',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(apiServiceProvider.future);
      expect(
        container.read(apiRoutingBackendProvider),
        isA<ApiRoutingBackend>(),
      );
    });

    test('read-only probe produces a wrapper with writes disabled', () async {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWithValue(cli),
          apiServiceProvider.overrideWith(
            (ref) async => ApiDiscovery(
              const ApiProbe(status: ApiServiceStatus.writeDisabled),
              transport: HttpApiTransport('127.0.0.1', port),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(apiServiceProvider.future);
      final backend = container.read(apiRoutingBackendProvider);
      expect(backend, isA<ApiRoutingBackend>());
      expect((backend as ApiRoutingBackend).writesEnabled, isFalse);
    });
  });
}
