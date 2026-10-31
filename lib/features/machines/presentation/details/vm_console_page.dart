import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/infrastructure/vnc/console_scale.dart';
import 'package:quickgui/infrastructure/vnc/keymap.dart';
import 'package:quickgui/infrastructure/vnc/reconnect_policy.dart';
import 'package:quickgui/infrastructure/vnc/rfb_client.dart';
import 'package:window_manager/window_manager.dart';

/// Embedded console: prefers a live RFB/VNC stream (full physical
/// keyboard, pointer, clipboard sync, scaling, fullscreen, reconnection
/// with backoff) and falls back to `quickemu --screenshot` screendump
/// polling when the VM exposes no VNC endpoint.
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

class _VmConsolePageState extends ConsumerState<VmConsolePage>
    with WidgetsBindingObserver {
  ui.Image? _frame;
  Timer? _timer;
  bool _running = true;
  bool _busy = false;
  String? _error;
  final _text = TextEditingController();

  // VNC streaming mode — preferred when the VM publishes an RFB port.
  RfbClient? _vnc;
  StreamSubscription<List<RfbRect>>? _vncSub;
  StreamSubscription<String>? _cutSub;
  Uint8List? _fb;
  bool _vncActive = false;
  int _pointerMask = 0;
  bool _decoding = false;

  // Physical keyboard (QG-001): tracked keysyms so nothing stays
  // "pressed" in the guest when focus is lost.
  final _keyFocus = FocusNode(debugLabel: 'console');
  final _keyTracker = RfbKeyTracker();
  bool _grabbed = false;
  bool _prefGrab = true;

  // Scaling (QG-004).
  ConsoleScaleMode _scaleMode = ConsoleScaleMode.fit;
  double _zoom = 1.0;
  final _scrollX = ScrollController();
  final _scrollY = ScrollController();

  // Clipboard (QG-005).
  bool _clipboardSync = true;

  // Fullscreen (QG-003).
  bool _fullscreen = false;
  bool _overlayVisible = true;
  Timer? _overlayTimer;

  // Reconnection (QG-006).
  static const _reconnectPolicy = ReconnectPolicy();
  VncConnectionState _vncState = VncConnectionState.connecting;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  bool _everConnected = false;

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
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _init();
  }

  /// Console preferences — grab/clipboard toggles are global, the scale
  /// mode is remembered per VM (QG-004).
  Future<void> _loadPrefs() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    final grab = await prefs.getAs<bool>(prefConsoleKeyboardGrab);
    final clip = await prefs.getAs<bool>(prefConsoleClipboardSync);
    final scale = await prefs.getAs<String>(
      '$prefConsoleScaleMode${widget.vm}',
    );
    if (!mounted) return;
    setState(() {
      _prefGrab = grab ?? true;
      _clipboardSync = clip ?? true;
      _scaleMode = consoleScaleModeParse(scale);
    });
  }

  Future<void> _savePref(String key, Object? value) =>
      ref.read(preferencesRepositoryProvider).set(key, value);

  /// Prefers the live RFB stream when the VM publishes a VNC endpoint
  /// (`vnc,PORT,HOST` in `<vm>.ports` or `vnc_listen` in the .conf);
  /// otherwise falls back to screendump polling.
  Future<void> _init() async {
    final endpoint = _vncEndpoint();
    if (endpoint != null) {
      _connectVncWithRetry(endpoint.$1, endpoint.$2);
      return;
    }
    _fallbackToScreendump();
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

  // ------------------------------------------------------------------
  // Connection + reconnection (QG-006)
  // ------------------------------------------------------------------

  /// Drives the connect → retry → give-up cycle. The first successful
  /// connection marks [_everConnected] so later drops read as
  /// "connection lost" rather than "VM starting".
  void _connectVncWithRetry(String host, int port) {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(
      _connectVnc(host, port).then((ok) {
        if (!mounted || ok) return;
        setState(() {
          _vncState = _everConnected
              ? VncConnectionState.reconnecting
              : VncConnectionState.starting;
        });
        _scheduleRetry(host, port);
      }),
    );
  }

  Future<bool> _connectVnc(String host, int port) async {
    final vnc = RfbClient();
    try {
      await vnc.connect(host, port);
    } catch (e) {
      AppLog.vmLifecycle.info('VNC connect to $host:$port failed: $e');
      await vnc.dispose();
      return false;
    }
    if (!mounted) {
      await vnc.dispose();
      return true;
    }
    _vnc = vnc;
    // Re-allocate on resolution change after reconnect (QG-006).
    _fb = Uint8List(vnc.width * vnc.height * 4);
    _vncSub = vnc.rects.listen(_composite);
    _cutSub = vnc.cutText.listen(_onGuestCutText);
    vnc.errors.listen((_) => _onVncLost(host, port));
    setState(() {
      _vncActive = true;
      _running = true;
      _everConnected = true;
      _retryAttempt = 0;
      _vncState = VncConnectionState.connected;
    });
    return true;
  }

  void _onVncLost(String host, int port) {
    if (!mounted || !_vncActive) return;
    _releaseAllKeys();
    _vncSub?.cancel();
    _vncSub = null;
    _cutSub?.cancel();
    _cutSub = null;
    unawaitedLogged(_vnc?.dispose(), AppLog.vmLifecycle, 'dispose vnc');
    _vnc = null;
    _vncActive = false;
    setState(() {
      _vncState = _everConnected
          ? VncConnectionState.reconnecting
          : VncConnectionState.starting;
    });
    AppLog.vmLifecycle.warning(
      'VNC connection lost for ${widget.vm} '
      '(state: $_vncState)',
    );
    _scheduleRetry(host, port);
  }

  /// Schedules the next attempt with exponential backoff; exhausting
  /// [ReconnectPolicy.maxAttempts] drops to screendump polling instead
  /// of retrying forever.
  void _scheduleRetry(String host, int port) {
    if (!mounted || _timer != null) return; // already on screendump
    if (!_reconnectPolicy.canRetry(_retryAttempt)) {
      AppLog.vmLifecycle.warning(
        'VNC reconnect attempts exhausted for ${widget.vm} — '
        'falling back to screendump',
      );
      _fallbackToScreendump();
      return;
    }
    final delay = _reconnectPolicy.delayFor(_retryAttempt);
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!mounted) return;
      unawaited(
        _connectVnc(host, port).then((ok) {
          if (!mounted) return;
          if (!ok) _scheduleRetry(host, port);
        }),
      );
    });
    if (mounted) setState(() {});
  }

  /// Cancels pending reconnects — called when the VM is stopped from
  /// the console toolbar and on dispose.
  void _cancelReconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _fallbackToScreendump() {
    _cancelReconnect();
    _releaseAllKeys();
    _vncSub?.cancel();
    _vncSub = null;
    _cutSub?.cancel();
    _cutSub = null;
    unawaitedLogged(_vnc?.dispose(), AppLog.vmLifecycle, 'dispose vnc');
    _vnc = null;
    _vncActive = false;
    _vncState = VncConnectionState.failed;
    _grab();
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _grab());
  }

  /// Guest pushed text via ServerCutText → host clipboard.
  Future<void> _onGuestCutText(String text) async {
    if (!_clipboardSync || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  // ------------------------------------------------------------------
  // Physical keyboard (QG-001/QG-002)
  // ------------------------------------------------------------------

  /// Handles a hardware key event while the console has focus.
  /// Returns handled so nothing bubbles to app shortcuts while grabbed.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;

    // Release combo Ctrl+Alt+G — checked before forwarding so it never
    // reaches the guest (QG-002). Either left/right Ctrl counts.
    if (key == LogicalKeyboardKey.keyG &&
        event is KeyDownEvent &&
        (_keyTracker.isHeld(LogicalKeyboardKey.controlLeft) ||
            _keyTracker.isHeld(LogicalKeyboardKey.controlRight)) &&
        (_keyTracker.isHeld(LogicalKeyboardKey.altLeft) ||
            _keyTracker.isHeld(LogicalKeyboardKey.altRight))) {
      _releaseGrab();
      return KeyEventResult.handled;
    }

    // F11 toggles fullscreen host-side; everything else goes to the
    // guest (QG-003).
    if (key == LogicalKeyboardKey.f11 && event is KeyDownEvent) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // In fullscreen the only way out besides F11 is Esc *when the
    // keyboard is not grabbed* — grabbed Esc belongs to the guest.
    if (key == LogicalKeyboardKey.escape &&
        _fullscreen &&
        !_grabbed &&
        event is KeyDownEvent) {
      _setFullscreen(false);
      return KeyEventResult.handled;
    }

    if (!_grabbed || !_vncActive) return KeyEventResult.ignored;

    final keysym = rfbKeysymFor(event);
    if (keysym == null || keysym < 0) return KeyEventResult.handled;

    final vnc = _vnc;
    if (vnc == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      vnc.sendKey(_keyTracker.recordDown(key, keysym), down: true);
    } else if (event is KeyUpEvent) {
      final held = _keyTracker.release(key);
      vnc.sendKey(held ?? keysym, down: false);
    }
    return KeyEventResult.handled;
  }

  /// Sends key-up for every tracked key — prevents "stuck" guest keys
  /// (QG-001 acceptance: release on focus loss and console close).
  void _releaseAllKeys() {
    final vnc = _vnc;
    if (vnc == null) {
      _keyTracker.releaseAll();
      return;
    }
    for (final keysym in _keyTracker.releaseAll()) {
      vnc.sendKey(keysym, down: false);
    }
  }

  /// Ctrl+Alt+G (or losing the window) drops the grab: release the
  /// guest keys first, then unfocus so host shortcuts work again.
  void _releaseGrab() {
    _releaseAllKeys();
    setState(() => _grabbed = false);
    _keyFocus.unfocus();
  }

  void _requestGrab() {
    if (!_prefGrab || !_vncActive) return;
    _keyFocus.requestFocus();
    setState(() => _grabbed = true);
    _armOverlayTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Minimise/background while a key is held would stick it guest-side
    // without this (QG-002: release on minimise).
    if (state != AppLifecycleState.resumed) {
      _releaseAllKeys();
      if (_grabbed) setState(() => _grabbed = false);
    }
  }

  // ------------------------------------------------------------------
  // Framebuffer
  // ------------------------------------------------------------------

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

  /// Forwards a PointerEvent to the guest. The GestureDetector lives
  /// inside the framebuffer-sized child, so [pos] already arrives in
  /// framebuffer coordinates regardless of the active scale mode —
  /// FittedBox performs the display transform.
  void _pointer(int mask, Offset pos) {
    final vnc = _vnc;
    if (vnc == null) return;
    _pointerMask = mask;
    vnc.sendPointer(
      mask,
      pos.dx.round().clamp(0, vnc.width - 1),
      pos.dy.round().clamp(0, vnc.height - 1),
    );
  }

  // ------------------------------------------------------------------
  // Fullscreen (QG-003)
  // ------------------------------------------------------------------

  Future<void> _toggleFullscreen() => _setFullscreen(!_fullscreen);

  Future<void> _setFullscreen(bool value) async {
    if (_fullscreen == value) return;
    setState(() => _fullscreen = value);
    try {
      await windowManager.setFullScreen(value);
    } catch (e) {
      AppLog.vmLifecycle.warning('setFullScreen($value) failed: $e');
    }
    _armOverlayTimer();
  }

  /// Fullscreen overlay auto-hides after a few idle seconds; any
  /// pointer activity re-arms it so the release shortcut stays visible.
  void _armOverlayTimer() {
    _overlayTimer?.cancel();
    setState(() => _overlayVisible = true);
    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  // ------------------------------------------------------------------
  // Clipboard (QG-005)
  // ------------------------------------------------------------------

  /// Host → guest: pushes clipboard text as ClientCutText. Multi-line
  /// content asks for confirmation first — pasting several lines into a
  /// console can execute commands unintentionally.
  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (!mounted || text == null || text.isEmpty) return;
    final risky = await ref
        .read(preferencesRepositoryProvider)
        .getAs<bool>(prefConfirmRiskyActions);
    if (text.contains('\n') && (risky ?? true)) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.t('Paste into console')),
          content: Text(
            context.t(
              'The clipboard contains {0} lines. Sending them will type '
              'each line into the guest — continue?',
              args: ['\n'.allMatches(text).length + 1],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.t('Paste')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    _vnc?.sendCutText(text);
  }

  static const _chordConfirmPrefixes = {'ctrl-alt-delete'};

  /// QEMU `sendkey` chords — sensitive ones ask first (QG-005).
  Future<void> _sendChord(String chord) async {
    if (_chordConfirmPrefixes.contains(chord)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.t('Send {0}', args: [chord])),
          content: Text(
            context.t(
              'This sends a system-level key combination to the guest. '
              'Continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.t('Send')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _send('sendkey $chord');
  }

  // ------------------------------------------------------------------
  // Screendump fallback (unchanged behaviour)
  // ------------------------------------------------------------------

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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelReconnect();
    _releaseAllKeys(); // QG-001: never leave keys held in the guest
    _timer?.cancel();
    _overlayTimer?.cancel();
    _vncSub?.cancel();
    _cutSub?.cancel();
    unawaitedLogged(_vnc?.dispose(), AppLog.vmLifecycle, 'dispose vnc');
    _scrollX.dispose();
    _scrollY.dispose();
    _keyFocus.dispose();
    _text.dispose();
    _frame?.dispose();
    if (_fullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(context.t('Console — {0}', args: [widget.vm])),
              actions: _consoleActions(context),
            ),
      body: Column(
        children: [
          Expanded(
            child: MouseRegion(
              onHover: (_) {
                if (_fullscreen) _armOverlayTimer();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _consoleBody(context, scheme),
                  if (_fullscreen) _fullscreenOverlay(context),
                  if (_vncActive && _grabbed) _grabIndicator(context),
                  if (_vncActive && _scaleMode == ConsoleScaleMode.manual)
                    _zoomControls(context),
                  if (_vncState == VncConnectionState.reconnecting ||
                      _vncState == VncConnectionState.starting)
                    _reconnectBanner(context),
                ],
              ),
            ),
          ),
          if (!_fullscreen) _controlsBar(context),
        ],
      ),
    );
  }

  List<Widget> _consoleActions(BuildContext context) {
    return [
      // Keyboard-grab toggle (QG-002) — visible state at all times.
      IconButton(
        tooltip: _grabbed
            ? context.t('Release keyboard (Ctrl+Alt+G)')
            : context.t('Capture keyboard input'),
        isSelected: _grabbed,
        icon: Icon(_grabbed ? Icons.keyboard : Icons.keyboard_outlined),
        onPressed: _vncActive ? (_grabbed ? _releaseGrab : _requestGrab) : null,
      ),
      // Scaling mode picker (QG-004).
      PopupMenuButton<ConsoleScaleMode>(
        tooltip: context.t('Console scaling'),
        icon: const Icon(Icons.aspect_ratio),
        initialValue: _scaleMode,
        onSelected: (mode) {
          setState(() => _scaleMode = mode);
          _savePref(
            '$prefConsoleScaleMode${widget.vm}',
            consoleScaleModeName(mode),
          );
        },
        itemBuilder: (context) => [
          _scaleItem(ConsoleScaleMode.fit, context.t('Fit to window')),
          _scaleItem(ConsoleScaleMode.stretch, context.t('Stretch')),
          _scaleItem(ConsoleScaleMode.native, context.t('Native size')),
          _scaleItem(ConsoleScaleMode.integer, context.t('Integer scale')),
          _scaleItem(ConsoleScaleMode.manual, context.t('Manual zoom')),
        ],
      ),
      // Clipboard sync + paste (QG-005).
      IconButton(
        tooltip: context.t('Paste clipboard into guest'),
        icon: const Icon(Icons.paste),
        onPressed: _vncActive && _clipboardSync ? _pasteClipboard : null,
      ),
      IconButton(
        tooltip: _clipboardSync
            ? context.t('Clipboard sync: on')
            : context.t('Clipboard sync: off'),
        isSelected: _clipboardSync,
        icon: Icon(_clipboardSync ? Icons.sync : Icons.sync_disabled),
        onPressed: () {
          setState(() => _clipboardSync = !_clipboardSync);
          _savePref(prefConsoleClipboardSync, _clipboardSync);
        },
      ),
      IconButton(
        tooltip: context.t('Fullscreen (F11)'),
        icon: const Icon(Icons.fullscreen),
        onPressed: _toggleFullscreen,
      ),
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
    ];
  }

  PopupMenuItem<ConsoleScaleMode> _scaleItem(
    ConsoleScaleMode mode,
    String label,
  ) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (_scaleMode == mode)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  /// Visible keyboard-grab indicator with the release combination
  /// spelled out (QG-002).
  Widget _grabIndicator(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      child: Semantics(
        label: context.t('Keyboard captured'),
        child: Chip(
          avatar: const Icon(Icons.keyboard, size: 16),
          label: Text(context.t('Keyboard captured — Ctrl+Alt+G to release')),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// Manual zoom controls (QG-004) — only visible in manual mode.
  Widget _zoomControls(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Card(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.t('Zoom out'),
              icon: const Icon(Icons.zoom_out, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _zoom = (_zoom - 0.25).clamp(0.25, 8.0)),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(_zoom * 100).round()}%',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: context.t('Zoom in'),
              icon: const Icon(Icons.zoom_in, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _zoom = (_zoom + 0.25).clamp(0.25, 8.0)),
            ),
          ],
        ),
      ),
    );
  }

  /// Reconnection state (QG-006): "VM starting" for the first attempt,
  /// "connection lost" once a session had been established.
  Widget _reconnectBanner(BuildContext context) {
    final starting = _vncState == VncConnectionState.starting;
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  starting
                      ? context.t('Waiting for the display to come up…')
                      : context.t(
                          'Connection lost — reconnecting ({0})…',
                          args: ['$_retryAttempt'],
                        ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _fallbackToScreendump,
                  child: Text(context.t('Cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Minimal overlay while fullscreen: release hint + exit button, auto
  /// hidden after idle (QG-003).
  Widget _fullscreenOverlay(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: _overlayVisible ? 8 : -64,
      left: 0,
      right: 0,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _grabbed
                      ? context.t('Ctrl+Alt+G releases the keyboard')
                      : context.t('F11 or Esc exits fullscreen'),
                ),
                IconButton(
                  tooltip: context.t('Exit fullscreen'),
                  icon: const Icon(Icons.fullscreen_exit),
                  onPressed: () => _setFullscreen(false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _consoleBody(BuildContext context, ColorScheme scheme) {
    return Container(
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
                  ? _vncViewport(context)
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
    );
  }

  /// Interactive VNC viewport: physical keyboard via [Focus], pointer
  /// via gestures, scale mode via [consoleTransform]. Clicking the
  /// framebuffer grabs the keyboard (QG-002).
  Widget _vncViewport(BuildContext context) {
    final vnc = _vnc;
    if (vnc == null) return const SizedBox.shrink();
    return Focus(
      focusNode: _keyFocus,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (hasFocus) {
        // Losing focus must never leave keys held guest-side.
        if (!hasFocus) {
          _releaseAllKeys();
          if (_grabbed) setState(() => _grabbed = false);
        }
        setState(() {});
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final t = consoleTransform(
            fbSize: Size(vnc.width.toDouble(), vnc.height.toDouble()),
            viewport: constraints.biggest,
            mode: _scaleMode,
            zoom: _zoom,
          );
          final image = GestureDetector(
            onTapDown: (d) => _pointer(1, d.localPosition),
            onTapUp: (d) => _pointer(0, d.localPosition),
            onSecondaryTapDown: (d) => _pointer(4, d.localPosition),
            onSecondaryTapUp: (d) => _pointer(0, d.localPosition),
            onPanUpdate: (d) => _pointer(_pointerMask, d.localPosition),
            onTap: _grabbed ? null : _requestGrab,
            child: MouseRegion(
              cursor: _grabbed
                  ? SystemMouseCursors.none
                  : SystemMouseCursors.basic,
              child: RawImage(image: _frame),
            ),
          );
          return Container(
            decoration: BoxDecoration(
              border: Border.all(
                // Visible focus indicator (QG-001 acceptance).
                color: _grabbed
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: t.scrollable
                ? Scrollbar(
                    controller: _scrollX,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 1,
                    child: Scrollbar(
                      controller: _scrollY,
                      thumbVisibility: true,
                      notificationPredicate: (n) => n.depth == 0,
                      child: SingleChildScrollView(
                        controller: _scrollX,
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _scrollY,
                          child: SizedBox(
                            width: vnc.width * t.scale,
                            height: vnc.height * t.scale,
                            child: FittedBox(
                              fit: BoxFit.fill,
                              child: SizedBox(
                                width: vnc.width.toDouble(),
                                height: vnc.height.toDouble(),
                                child: image,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: SizedBox(
                      width: t.dst.width,
                      height: t.dst.height,
                      child: FittedBox(
                        fit: BoxFit.fill,
                        child: SizedBox(
                          width: vnc.width.toDouble(),
                          height: vnc.height.toDouble(),
                          child: image,
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _controlsBar(BuildContext context) {
    return Material(
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
                    onPressed: _running ? () => _sendChord(chord) : null,
                  ),
              ],
            ),
          ],
        ),
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

  /// Typed text goes through RFB KeyEvents — Latin-1 maps 1:1; C0
  /// controls and higher code points take the special/Unicode paths.
  void _typeRfb(String ch) {
    final vnc = _vnc;
    if (vnc == null) return;
    final c = ch.codeUnitAt(0);
    int? keysym;
    var shift = false;
    if (ch == '\n') {
      keysym = Keysyms.enter;
    } else if (ch == '\t') {
      keysym = Keysyms.tab;
    } else if (c >= 0x20 && c <= 0x7e) {
      keysym = c;
      // Shifted ASCII symbols and uppercase need Shift held.
      shift = (c >= 0x41 && c <= 0x5a) || r'!@#$%^&*()_+{}|:"<>?~'.contains(ch);
    } else if (c > 0x7e) {
      // Latin-1 direct; higher → UCS keysym (QEMU drops unknowns).
      keysym = c <= 0xff ? c : 0x01000000 | c;
    }
    if (keysym == null) return;
    if (shift) vnc.sendKey(Keysyms.shiftL, down: true);
    vnc
      ..sendKey(keysym, down: true)
      ..sendKey(keysym, down: false);
    if (shift) vnc.sendKey(Keysyms.shiftL, down: false);
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
