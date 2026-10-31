/// Maps a physical [KeyEvent] to the X11 keysym QEMU's VNC server
/// expects, and tracks held keys so they can all be released when focus
/// is lost (the "stuck key" problem).
///
/// Layout notes: [KeyEvent.character] carries the character produced by
/// the *current* host layout (Spanish, German, US…), so forwarding its
/// keysym reproduces the guest-correct key: QEMU maps the character
/// keysym back to the matching USB position and the guest layout types
/// the intended glyph. This gives correct behaviour across layouts
/// without layout tables. Wayland/X11 host sessions deliver the same
/// LogicalKeyboardKey events, so the map is host-compositor agnostic.
library;

import 'package:flutter/services.dart';

/// Printable/special key → keysym translation for one [KeyEvent].
///
/// Returns `null` for keys that produce no guest input (dead keys, IME
/// composition, unknown logical keys).
int? rfbKeysymFor(KeyEvent event) {
  final special = _specialKeysyms[event.logicalKey];
  if (special != null) return special;
  final character = event.character;
  if (character == null || character.isEmpty) return null;
  return _unicodeToKeysym(character.codeUnitAt(0));
}

/// Converts a Unicode code point to a keysym. Latin-1 (≤ U+00FF) maps
/// 1:1 — this covers accented Spanish/German characters (á, ñ, ü, ß…)
/// as well as every ASCII glyph. Higher code points use the X11 UCS
/// convention (0x01000000|cp); QEMU drops the ones it cannot map, which
/// is harmless.
int _unicodeToKeysym(int codePoint) {
  if (codePoint < 0x20 && codePoint != 0x09 && codePoint != 0x0a) {
    return -1; // C0 control without a keysym — handled via specials
  }
  if (codePoint <= 0xff) return codePoint;
  return 0x01000000 | codePoint;
}

/// Non-printable keys — layout-independent USB positions, mapped to the
/// keysym QEMU translates to the matching guest scancode.
final Map<LogicalKeyboardKey, int> _specialKeysyms = {
  // Modifiers — left/right variants all tracked separately.
  LogicalKeyboardKey.shiftLeft: Keysyms.shiftL,
  LogicalKeyboardKey.shiftRight: Keysyms.shiftR,
  LogicalKeyboardKey.controlLeft: Keysyms.ctrlL,
  LogicalKeyboardKey.controlRight: Keysyms.ctrlR,
  LogicalKeyboardKey.altLeft: Keysyms.altL,
  LogicalKeyboardKey.altRight: Keysyms.altGr,
  LogicalKeyboardKey.metaLeft: Keysyms.superL,
  LogicalKeyboardKey.metaRight: Keysyms.superR,
  LogicalKeyboardKey.capsLock: Keysyms.capsLock,
  // Lock / system keys.
  LogicalKeyboardKey.numLock: Keysyms.numLock,
  LogicalKeyboardKey.scrollLock: Keysyms.scrollLock,
  LogicalKeyboardKey.printScreen: Keysyms.printScreen,
  LogicalKeyboardKey.pause: Keysyms.pause,
  LogicalKeyboardKey.contextMenu: Keysyms.menu,
  // Editing / navigation cluster.
  LogicalKeyboardKey.backspace: Keysyms.backspace,
  LogicalKeyboardKey.tab: Keysyms.tab,
  LogicalKeyboardKey.enter: Keysyms.enter,
  LogicalKeyboardKey.numpadEnter: Keysyms.kpEnter,
  LogicalKeyboardKey.escape: Keysyms.escape,
  LogicalKeyboardKey.insert: Keysyms.insert,
  LogicalKeyboardKey.delete: Keysyms.delete,
  LogicalKeyboardKey.home: Keysyms.home,
  LogicalKeyboardKey.end: Keysyms.end,
  LogicalKeyboardKey.pageUp: Keysyms.pageUp,
  LogicalKeyboardKey.pageDown: Keysyms.pageDown,
  LogicalKeyboardKey.arrowLeft: Keysyms.left,
  LogicalKeyboardKey.arrowUp: Keysyms.up,
  LogicalKeyboardKey.arrowRight: Keysyms.right,
  LogicalKeyboardKey.arrowDown: Keysyms.down,
  // Function keys F1–F24 are consecutive keysyms.
  LogicalKeyboardKey.f1: Keysyms.f1,
  LogicalKeyboardKey.f2: Keysyms.f1 + 1,
  LogicalKeyboardKey.f3: Keysyms.f1 + 2,
  LogicalKeyboardKey.f4: Keysyms.f1 + 3,
  LogicalKeyboardKey.f5: Keysyms.f1 + 4,
  LogicalKeyboardKey.f6: Keysyms.f1 + 5,
  LogicalKeyboardKey.f7: Keysyms.f1 + 6,
  LogicalKeyboardKey.f8: Keysyms.f1 + 7,
  LogicalKeyboardKey.f9: Keysyms.f1 + 8,
  LogicalKeyboardKey.f10: Keysyms.f1 + 9,
  LogicalKeyboardKey.f11: Keysyms.f1 + 10,
  LogicalKeyboardKey.f12: Keysyms.f1 + 11,
  // Numeric keypad operators (digits/decimal come through
  // [KeyEvent.character] on most platforms, but explicit mappings keep
  // NumLock-off paths correct).
  LogicalKeyboardKey.numpadAdd: Keysyms.kpAdd,
  LogicalKeyboardKey.numpadSubtract: Keysyms.kpSubtract,
  LogicalKeyboardKey.numpadMultiply: Keysyms.kpMultiply,
  LogicalKeyboardKey.numpadDivide: Keysyms.kpDivide,
  LogicalKeyboardKey.numpadEqual: Keysyms.kpEqual,
  LogicalKeyboardKey.numpadDecimal: Keysyms.kpDecimal,
  LogicalKeyboardKey.numpadComma: Keysyms.kpSeparator,
  LogicalKeyboardKey.numpad0: Keysyms.kp0,
  LogicalKeyboardKey.numpad1: Keysyms.kp0 + 1,
  LogicalKeyboardKey.numpad2: Keysyms.kp0 + 2,
  LogicalKeyboardKey.numpad3: Keysyms.kp0 + 3,
  LogicalKeyboardKey.numpad4: Keysyms.kp0 + 4,
  LogicalKeyboardKey.numpad5: Keysyms.kp0 + 5,
  LogicalKeyboardKey.numpad6: Keysyms.kp0 + 6,
  LogicalKeyboardKey.numpad7: Keysyms.kp0 + 7,
  LogicalKeyboardKey.numpad8: Keysyms.kp0 + 8,
  LogicalKeyboardKey.numpad9: Keysyms.kp0 + 9,
};

/// Tracks which keysyms were sent as *down* so the console can release
/// them all — on focus loss, grab release, app lifecycle pause or page
/// disposal. This is what prevents guest keys sticking (the classic
/// "shift keeps typing" bug of naive VNC embeds).
class RfbKeyTracker {
  /// logicalKey → keysym currently held down.
  final Map<LogicalKeyboardKey, int> _held = {};

  /// Number of keys currently held (test seam).
  int get heldCount => _held.length;

  /// Whether [key] is held — used by the release-combo detection.
  bool isHeld(LogicalKeyboardKey key) => _held.containsKey(key);

  /// Records the keysym sent for [key]'s down event. Returns the keysym
  /// to release later (stored so an intervening layout change cannot
  /// alter the up event).
  int recordDown(LogicalKeyboardKey key, int keysym) {
    _held[key] = keysym;
    return keysym;
  }

  /// Returns the keysym to release for [key]'s up event, or `null` if
  /// it was never held (e.g. down happened outside the grab).
  int? release(LogicalKeyboardKey key) => _held.remove(key);

  /// Keysyms to send key-up for, in press order. Clears the tracker.
  List<int> releaseAll() {
    final keysyms = _held.values.toList(growable: false);
    _held.clear();
    return keysyms;
  }
}

/// X11 keysyms beyond ASCII. Mirrors the constants already used by the
/// RFB client; kept here so [rfbKeysymFor] stays import-light.
abstract final class Keysyms {
  static const backspace = 0xFF08;
  static const tab = 0xFF09;
  static const enter = 0xFF0D;
  static const escape = 0xFF1B;
  static const space = 0x20;
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
  static const shiftL = 0xFFE1;
  static const shiftR = 0xFFE2;
  static const ctrlL = 0xFFE3;
  static const ctrlR = 0xFFE4;
  static const capsLock = 0xFFE5;
  static const altL = 0xFFE9;

  /// ISO_Level3_Shift — what QEMU expects for the right-Alt/AltGr
  /// position; it resolves to the same guest scancode.
  static const altGr = 0xFE03;
  static const superL = 0xFFEB;
  static const superR = 0xFFEC;
  static const menu = 0xFF67;
  static const numLock = 0xFF7F;
  static const scrollLock = 0xFF14;
  static const printScreen = 0xFF61;
  static const pause = 0xFF13;
  // Keypad.
  static const kpEnter = 0xFF8D;
  static const kpMultiply = 0xFFAA;
  static const kpAdd = 0xFFAB;
  static const kpSeparator = 0xFFAC;
  static const kpSubtract = 0xFFAD;
  static const kpDecimal = 0xFFAE;
  static const kpDivide = 0xFFAF;
  static const kpEqual = 0xFFBD;
  static const kp0 = 0xFFB0;
}
