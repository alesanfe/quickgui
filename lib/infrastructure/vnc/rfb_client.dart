import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A single framebuffer rectangle delivered by the server — either new
/// pixels (raw) or a copy of an existing region (CopyRect).
class RfbRect {
  const RfbRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.pixels,
    this.srcX,
    this.srcY,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  /// BGRA bytes (bottom byte unused/0) for raw rectangles; null for
  /// CopyRect, where [srcX]/[srcY] point at the source region.
  final Uint8List? pixels;
  final int? srcX;
  final int? srcY;

  bool get isCopyRect => pixels == null;
}

/// Minimal RFB 3.8 (RFC 6143) client — enough for QEMU/Quickemu's VNC
/// server: SecurityNone handshake, Raw + CopyRect encodings, pointer and
/// key events. No external dependencies.
///
/// Frame updates arrive on [rects] as a stream of completed updates —
/// each event is the list of rectangles in one FramebufferUpdate. The
/// client keeps requesting incremental updates until [close].
class RfbClient {
  RfbClient({this.connectTimeout = const Duration(seconds: 5)});

  final Duration connectTimeout;

  Socket? _socket;
  final _inbox = BytesBuilder(copy: false);
  final _inboxWaiters = <Completer<void>>[];
  StreamSubscription<Uint8List>? _sub;
  Timer? _updateTimer;
  bool _handshook = false;

  int width = 0;
  int height = 0;
  String serverName = '';

  final _rects = StreamController<List<RfbRect>>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  /// Completed framebuffer updates (rect lists), in wire order.
  Stream<List<RfbRect>> get rects => _rects.stream;

  /// Socket/protocol errors after connect (the connect itself throws).
  Stream<Object> get errors => _errors.stream;

  bool get connected => _handshook && _socket != null;

  Future<void> connect(String host, int port) async {
    final sock = await Socket.connect(host, port, timeout: connectTimeout);
    _socket = sock;
    _sub = sock.listen(
      _onData,
      onError: (Object e) {
        if (!_errors.isClosed) _errors.add(e);
        close();
      },
      onDone: () {
        if (!_errors.isClosed) {
          _errors.add(StateError('VNC server closed the connection'));
        }
        close();
      },
    );
    await _handshake(sock);
    _handshook = true;
    // Initial full-frame request, then keep polling incrementally so the
    // stream stays live even when QEMU holds updates back.
    _sendUpdateRequest(incremental: false);
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _sendUpdateRequest(incremental: true),
    );
    unawaited(_readLoop());
  }

  void _onData(Uint8List chunk) {
    _inbox.add(chunk);
    for (final w in List<Completer<void>>.of(_inboxWaiters)) {
      if (!w.isCompleted) w.complete();
    }
    _inboxWaiters.clear();
  }

  /// Waits until [n] bytes are buffered, then consumes and returns them.
  Future<Uint8List> _read(int n) async {
    while (_inbox.length < n) {
      if (_socket == null) {
        throw StateError('connection closed while reading $n bytes');
      }
      final c = Completer<void>();
      _inboxWaiters.add(c);
      await c.future;
    }
    final all = _inbox.toBytes();
    _inbox.clear();
    if (all.length > n) _inbox.add(all.sublist(n));
    return Uint8List.fromList(all.sublist(0, n));
  }

  Future<int> _u8() async => (await _read(1))[0];
  Future<int> _u16() async => ByteData.sublistView(await _read(2)).getUint16(0);
  Future<int> _u32() async => ByteData.sublistView(await _read(4)).getUint32(0);

  Future<void> _handshake(Socket sock) async {
    final version = await _read(12);
    final banner = String.fromCharCodes(version);
    if (!banner.startsWith('RFB ')) {
      throw StateError('not an RFB server: $banner');
    }
    sock.add('RFB 003.008\n'.codeUnits);
    final nTypes = await _u8();
    if (nTypes == 0) {
      final len = await _u32();
      final reason = String.fromCharCodes(await _read(len));
      throw StateError('RFB handshake refused: $reason');
    }
    final types = await _read(nTypes);
    if (!types.contains(1)) {
      throw StateError('server requires VNC authentication — unsupported');
    }
    sock.add([1]); // SecurityNone
    final result = await _u32();
    if (result != 0) {
      throw StateError('RFB security handshake failed ($result)');
    }
    sock.add([1]); // ClientInit: shared session
    // ServerInit
    width = await _u16();
    height = await _u16();
    await _read(16); // server pixel format — we override below
    final nameLen = await _u32();
    serverName = String.fromCharCodes(await _read(nameLen));
    // SetPixelFormat: 32bpp, depth 24, little-endian, true colour,
    // rshift=16 gshift=8 bshift=0 → wire bytes arrive as B,G,R,X.
    sock.add(const [
      0, 0, 0, 0, // type + 3 pad
      32, 24, 0, 1, // bpp, depth, bigEndian=0, trueColour=1
      0, 255, 0, 255, 0, 255, // rmax gmax bmax (u16 each)
      16, 8, 0, // rshift gshift bshift (u8 each)
      0, 0, 0, // padding
    ]);
    // SetEncodings: [Raw=0, CopyRect=1] as signed i32 each.
    sock.add(const [
      2, 0, 0, 2, // type, pad, count=2
      0, 0, 0, 0, // Raw
      0, 0, 0, 1, // CopyRect
    ]);
  }

  void _sendUpdateRequest({required bool incremental}) {
    final s = _socket;
    if (s == null) return;
    final b = ByteData(10);
    b.setUint8(0, 3);
    b.setUint8(1, incremental ? 1 : 0);
    b.setUint16(2, 0);
    b.setUint16(4, 0);
    b.setUint16(6, width);
    b.setUint16(8, height);
    s.add(b.buffer.asUint8List());
  }

  Future<void> _readLoop() async {
    try {
      while (_socket != null) {
        final type = await _u8();
        switch (type) {
          case 0: // FramebufferUpdate
            await _u8(); // padding
            final nRects = await _u16();
            final rects = <RfbRect>[];
            for (var i = 0; i < nRects; i++) {
              final x = await _u16();
              final y = await _u16();
              final w = await _u16();
              final h = await _u16();
              final enc = (await _u32()).toSigned(32);
              if (enc == 0) {
                rects.add(
                  RfbRect(
                    x: x,
                    y: y,
                    width: w,
                    height: h,
                    pixels: await _read(w * h * 4),
                  ),
                );
              } else if (enc == 1) {
                final sx = await _u16();
                final sy = await _u16();
                rects.add(
                  RfbRect(x: x, y: y, width: w, height: h, srcX: sx, srcY: sy),
                );
              } else {
                throw StateError('unsupported encoding $enc');
              }
            }
            if (!_rects.isClosed) _rects.add(rects);
          case 1: // SetColorMapEntries
            await _read(5);
            final n = await _u16();
            await _read(n * 6);
          case 2: // Bell — ignore
            break;
          case 3: // ServerCutText
            await _read(3);
            final len = await _u32();
            await _read(len);
          default:
            throw StateError('unknown server message $type');
        }
      }
    } catch (e) {
      if (!_errors.isClosed) _errors.add(e);
      close();
    }
  }

  /// Sends a key press or release. [keysym] is an X11 keysym — printable
  /// ASCII maps 1:1; specials use 0xFF00+ codes (see [Keysyms]).
  void sendKey(int keysym, {required bool down}) {
    final s = _socket;
    if (s == null) return;
    final b = ByteData(8);
    b.setUint8(0, 4);
    b.setUint8(1, down ? 1 : 0);
    b.setUint32(4, keysym);
    s.add(b.buffer.asUint8List());
  }

  /// Button mask bits: 1=left 2=middle 4=right 8=wheel-up 16=wheel-down.
  void sendPointer(int mask, int x, int y) {
    final s = _socket;
    if (s == null) return;
    s.add([5, mask, x >> 8, x & 0xff, y >> 8, y & 0xff]);
  }

  Future<void> close() async {
    _updateTimer?.cancel();
    _updateTimer = null;
    await _sub?.cancel();
    _sub = null;
    final s = _socket;
    _socket = null;
    await s?.close();
    for (final w in _inboxWaiters) {
      if (!w.isCompleted) w.complete();
    }
    _inboxWaiters.clear();
  }

  Future<void> dispose() async {
    await close();
    await _rects.close();
    await _errors.close();
  }
}

/// X11 keysyms the console needs beyond ASCII (which is its own keysym).
abstract final class Keysyms {
  static const backspace = 0xFF08;
  static const tab = 0xFF09;
  static const enter = 0xFF0D;
  static const escape = 0xFF1B;
  static const insert = 0xFF63;
  static const delete = 0xFFFF;
  static const home = 0xFF50;
  static const end = 0xFF57;
  static const pageUp = 0xFF55;
  static const pageDown = 0xFF56;
  static const left = 0xFF51;
  static const up = 0xFF52;
  static const right = 0xFF53;
  static const down = 0xFF54;
  static const f1 = 0xFFBE;
  static const f2 = 0xFFBF;
  static const f3 = 0xFFC0;
  static const f4 = 0xFFC1;
  static const f5 = 0xFFC2;
  static const f6 = 0xFFC3;
  static const f7 = 0xFFC4;
  static const f8 = 0xFFC5;
  static const f9 = 0xFFC6;
  static const f10 = 0xFFC7;
  static const f11 = 0xFFC8;
  static const f12 = 0xFFC9;
  static const shiftL = 0xFFE1;
  static const shiftR = 0xFFE2;
  static const ctrlL = 0xFFE3;
  static const ctrlR = 0xFFE4;
  static const altL = 0xFFE9;
  static const altR = 0xFFEA;
  static const superL = 0xFFEB;
}
