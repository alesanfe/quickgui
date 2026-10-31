import 'dart:math' as math;
import 'dart:ui';

/// How the guest framebuffer maps onto the console viewport.
enum ConsoleScaleMode {
  /// Stretch the framebuffer to exactly fill the viewport (may distort).
  stretch,

  /// Fit inside the viewport preserving aspect ratio (letterbox).
  fit,

  /// 1:1 device pixels — scrolls when the framebuffer is larger.
  native,

  /// Largest whole-number factor that still fits (1x, 2x, 3x…), so
  /// pixels stay crisp; scrolls when even 1x is too large.
  integer,

  /// Manual factor chosen by the user — scrolls when needed.
  manual,
}

/// Persisted/display name for settings and tooltips.
String consoleScaleModeName(ConsoleScaleMode mode) => switch (mode) {
  ConsoleScaleMode.stretch => 'stretch',
  ConsoleScaleMode.fit => 'fit',
  ConsoleScaleMode.native => 'native',
  ConsoleScaleMode.integer => 'integer',
  ConsoleScaleMode.manual => 'manual',
};

/// Parses a stored mode name back — unknown values fall back to fit.
ConsoleScaleMode consoleScaleModeParse(String? name) {
  for (final m in ConsoleScaleMode.values) {
    if (consoleScaleModeName(m) == name) return m;
  }
  return ConsoleScaleMode.fit;
}

/// Effective scale factor and destination rect for [fbSize] inside
/// [viewport], honouring [mode] and the user [zoom] (manual mode only).
/// Pure — unit-tested without a widget tree.
({double scale, Rect dst, bool scrollable}) consoleTransform({
  required Size fbSize,
  required Size viewport,
  required ConsoleScaleMode mode,
  double zoom = 1.0,
}) {
  final fw = fbSize.width <= 0 ? 1.0 : fbSize.width;
  final fh = fbSize.height <= 0 ? 1.0 : fbSize.height;
  final vw = viewport.width <= 0 ? 1.0 : viewport.width;
  final vh = viewport.height <= 0 ? 1.0 : viewport.height;

  double scale;
  var scrollable = false;
  switch (mode) {
    case ConsoleScaleMode.stretch:
      // Non-uniform: handled by dst covering the whole viewport.
      final dw = vw;
      final dh = vh;
      return (
        scale: math.min(vw / fw, vh / fh),
        dst: Rect.fromLTWH(0, 0, dw, dh),
        scrollable: false,
      );
    case ConsoleScaleMode.fit:
      scale = math.min(vw / fw, vh / fh);
    case ConsoleScaleMode.native:
      scale = 1.0;
      scrollable = true;
    case ConsoleScaleMode.integer:
      scale = math.max(1, math.min(vw / fw, vh / fh).floor()).toDouble();
      scrollable = true;
    case ConsoleScaleMode.manual:
      scale = zoom.clamp(0.1, 8.0);
      scrollable = true;
  }
  final dw = fw * scale;
  final dh = fh * scale;
  return (
    scale: scale,
    dst: Rect.fromLTWH((vw - dw) / 2, (vh - dh) / 2, dw, dh),
    scrollable: scrollable,
  );
}

/// Converts a viewport-relative point into framebuffer coordinates for
/// [mode]/[zoom]. Returns null when the point is outside the displayed
/// framebuffer (non-scrollable modes centre the image, so letterbox
/// margins are not clickable).
Offset? consolePointToFb({
  required Offset point,
  required Size fbSize,
  required Size viewport,
  required ConsoleScaleMode mode,
  double zoom = 1.0,
  Offset scrollOffset = Offset.zero,
}) {
  final t = consoleTransform(
    fbSize: fbSize,
    viewport: viewport,
    mode: mode,
    zoom: zoom,
  );
  // Scrolled modes place the scaled framebuffer at the origin of the
  // scrollable child; non-scrolled modes use the centred dst rect.
  final local = t.scrollable ? point + scrollOffset : point - t.dst.topLeft;
  final x = (local.dx / t.scale).round();
  final y = (local.dy / t.scale).round();
  if (x < 0 || y < 0 || x >= fbSize.width || y >= fbSize.height) {
    return null;
  }
  return Offset(x.toDouble(), y.toDouble());
}
