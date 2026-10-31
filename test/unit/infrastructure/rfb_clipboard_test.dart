import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/vnc/rfb_client.dart';

import 'rfb_client_test.dart';

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

  test('ServerCutText surfaces on the cutText stream (guest→host)', () async {
    server.serve(serverInitTail: serverInit());
    await client.connect('127.0.0.1', server.port);
    final texts = client.cutText.first;
    // type=3, 3 pad, u32 len, payload "hola"
    server.send([3, 0, 0, 0, 0, 0, 0, 4, ...'hola'.codeUnits]);
    expect(await texts.timeout(const Duration(seconds: 2)), 'hola');
  });

  test('sendCutText emits ClientCutText wire format (host→guest)', () async {
    server.serve(serverInitTail: serverInit());
    await client.connect('127.0.0.1', server.port);
    client.sendCutText('hi');
    final msg = await server.takeMessage(6);
    expect(msg[0], 6); // ClientCutText
    expect(ByteData.sublistView(msg).getUint32(4), 2);
    expect(msg.sublist(8), 'hi'.codeUnits);
  });

  test('sendCutText replaces non-Latin-1 with ?', () async {
    server.serve(serverInitTail: serverInit());
    await client.connect('127.0.0.1', server.port);
    client.sendCutText('a€b'); // € is U+20AC — out of Latin-1
    final msg = await server.takeMessage(6);
    expect(msg.sublist(8), [0x61, 0x3f, 0x62]); // a ? b
  });
}
