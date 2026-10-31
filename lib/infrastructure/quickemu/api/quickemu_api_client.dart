import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quickgui/core/errors/app_failure.dart';

/// High-level health of the quickemu API service, phrased for
/// non-technical display (QG-021).
enum ApiServiceStatus {
  /// Reachable, correct envelope, ready for requests.
  ready,

  /// The daemon requires a Bearer token that is not configured.
  authRequired,

  /// Reachable for reads but mutating calls are disabled
  /// (daemon started without `--token`).
  writeDisabled,

  /// Socket/listener exists but nothing answers, or the envelope is
  /// not the v1 shape — likely an old or foreign service.
  incompatible,

  /// Nothing listening on the endpoint — fall back to CLI.
  unavailable,
}

/// Result of [QuickemuApiClient.probe].
class ApiProbe {
  const ApiProbe({
    required this.status,
    this.writesEnabled = false,
    this.detail = '',
  });

  final ApiServiceStatus status;

  /// True when mutating `/v1/vm-cmd` calls are authorised.
  final bool writesEnabled;

  /// Friendly one-line status, e.g. "Service ready".
  final String detail;

  bool get usable =>
      status == ApiServiceStatus.ready ||
      status == ApiServiceStatus.writeDisabled;
}

/// Wire response from an [ApiTransport].
class ApiResponse {
  const ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// One HTTP request to the API endpoint. `body` is a JSON-encoded
/// string for POSTs.
abstract class ApiTransport {
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, String>? headers,
    String? body,
  });
}

/// Loopback-TCP transport (`quickemu-api --listen 127.0.0.1:8490`).
class HttpApiTransport implements ApiTransport {
  HttpApiTransport(this.host, this.port);

  final String host;
  final int port;

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.openUrl(
        method,
        Uri.parse('http://$host:$port$path'),
      );
      headers?.forEach(req.headers.add);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(body);
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      return ApiResponse(res.statusCode, text);
    } finally {
      client.close();
    }
  }
}

/// HTTP/1.1 over a unix socket (`quickemu-api --listen /path/api.sock`).
/// Minimal framing: one request per connection, `Connection: close`.
class UnixSocketApiTransport implements ApiTransport {
  UnixSocketApiTransport(this.path);

  final String path;

  @override
  Future<ApiResponse> send(
    String method,
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 5),
    );
    try {
      final buf = StringBuffer()
        ..write('$method $path HTTP/1.1\r\n')
        ..write('Host: localhost\r\n')
        ..write('Connection: close\r\n');
      headers?.forEach((k, v) => buf.write('$k: $v\r\n'));
      if (body != null) {
        buf
          ..write('Content-Type: application/json\r\n')
          ..write('Content-Length: ${utf8.encode(body).length}\r\n');
      }
      buf.write('\r\n');
      socket.add(utf8.encode(buf.toString()));
      if (body != null) socket.add(utf8.encode(body));
      await socket.flush();
      final raw = await socket.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      return parseHttpResponse(utf8.decode(raw));
    } finally {
      await socket.close();
    }
  }
}

/// Parses a raw HTTP/1.1 response into status + body. Kept separate so
/// both transports and tests share one parser.
ApiResponse parseHttpResponse(String raw) {
  final split = raw.indexOf('\r\n\r\n');
  final head = split < 0 ? raw : raw.substring(0, split);
  var body = split < 0 ? '' : raw.substring(split + 4);
  final status =
      int.tryParse(
        RegExp(r'^HTTP/\d\.\d (\d{3})').firstMatch(head)?.group(1) ?? '',
      ) ??
      0;
  // The daemon only emits identity-encoded bodies; a chunked body is
  // decoded so tests against real servers stay simple.
  final headers = head.toLowerCase();
  if (headers.contains('transfer-encoding: chunked')) {
    body = _decodeChunked(body);
  }
  return ApiResponse(status, body);
}

String _decodeChunked(String raw) {
  final out = StringBuffer();
  var rest = raw;
  while (rest.isNotEmpty) {
    final nl = rest.indexOf('\r\n');
    if (nl < 0) break;
    final size = int.tryParse(rest.substring(0, nl).trim(), radix: 16) ?? 0;
    if (size == 0) break;
    rest = rest.substring(nl + 2);
    if (rest.length < size) break;
    out.write(rest.substring(0, size));
    rest = rest.substring(size + 2); // trailing CRLF
  }
  return out.toString();
}

/// Discovers candidate API endpoints without touching the network
/// (QG-021): default loopback TCP plus well-known socket locations.
class ApiEndpointDiscovery {
  /// Environment variable a user/packaging can set to pin the socket.
  static const socketEnv = 'QUICKEMU_API_SOCKET';

  /// Default loopback port chosen by the daemon.
  static const defaultPort = 8490;

  /// Candidate transports in preference order: explicit socket env,
  /// runtime-dir socket, data-dir socket, then loopback TCP.
  List<ApiTransport> candidates({String? dataDir, Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final paths = <String>[
      if (e[socketEnv] case final p? when p.isNotEmpty) p,
      if (e['XDG_RUNTIME_DIR'] case final d? when d.isNotEmpty)
        '$d/quickemu/api.sock',
      if (dataDir != null) '$dataDir/api.sock',
      '/run/quickemu/api.sock',
    ];
    return [
      for (final p in paths) UnixSocketApiTransport(p),
      HttpApiTransport('127.0.0.1', defaultPort),
    ];
  }
}

/// Filesystem checks for a unix socket before trusting it (QG-021):
/// the daemon creates it 0600; anything looser may have been replaced
/// by another process/user and must not receive the bearer token.
class SocketSecurity {
  /// Returns human-readable issues for [modeBits]
  /// (`FileStat.mode & 0777`). Empty list = safe to use.
  static List<String> issues(int modeBits) {
    final problems = <String>[];
    // Any group/other permission bit set — the daemon creates 0600.
    if (modeBits & 0x3F != 0) {
      problems.add('socket is accessible by group/others');
    }
    // Owner-write bit (0200 octal = 0x80) missing.
    if (modeBits & 0x80 == 0) {
      problems.add('socket is not owner-writable');
    }
    return problems;
  }
}

/// Typed client for the `quickemu-api` daemon (QG-020/QG-021). Every
/// call is connection-per-request (`Connection: close`), so a daemon
/// restart needs no special reconnect logic — the next call re-dials.
class QuickemuApiClient {
  QuickemuApiClient(this._transport, {this.token});

  final ApiTransport _transport;

  /// Optional Bearer token — required by the daemon for writes.
  final String? token;

  /// Mutating commands whitelisted by the daemon (`/v1/vm-cmd`).
  static const safeCommands = {
    'start',
    'stop',
    'shutdown',
    'pause',
    'resume',
    'kill',
    'reset',
  };

  Map<String, String> get _headers => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  /// Health + capability probe (QG-021). Maps wire failures to
  /// friendly [ApiServiceStatus] instead of leaking socket errors.
  Future<ApiProbe> probe() async {
    ApiResponse res;
    try {
      res = await _transport.send('GET', '/v1/health', headers: _headers);
    } on SocketException {
      return const ApiProbe(
        status: ApiServiceStatus.unavailable,
        detail: 'Service is not running',
      );
    } on TimeoutException {
      return const ApiProbe(
        status: ApiServiceStatus.unavailable,
        detail: 'Service did not respond in time',
      );
    } on HandshakeException {
      return const ApiProbe(
        status: ApiServiceStatus.incompatible,
        detail: 'Endpoint is not the quickemu service',
      );
    } catch (_) {
      return const ApiProbe(
        status: ApiServiceStatus.unavailable,
        detail: 'Service is unreachable',
      );
    }
    if (res.statusCode == 401) {
      return const ApiProbe(
        status: ApiServiceStatus.authRequired,
        detail: 'Service requires an access token',
      );
    }
    final data = _envelopeData(res);
    if (data == null || data['ok'] != true) {
      return const ApiProbe(
        status: ApiServiceStatus.incompatible,
        detail: 'Service answered with an unexpected format',
      );
    }
    // Probe write capability with the daemon's own rule: writes need
    // a configured token.
    return ApiProbe(
      status: token != null
          ? ApiServiceStatus.ready
          : ApiServiceStatus.writeDisabled,
      writesEnabled: token != null,
      detail: token != null
          ? 'Service ready'
          : 'Service ready (read-only — no token configured)',
    );
  }

  /// `GET /v1/vms` — the daemon's merged VM registry.
  Future<Map<String, dynamic>> vms() async =>
      _requireData(await _get('/v1/vms'), 'vms');

  /// `GET /v1/vm/<name>/state` — running/stopped plus runtime detail.
  Future<Map<String, dynamic>> vmState(String vm) async =>
      _requireData(await _get('/v1/vm/${_checkedVm(vm)}/state'), 'state');

  /// `GET /v1/vm/<name>/ops` — recorded async operations for the VM.
  Future<List<dynamic>> vmOperations(String vm) async {
    final data = _requireData(
      await _get('/v1/vm/${_checkedVm(vm)}/ops'),
      'operations',
    );
    final ops = data['operations'];
    return ops is List ? ops : const [];
  }

  /// `POST /v1/vm-cmd` — whitelisted lifecycle commands only.
  Future<Map<String, dynamic>> vmCommand(String vm, String cmd) async {
    if (!safeCommands.contains(cmd)) {
      throw const AppFailure(
        AppFailureKind.validation,
        'UNSAFE_COMMAND',
        'That command is not allowed through the quickemu service',
      );
    }
    final res = await _send(
      'POST',
      '/v1/vm-cmd/',
      body: jsonEncode({'vm': _checkedVm(vm), 'cmd': cmd}),
    );
    return _requireData(res, 'vm-cmd');
  }

  /// VM names feed server-side globs and path joins — the daemon
  /// rejects traversal, and the client refuses to even send it.
  String _checkedVm(String vm) {
    if (vm.isEmpty ||
        vm.contains('..') ||
        RegExp(r'[/\\?*\[\]]').hasMatch(vm)) {
      throw const AppFailure(
        AppFailureKind.validation,
        'INVALID_VM_NAME',
        'Invalid machine name',
      );
    }
    return vm;
  }

  Future<ApiResponse> _get(String path) => _send('GET', path);

  Future<ApiResponse> _send(String method, String path, {String? body}) async {
    try {
      return await _transport.send(method, path, headers: _headers, body: body);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw const AppFailure(
        AppFailureKind.timeout,
        'API_TIMEOUT',
        'The quickemu service did not respond in time',
      );
    } catch (e) {
      throw AppFailure(
        AppFailureKind.connection,
        'API_UNREACHABLE',
        'The quickemu service is unreachable',
        cause: e,
      );
    }
  }

  /// Unwraps `{data: ...}` / maps `{errors: ...}` and HTTP errors onto
  /// typed [AppFailure]s — never returns an untyped exception.
  Map<String, dynamic>? _envelopeData(ApiResponse res) {
    if (res.statusCode == 401) {
      throw const AppFailure(
        AppFailureKind.permission,
        'AUTH_REQUIRED',
        'The quickemu service requires an access token',
      );
    }
    if (res.statusCode == 403) {
      throw const AppFailure(
        AppFailureKind.permission,
        'WRITE_DISABLED',
        'The service was started without a token — writes disabled',
      );
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      json = decoded;
    } catch (_) {
      return null;
    }
    final errors = json['errors'];
    if (errors is List && errors.isNotEmpty) {
      final code = '${(errors.first as Map?)?['code'] ?? 'API_ERROR'}';
      throw AppFailure(
        code == 'INVALID_ARGUMENT'
            ? AppFailureKind.validation
            : AppFailureKind.internal,
        'API_$code',
        'The quickemu service rejected the request ($code)',
      );
    }
    final data = json['data'];
    return data is Map<String, dynamic> ? data : null;
  }

  Map<String, dynamic> _requireData(ApiResponse res, String what) {
    final data = _envelopeData(res);
    if (data == null) {
      throw AppFailure(
        AppFailureKind.backendContract,
        'MALFORMED_JSON',
        'The service returned an unexpected $what payload',
      );
    }
    return data;
  }
}
