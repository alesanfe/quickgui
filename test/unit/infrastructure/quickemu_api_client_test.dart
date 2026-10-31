import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/infrastructure/quickemu/api/quickemu_api_client.dart';

/// Spins up a real loopback HTTP server speaking the v1 envelope —
/// exercises the transport, envelope unwrap and error mapping
/// end-to-end without mocking the wire.
class FakeApiDaemon {
  HttpServer? _server;

  String? expectedToken;
  bool writesEnabled = true;
  Map<String, dynamic>? vmsData;
  String stateFor = 'running';
  final List<Map<String, dynamic>> receivedCommands = [];
  final List<String> receivedAuth = [];

  Future<int> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
    return _server!.port;
  }

  Future<void> stop() => _server!.close(force: true);

  void _reply(HttpResponse res, int code, Map<String, dynamic> body) {
    res
      ..statusCode = code
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  }

  void _handle(HttpRequest req) {
    receivedAuth.add(req.headers.value('authorization') ?? '');
    if (expectedToken != null &&
        req.headers.value('authorization') != 'Bearer $expectedToken') {
      _reply(req.response, 401, {
        'errors': [
          {'code': 'UNAUTHORIZED'},
        ],
      });
      return;
    }
    final path = req.uri.path;
    if (path == '/v1/health') {
      _reply(req.response, 200, {
        'data': {'ok': true},
      });
    } else if (path == '/v1/vms') {
      _reply(req.response, 200, {'data': vmsData ?? {}});
    } else if (path.startsWith('/v1/vm/') && path.endsWith('/state')) {
      _reply(req.response, 200, {
        'data': {'state': stateFor},
      });
    } else if (path.startsWith('/v1/vm/') && path.endsWith('/ops')) {
      _reply(req.response, 200, {
        'data': {
          'operations': [
            {'operationId': 'op-1', 'state': 'completed'},
          ],
        },
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
    } else if (path == '/v1/corrupt') {
      req.response
        ..statusCode = 200
        ..write('not json{')
        ..close();
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
  late FakeApiDaemon daemon;
  late QuickemuApiClient client;

  setUp(() async {
    daemon = FakeApiDaemon();
    final port = await daemon.start();
    client = QuickemuApiClient(HttpApiTransport('127.0.0.1', port));
  });

  tearDown(() => daemon.stop());

  group('probe (QG-021)', () {
    test('reachable daemon without token is writeDisabled', () async {
      final probe = await client.probe();
      expect(probe.status, ApiServiceStatus.writeDisabled);
      expect(probe.usable, isTrue);
      expect(probe.writesEnabled, isFalse);
      expect(probe.detail, contains('read-only'));
    });

    test('token makes the service ready', () async {
      final port = daemon._server!.port;
      final authed = QuickemuApiClient(
        HttpApiTransport('127.0.0.1', port),
        token: 't',
      );
      final probe = await authed.probe();
      expect(probe.status, ApiServiceStatus.ready);
      expect(probe.writesEnabled, isTrue);
    });

    test('401 maps to authRequired', () async {
      daemon.expectedToken = 'sekrit';
      final probe = await client.probe();
      expect(probe.status, ApiServiceStatus.authRequired);
      expect(probe.usable, isFalse);
    });

    test('closed port maps to unavailable', () async {
      await daemon.stop();
      final probe = await client.probe();
      expect(probe.status, ApiServiceStatus.unavailable);
      expect(probe.usable, isFalse);
      // Rebind a fresh daemon on a new port so tearDown still works.
      daemon._server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      daemon._server!.listen(daemon._handle);
    });

    test('non-envelope answer maps to incompatible', () async {
      // Simulate a foreign service answering /v1/health with junk.
      final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => foreign.close(force: true));
      foreign.listen((req) {
        req.response
          ..statusCode = 200
          ..write('<html>hello</html>')
          ..close();
      });
      final c = QuickemuApiClient(HttpApiTransport('127.0.0.1', foreign.port));
      final probe = await c.probe();
      expect(probe.status, ApiServiceStatus.incompatible);
    });
  });

  group('typed calls (QG-020)', () {
    test('vms() unwraps the data envelope', () async {
      daemon.vmsData = {
        'a': {'state': 'running'},
        'b': {'state': 'stopped'},
      };
      expect(await client.vms(), contains('a'));
    });

    test('vmState decodes running state', () async {
      final state = await client.vmState('a');
      expect(state['state'], 'running');
      daemon.stateFor = 'stopped';
      expect((await client.vmState('a'))['state'], 'stopped');
    });

    test('vmOperations returns the ops list', () async {
      final ops = await client.vmOperations('a');
      expect(ops, hasLength(1));
      expect(ops.first['operationId'], 'op-1');
    });

    test('vmCommand POSTs the whitelisted command with auth', () async {
      daemon.expectedToken = 'sekrit';
      final port = daemon._server!.port;
      final authed = QuickemuApiClient(
        HttpApiTransport('127.0.0.1', port),
        token: 'sekrit',
      );
      await authed.vmCommand('a', 'pause');
      expect(daemon.receivedCommands.single, {'vm': 'a', 'cmd': 'pause'});
      expect(daemon.receivedAuth, contains('Bearer sekrit'));
    });

    test('non-whitelisted commands are refused client-side', () {
      expect(
        () => client.vmCommand('a', 'delete-vm'),
        throwsA(
          isA<AppFailure>().having((f) => f.code, 'code', 'UNSAFE_COMMAND'),
        ),
      );
      expect(daemon.receivedCommands, isEmpty);
    });

    test('traversal-shaped VM names are refused client-side', () {
      for (final bad in ['../etc', 'a/b', 'v*', 'x[0]', r'..\win']) {
        expect(
          () => client.vmState(bad),
          throwsA(
            isA<AppFailure>().having((f) => f.code, 'code', 'INVALID_VM_NAME'),
          ),
          reason: bad,
        );
      }
    });

    test('403 maps to a WRITE_DISABLED permission failure', () {
      daemon.writesEnabled = false;
      expect(
        () => client.vmCommand('a', 'start'),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'WRITE_DISABLED')
              .having((f) => f.kind, 'kind', AppFailureKind.permission),
        ),
      );
    });

    test('errors envelopes surface a typed failure', () async {
      // A 404-only server exercises the errors-envelope branch that
      // normal endpoints never reach.
      final notFound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => notFound.close(force: true));
      notFound.listen((req) {
        req.response
          ..statusCode = 404
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'errors': [
                {'code': 'NOT_FOUND'},
              ],
            }),
          )
          ..close();
      });
      final c = QuickemuApiClient(HttpApiTransport('127.0.0.1', notFound.port));
      expect(
        c.vms(),
        throwsA(
          isA<AppFailure>().having((f) => f.code, 'code', 'API_NOT_FOUND'),
        ),
      );
    });

    test('malformed JSON maps to a contract failure', () async {
      // Reach the corrupt endpoint through the private surface by
      // pointing vms() at a server that returns junk for /v1/vms.
      final junk = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => junk.close(force: true));
      junk.listen((req) {
        req.response
          ..statusCode = 200
          ..write('not json{')
          ..close();
      });
      final c = QuickemuApiClient(HttpApiTransport('127.0.0.1', junk.port));
      expect(
        c.vms(),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.code, 'code', 'MALFORMED_JSON')
              .having((f) => f.kind, 'kind', AppFailureKind.backendContract),
        ),
      );
    });

    test('connection refused maps to a connection failure', () async {
      final c = QuickemuApiClient(
        HttpApiTransport('127.0.0.1', 1), // port 1: guaranteed closed
      );
      expect(
        c.vms(),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.kind,
            'kind',
            AppFailureKind.connection,
          ),
        ),
      );
    });
  });

  group('HTTP parsing and security helpers', () {
    test('parseHttpResponse splits status, headers and body', () {
      final res = parseHttpResponse(
        'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
        'Content-Length: 15\r\n\r\n{"data":{"a":1}}',
      );
      expect(res.statusCode, 200);
      expect(res.body, '{"data":{"a":1}}');
    });

    test('parseHttpResponse decodes chunked bodies', () {
      final res = parseHttpResponse(
        'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
        '4\r\nWiki\r\n5\r\npedia\r\n0\r\n\r\n',
      );
      expect(res.statusCode, 200);
      expect(res.body, 'Wikipedia');
    });

    test('socket permissions: 0600 clean, looser flagged (QG-021)', () {
      // Hex equivalents: 0600=0x180, 0660=0x1B0, 0644=0x1A4, 0400=0x100.
      expect(SocketSecurity.issues(0x180), isEmpty);
      expect(SocketSecurity.issues(0x1B0), isNotEmpty);
      expect(SocketSecurity.issues(0x1A4), isNotEmpty);
      expect(SocketSecurity.issues(0x100), isNotEmpty); // not writable
    });

    test('endpoint discovery prefers explicit env socket (QG-021)', () {
      final d = ApiEndpointDiscovery();
      final candidates = d.candidates(
        dataDir: '/data',
        env: {
          'QUICKEMU_API_SOCKET': '/explicit/api.sock',
          'XDG_RUNTIME_DIR': '/run/user/1000',
        },
      );
      expect(candidates, hasLength(5));
      expect(
        (candidates[0] as UnixSocketApiTransport).path,
        '/explicit/api.sock',
      );
      expect(
        (candidates[1] as UnixSocketApiTransport).path,
        '/run/user/1000/quickemu/api.sock',
      );
      expect((candidates[2] as UnixSocketApiTransport).path, '/data/api.sock');
      expect(
        (candidates[3] as UnixSocketApiTransport).path,
        '/run/quickemu/api.sock',
      );
      expect(candidates[4], isA<HttpApiTransport>());
      expect((candidates[4] as HttpApiTransport).port, 8490);
    });
  });
}
