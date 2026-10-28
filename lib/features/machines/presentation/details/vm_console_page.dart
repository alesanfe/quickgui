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
    _grab();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _grab());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    // --type maps chars to sendkey chords; do the same here via HMP.
    for (final ch in t.split('')) {
      _send('sendkey ${_keyName(ch)}');
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
