import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/vnc/rfb_client.dart';

/// Embedded console (VISTA gap): polls `quickemu --screenshot` — a QEMU
/// `screendump` in PPM format — and decodes the framebuffer in-app, so
/// common console workflows no longer depend on an external `spicy`
/// window. Text and key chords are injected as HMP `sendkey` commands;
/// [VmConnectionView] remains as the full-featured external fallback.
class VmConsolePage extends ConsumerStatefulWidget {
  const VmConsolePage({required this.vm, required this.confPath, super.key});

  /// VM name (basename of the .conf).
  final String vm;

  /// Absolute path of the .conf — forwarded to the external-viewer pane.
  final String confPath;

  @override
  ConsumerState<VmConsolePage> createState() => _VmConsolePageState();
}

class _VmConsolePageState extends ConsumerState<VmConsolePage> {
  ui.Image? _frame;
  Timer? _timer;
  bool _running = true;
  bool _busy = false;
  String? _error;
  final _text = TextEditingController();

  // VNC streaming mode — preferred when the VM publishes an RFB port.
  RfbClient? _vnc;
  StreamSubscription<List<RfbRect>>? _vncSub;
  Uint8List? _fb;
  bool _vncActive = false;
  int _pointerMask = 0;
  bool _decoding = false;

  static const _keyChords = [
    'ctrl-alt-delete',
    'ctrl-alt-f1',
    'ctrl-alt-f2',
    'alt-tab',
    'alt-f4',
    'ret',
    'esc',
    'super',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Prefers the live RFB stream when the VM publishes a VNC endpoint
  /// (`vnc,PORT,HOST` in `<vm>.ports` or `vnc_listen` in the .conf);
  /// otherwise falls back to screendump polling.
  Future<void> _init() async {
    final endpoint = _vncEndpoint();
    if (endpoint != null) {
      try {
        await _connectVnc(endpoint.$1, endpoint.$2);
        return;
      } catch (_) {
        // Fall through to screendump — the VNC server may not be up yet.
      }
    }
    _grab();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _grab());
  }

  /// Resolves the (host, port) pair QEMU's `-vnc host:display` maps to:
  /// TCP 5900 + display number. Published as `vnc,port,host` in
  /// `<vm>.ports` by quickemu; falls back to `vnc_listen` in the conf.
  (String, int)? _vncEndpoint() {
    final dir = p.dirname(widget.confPath);
    final ports = File(p.join(dir, '${widget.vm}.ports'));
    if (ports.existsSync()) {
      for (final line in ports.readAsLinesSync()) {
        final parts = line.split(',');
        if (parts.length >= 2 && parts[0] == 'vnc') {
          final port = int.tryParse(parts[1]);
          if (port != null) {
            return (parts.length > 2 ? parts[2] : '127.0.0.1', port);
          }
        }
      }
    }
    final conf = File(widget.confPath);
    if (!conf.existsSync()) return null;
    String? display;
    String? listen;
    for (final line in conf.readAsLinesSync()) {
      final m = RegExp(r'^(\w+)\s*=\s*"?([^"#]*)"?').firstMatch(line);
      if (m == null) continue;
      if (m.group(1) == 'display') display = m.group(2);
      if (m.group(1) == 'vnc_listen') listen = m.group(2);
    }
    if (display != 'vnc') return null;
    listen ??= '127.0.0.1:0';
    final i = listen.lastIndexOf(':');
    final disp = int.tryParse(i >= 0 ? listen.substring(i + 1) : listen);
    if (disp == null) return null;
    final host = (i > 0 && listen.substring(0, i).isNotEmpty)
        ? listen.substring(0, i)
        : '127.0.0.1';
    return (host, 5900 + disp);
  }

  Future<void> _connectVnc(String host, int port) async {
    final vnc = RfbClient();
    await vnc.connect(host, port);
    if (!mounted) {
      await vnc.dispose();
      return;
    }
    _vnc = vnc;
    _fb = Uint8List(vnc.width * vnc.height * 4);
    _vncSub = vnc.rects.listen(_composite);
    vnc.errors.listen((_) {
      if (mounted) _fallbackToScreendump();
    });
    setState(() {
      _vncActive = true;
      _running = true;
    });
  }

  void _fallbackToScreendump() {
    _vncSub?.cancel();
    _vncSub = null;
    unawaited(_vnc?.dispose());
    _vnc = null;
    _vncActive = false;
    _grab();
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _grab());
  }

  /// Applies one FramebufferUpdate to the pixel buffer and refreshes the
  /// decoded frame at most once per pending decode.
  void _composite(List<RfbRect> rects) {
    final fb = _fb;
    final vnc = _vnc;
    if (fb == null || vnc == null) return;
    final w = vnc.width;
    for (final r in rects) {
      if (r.isCopyRect) {
        // Region copy inside the framebuffer.
        for (var row = 0; row < r.height; row++) {
          final src = ((r.srcY! + row) * w + r.srcX!) * 4;
          final dst = ((r.y + row) * w + r.x) * 4;
          fb.setRange(dst, dst + r.width * 4, fb, src);
        }
      } else {
        final px = r.pixels!;
        for (var row = 0; row < r.height; row++) {
          final dst = ((r.y + row) * w + r.x) * 4;
          final src = row * r.width * 4;
          fb.setRange(dst, dst + r.width * 4, px, src);
          // QEMU's unused byte may be 0 — force opaque alpha.
          for (var i = dst + 3; i < dst + r.width * 4; i += 4) {
            fb[i] = 0xff;
          }
        }
      }
    }
    if (_decoding) return;
    _decoding = true;
    ui.decodeImageFromPixels(fb, w, vnc.height, ui.PixelFormat.bgra8888, (
      image,
    ) {
      _decoding = false;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _frame?.dispose();
        _frame = image;
      });
    });
  }

  /// Maps a console point (inside the fitted image) to framebuffer
  /// coordinates and forwards a PointerEvent to the guest.
  void _pointer(int mask, Offset pos, Size box) {
    final vnc = _vnc;
    if (vnc == null) return;
    final scale = (box.width / vnc.width).clamp(0.0, box.height / vnc.height);
    final dw = vnc.width * scale;
    final dh = vnc.height * scale;
    final ox = (box.width - dw) / 2;
    final oy = (box.height - dh) / 2;
    final x = ((pos.dx - ox) / scale).round().clamp(0, vnc.width - 1);
    final y = ((pos.dy - oy) / scale).round().clamp(0, vnc.height - 1);
    _pointerMask = mask;
    vnc.sendPointer(mask, x, y);
  }

  /// Typed text goes through RFB KeyEvents in VNC mode — ASCII maps 1:1,
  /// Enter/Tab/Backspace get their keysyms, uppercase adds Shift.
  void _typeRfb(String ch) {
    final vnc = _vnc;
    if (vnc == null) return;
    int keysym;
    var shift = false;
    switch (ch) {
      case '\n':
        keysym = Keysyms.enter;
      case '\t':
        keysym = Keysyms.tab;
      default:
        final c = ch.codeUnitAt(0);
        if (c >= 0x41 && c <= 0x5a) {
          shift = true;
          keysym = c + 0x20;
        } else if (c >= 0x20 && c <= 0x7e) {
          keysym = c;
        } else {
          keysym = 0x20;
        }
    }
    if (shift) vnc.sendKey(Keysyms.shiftL, down: true);
    vnc
      ..sendKey(keysym, down: true)
      ..sendKey(keysym, down: false);
    if (shift) vnc.sendKey(Keysyms.shiftL, down: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vncSub?.cancel();
    unawaited(_vnc?.dispose());
    _text.dispose();
    _frame?.dispose();
    super.dispose();
  }

  String get _tmpShot =>
      p.join(Directory.systemTemp.path, 'quickgui-console-${widget.vm}.ppm');

  Future<void> _grab() async {
    if (_busy) return;
    _busy = true;
    try {
      // QEMU screendump is an HMP monitor command — going through the
      // port's monitorCommand keeps presentation off the raw-argv path.
      final result = await ref
          .read(backendProvider)
          .monitorCommand(widget.vm, 'screendump $_tmpShot');
      if (!mounted) return;
      if (result.exitCode == 0 && File(_tmpShot).existsSync()) {
        final bytes = await File(_tmpShot).readAsBytes();
        final image = await decodePpm(bytes);
        if (!mounted) {
          image?.dispose();
          return;
        }
        setState(() {
          _frame?.dispose();
          _frame = image;
          _running = image != null;
          _error = image == null ? context.t('Unsupported framebuffer') : null;
        });
      } else {
        setState(() {
          _running = false;
          _frame?.dispose();
          _frame = null;
        });
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _send(String command) async {
    final result = await ref
        .read(backendProvider)
        .monitorCommand(widget.vm, command);
    if (!mounted) return;
    if (result.exitCode != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.stdout}${result.stderr}'.trim())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Console — {0}', args: [widget.vm])),
        actions: [
          IconButton(
            tooltip: context.t('Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _grab,
          ),
          IconButton(
            tooltip: context.t('Open external viewer'),
            icon: const Icon(Icons.open_in_new),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    VmConnectionView(vm: widget.vm, confPath: widget.confPath),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              width: double.infinity,
              // Live region: screen readers learn when the console is
              // live vs the VM having stopped.
              child: Semantics(
                liveRegion: true,
                label: _running
                    ? context.t('Live console')
                    : context.t('Machine is not running'),
                child: _running
                    ? (_frame == null
                          ? const Center(child: CircularProgressIndicator())
                          : _vncActive
                          ? LayoutBuilder(
                              builder: (context, constraints) =>
                                  GestureDetector(
                                    onTapDown: (d) => _pointer(
                                      1,
                                      d.localPosition,
                                      constraints.biggest,
                                    ),
                                    onTapUp: (d) => _pointer(
                                      0,
                                      d.localPosition,
                                      constraints.biggest,
                                    ),
                                    onSecondaryTapDown: (d) => _pointer(
                                      4,
                                      d.localPosition,
                                      constraints.biggest,
                                    ),
                                    onSecondaryTapUp: (d) => _pointer(
                                      0,
                                      d.localPosition,
                                      constraints.biggest,
                                    ),
                                    onPanUpdate: (d) => _pointer(
                                      _pointerMask,
                                      d.localPosition,
                                      constraints.biggest,
                                    ),
                                    child: FittedBox(
                                      child: RawImage(image: _frame),
                                    ),
                                  ),
                            )
                          : InteractiveViewer(
                              child: Center(child: RawImage(image: _frame)),
                            ))
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.monitor,
                              size: 64,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error ??
                                  context.t(
                                    'The machine is not running — start it to use the console.',
                                  ),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          enabled: _running,
                          decoration: InputDecoration(
                            isDense: true,
                            border: const OutlineInputBorder(),
                            labelText: context.t('Type text into the machine'),
                          ),
                          onSubmitted: (_) => _typeText(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _running ? _typeText : null,
                        child: Text(context.t('Type')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final chord in _keyChords)
                        ActionChip(
                          label: Text(chord),
                          onPressed: _running
                              ? () => _send('sendkey $chord')
                              : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _typeText() {
    final t = _text.text;
    if (t.isEmpty) return;
    _text.clear();
    for (final ch in t.split('')) {
      if (_vncActive) {
        _typeRfb(ch);
      } else {
        // --type maps chars to sendkey chords; do the same here via HMP.
        _send('sendkey ${_keyName(ch)}');
      }
    }
  }
}

/// Maps a typed character to a QEMU `sendkey` name — parity with the
/// `--type` loop in the Go CLI (letters/digits literal, shifted
/// punctuation named, uppercase via `shift-`).
String _keyName(String ch) {
  const named = {
    ' ': 'spc',
    '!': 'shift-1',
    '@': 'shift-2',
    '#': 'shift-3',
    r'$': 'shift-4',
    '%': 'shift-5',
    '^': 'shift-6',
    '&': 'shift-7',
    '*': 'shift-8',
    '(': 'shift-9',
    ')': 'shift-0',
    '-': 'minus',
    '_': 'shift-minus',
    '=': 'equal',
    '+': 'shift-equal',
    '[': 'bracket_left',
    ']': 'bracket_right',
    '{': 'shift-bracket_left',
    '}': 'shift-bracket_right',
    ';': 'semicolon',
    ':': 'shift-semicolon',
    "'": 'apostrophe',
    '"': 'shift-apostrophe',
    '`': 'grave_accent',
    '~': 'shift-grave_accent',
    r'\': 'backslash',
    '|': 'shift-backslash',
    ',': 'comma',
    '<': 'shift-comma',
    '.': 'dot',
    '>': 'shift-dot',
    '/': 'slash',
    '?': 'shift-slash',
    '\n': 'ret',
    '\t': 'tab',
  };
  if (named.containsKey(ch)) return named[ch]!;
  if (RegExp(r'^[a-z0-9]$').hasMatch(ch)) return ch;
  if (RegExp(r'^[A-Z]$').hasMatch(ch)) return 'shift-${ch.toLowerCase()}';
  return 'spc';
}

/// Decodes a binary PPM (P6) framebuffer. QEMU screendump emits
/// `P6 <w> <h> <maxval>` followed by w*h*3 bytes of RGB.
Future<ui.Image?> decodePpm(Uint8List bytes) async {
  var i = 0;
  final tokens = <int>[];
  while (tokens.length < 3 && i < bytes.length) {
    // skip whitespace and '#' comments
    while (i < bytes.length && (bytes[i] <= 0x20 || bytes[i] == 0x23)) {
      if (bytes[i] == 0x23) {
        while (i < bytes.length && bytes[i] != 0x0a) {
          i++;
        }
      } else {
        i++;
      }
    }
    var v = 0;
    final start = i;
    if (i + 1 < bytes.length &&
        bytes[i] == 0x50 /*P*/ &&
        bytes[i + 1] == 0x36 /*6*/ ) {
      tokens.add(-1); // magic consumed
      i += 2;
      continue;
    }
    while (i < bytes.length && bytes[i] > 0x20) {
      v = v * 10 + (bytes[i] - 0x30);
      i++;
    }
    if (i != start) tokens.add(v);
  }
  if (tokens.length < 3 || tokens[0] != -1) return null;
  final w = tokens[1];
  final h = tokens[2];
  i++; // single whitespace after maxval
  if (w <= 0 || h <= 0 || i + w * h * 3 > bytes.length) return null;
  final rgba = Uint8List(w * h * 4);
  for (var s = 0, d = 0; d < rgba.length; s += 3, d += 4) {
    rgba[d] = bytes[i + s];
    rgba[d + 1] = bytes[i + s + 1];
    rgba[d + 2] = bytes[i + s + 2];
    rgba[d + 3] = 0xff;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return await c.future;
}
