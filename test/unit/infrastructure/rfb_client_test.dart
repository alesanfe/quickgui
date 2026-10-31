import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/vnc/rfb_client.dart';

/// A minimal in-process RFB server: completes the handshake with canned
/// bytes, records what the client sends, and replays scripted server
/// messages.
///
/// Handshake bytes the server *reads* (client version, security choice,
/// ClientInit) are consumed on a private buffer so they can never race
/// with the test-side take/takeMessage reads on [received].
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
    if (all.length > n) received.add(all.sublist(n));
    return Uint8List.fromList(all.sublist(0, n));
  }

  /// Reads the next client→server message of type [type], discarding
  /// any other message types (the client's periodic
  /// FramebufferUpdateRequests interleave otherwise).
  Future<Uint8List> takeMessage(int type) async {
    for (;;) {
      final t = (await take(1))[0];
      switch (t) {
        case 0: // SetPixelFormat — fixed 19B tail
          final rest = await take(19);
          if (t == type) return Uint8List.fromList([t, ...rest]);
        case 2: // SetEncodings — 3B pad+count, then count u32s
          final hdr = await take(3);
          final count = ByteData.sublistView(hdr).getUint16(1);
          final body = await take(count * 4);
          if (t == type) {
            return Uint8List.fromList([t, ...hdr, ...body]);
          }
        case 3: // FramebufferUpdateRequest — fixed 9B tail; skip
          await take(9);
        case 4: // KeyEvent — fixed 7B tail
          final rest = await take(7);
          if (t == type) return Uint8List.fromList([t, ...rest]);
        case 5: // PointerEvent — fixed 5B tail
          final rest = await take(5);
          if (t == type) return Uint8List.fromList([t, ...rest]);
        case 6: // ClientCutText — 7B pad+len, then len bytes
          final hdr = await take(7);
          final len = ByteData.sublistView(hdr).getUint32(3);
          final body = await take(len);
          if (t == type) {
            return Uint8List.fromList([t, ...hdr, ...body]);
          }
        default:
          throw StateError('unknown client message type $t');
      }
    }
  }

  /// Runs the scripted server side of the session. Handshake bytes are
  /// read from a private inbox — never [received].
  void serve({required List<int> serverInitTail}) {
    server.listen((sock) {
      client = sock;
      var forwarded = false;
      final inbox = BytesBuilder(copy: false);
      final inboxWaiters = <Completer<void>>[];

      Future<Uint8List> readWire(int n) async {
        while (inbox.length < n) {
          final c = Completer<void>();
          inboxWaiters.add(c);
          await c.future;
        }
        final all = inbox.toBytes();
        inbox.clear();
        if (all.length > n) inbox.add(all.sublist(n));
        return Uint8List.fromList(all.sublist(0, n));
      }

      sock.listen((d) {
        if (forwarded) {
          _push(d);
          return;
        }
        inbox.add(d);
        for (final w in List<Completer<void>>.of(inboxWaiters)) {
          if (!w.isCompleted) w.complete();
        }
        inboxWaiters.clear();
      });

      () async {
        sock.add('RFB 003.008\n'.codeUnits);
        await readWire(12); // client version
        sock.add([2, 1, 2]); // two security types: None + VNC-auth
        await readWire(1); // client picks 1
        sock.add([0, 0, 0, 0]); // SecurityResult OK
        await readWire(1); // ClientInit
        sock.add(serverInitTail); // ServerInit
        forwarded = true;
        // Any surplus already-read bytes belong to the post-handshake
        // stream — hand them to received.
        if (inbox.length > 0) {
          _push(inbox.toBytes());
          inbox.clear();
        }
      }();
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
    final fmt = await server.takeMessage(0);
    expect(fmt[4], 32); // bpp
    expect(fmt[5], 24); // depth
    expect(fmt[7], 1); // trueColour
    expect(fmt[14], 16); // rshift
    expect(fmt[15], 8); // gshift
    expect(fmt[16], 0); // bshift
    final enc = await server.takeMessage(2);
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
    client.sendKey(Keysyms.enter, down: true);
    final key = await server.takeMessage(4);
    expect(key[1], 1); // down
    expect(ByteData.sublistView(key).getUint32(4), Keysyms.enter);
    client.sendPointer(1 | 4, 300, 200);
    final ptr = await server.takeMessage(5);
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
