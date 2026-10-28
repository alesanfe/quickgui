import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/vnc/rfb_client.dart';

/// A minimal in-process RFB server: completes the handshake with canned
/// bytes, records what the client sends, and replays scripted server
/// messages.
class MockRfbServer {
  MockRfbServer._(this.server);

  final ServerSocket server;
  Socket? client;
  final received = BytesBuilder(copy: false);
  final _receivedWaiters = <Completer<void>>[];

  static Future<MockRfbServer> start() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return MockRfbServer._(s);
  }

  int get port => server.port;

  void _push(Uint8List d) {
    received.add(d);
    for (final w in List<Completer<void>>.of(_receivedWaiters)) {
      if (!w.isCompleted) w.complete();
    }
    _receivedWaiters.clear();
  }

  Future<Uint8List> take(int n) async {
    while (received.length < n) {
      final c = Completer<void>();
      _receivedWaiters.add(c);
      await c.future;
    }
    final all = received.toBytes();
    received.clear();
    return Uint8List.fromList(all.sublist(0, n));
  }

  /// Runs the scripted server side of the session.
  void serve({required List<int> serverInitTail}) {
    server.listen((sock) async {
      client = sock;
      sock.listen(_push);
      sock.add('RFB 003.008\n'.codeUnits);
      await take(12); // client version
      sock.add([2, 1, 2]); // two security types: None + VNC-auth
      await take(1); // client picks 1
      sock.add([0, 0, 0, 0]); // SecurityResult OK
      await take(1); // ClientInit
      sock.add(serverInitTail); // ServerInit
      // then read SetPixelFormat (20B) + SetEncodings (12B)
    });
  }

  void send(List<int> bytes) => client?.add(bytes);
  Future<void> close() async {
    await client?.close();
    await server.close();
  }
}

Uint8List serverInit({int w = 4, int h = 2, String name = 'qemu'}) {
  final b = BytesBuilder();
  b.add([w >> 8, w & 0xff, h >> 8, h & 0xff]);
  b.add(List.filled(16, 0)); // server pixel format (ignored)
  b.add([0, 0, 0, name.length]);
  b.add(name.codeUnits);
  return b.toBytes();
}

Uint8List frameUpdate(List<List<int>> rects) {
  final b = BytesBuilder();
  b.add([0, 0, rects.length >> 8, rects.length & 0xff]);
  for (final r in rects) {
    b.add(r);
  }
  return b.toBytes();
}

List<int> rawRect(int x, int y, int w, int h, List<int> pixels) => [
  x >> 8, x & 0xff, y >> 8, y & 0xff,
  w >> 8, w & 0xff, h >> 8, h & 0xff,
  0, 0, 0, 0, // Raw
  ...pixels,
];

void main() {
  late MockRfbServer server;
  late RfbClient client;

  setUp(() async {
    server = await MockRfbServer.start();
    client = RfbClient();
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test('handshake negotiates SecurityNone and parses ServerInit', () async {
    server.serve(serverInitTail: serverInit(w: 640, h: 480, name: 'vm1'));
    await client.connect('127.0.0.1', server.port);
    await pumpEventQueue();
    expect(client.width, 640);
    expect(client.height, 480);
    expect(client.serverName, 'vm1');
    // Client must have picked security type 1 (None).
    final fmt = await server.take(20);
    expect(fmt[0], 0); // SetPixelFormat
    expect(fmt[4], 32); // bpp
    expect(fmt[5], 24); // depth
    expect(fmt[7], 1); // trueColour
    expect(fmt[14], 16); // rshift
    expect(fmt[15], 8); // gshift
    expect(fmt[16], 0); // bshift
    final enc = await server.take(12);
    expect(enc[0], 2); // SetEncodings
    expect(enc.sublist(4, 8), [0, 0, 0, 0]); // Raw
    expect(enc.sublist(8, 12), [0, 0, 0, 1]); // CopyRect
  });

  test('parses a raw rectangle update', () async {
    server.serve(serverInitTail: serverInit(w: 8, h: 8));
    await client.connect('127.0.0.1', server.port);
    final updates = client.rects.first;
    // 1x2 rect at (3,4): pixels B,G,R,X x2
    server.send(
      frameUpdate([
        rawRect(3, 4, 1, 2, [10, 20, 30, 0, 40, 50, 60, 0]),
      ]),
    );
    final rects = await updates.timeout(const Duration(seconds: 2));
    expect(rects, hasLength(1));
    final r = rects.single;
    expect((r.x, r.y, r.width, r.height), (3, 4, 1, 2));
    expect(r.pixels!.sublist(0, 4), [10, 20, 30, 0]);
    expect(r.pixels!.sublist(4, 8), [40, 50, 60, 0]);
  });

  test('parses a CopyRect update', () async {
    server.serve(serverInitTail: serverInit());
    await client.connect('127.0.0.1', server.port);
    final updates = client.rects.first;
    server.send(
      frameUpdate([
        [0, 1, 0, 2, 0, 5, 0, 6, 0, 0, 0, 1, 0, 7, 0, 8], // x y w h enc=1 sx sy
      ]),
    );
    final r = (await updates.timeout(const Duration(seconds: 2))).single;
    expect(r.isCopyRect, isTrue);
    expect((r.srcX, r.srcY), (7, 8));
  });

  test('sendKey and sendPointer emit wire-format events', () async {
    server.serve(serverInitTail: serverInit());
    await client.connect('127.0.0.1', server.port);
    await server.take(32); // consume fmt+enc
    client.sendKey(Keysyms.enter, down: true);
    final key = await server.take(8);
    expect(key[0], 4);
    expect(key[1], 1);
    expect(ByteData.sublistView(key).getUint32(4), Keysyms.enter);
    client.sendPointer(1 | 4, 300, 200);
    final ptr = await server.take(6);
    expect(ptr, [5, 5, 1, 44, 0, 200]);
  });

  test('refuses servers without SecurityNone', () async {
    server.server.listen((sock) {
      sock.add('RFB 003.008\n'.codeUnits);
      sock.listen((_) {});
      sock.add([1, 2]); // only VNC-auth
    });
    await expectLater(
      client.connect('127.0.0.1', server.port),
      throwsA(isA<StateError>()),
    );
  });
}
