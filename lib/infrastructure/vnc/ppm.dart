import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

// Binary PPM (P6) decoding for QEMU screendump fallback.
// Extracted from vm_console_page.

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
