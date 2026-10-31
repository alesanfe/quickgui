import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/vnc/keymap.dart';

/// Builds a minimal KeyDown/UpEvent with the fields [rfbKeysymFor]
/// reads — logicalKey plus the produced character.
KeyDownEvent keyDown(LogicalKeyboardKey key, {String? character}) {
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    character: character,
    timeStamp: Duration.zero,
  );
}

KeyUpEvent keyUp(LogicalKeyboardKey key) {
  return KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

void main() {
  group('rfbKeysymFor — specials', () {
    test('navigation cluster maps to X11 navigation keysyms', () {
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.arrowLeft)), Keysyms.left);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.arrowUp)), Keysyms.up);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.arrowRight)),
        Keysyms.right,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.arrowDown)), Keysyms.down);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.home)), Keysyms.home);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.end)), Keysyms.end);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.pageUp)), Keysyms.pageUp);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.pageDown)),
        Keysyms.pageDown,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.insert)), Keysyms.insert);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.delete)), Keysyms.delete);
    });

    test('function keys F1..F12 map to consecutive keysyms', () {
      const fKeys = [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.f12,
      ];
      for (var i = 0; i < fKeys.length; i++) {
        expect(rfbKeysymFor(keyDown(fKeys[i])), Keysyms.f1 + i);
      }
    });

    test('modifiers map to left/right keysyms, AltGr to ISO_Level3', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.shiftLeft)),
        Keysyms.shiftL,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.shiftRight)),
        Keysyms.shiftR,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.controlLeft)),
        Keysyms.ctrlL,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.controlRight)),
        Keysyms.ctrlR,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.altLeft)), Keysyms.altL);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.altRight)), Keysyms.altGr);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.metaLeft)),
        Keysyms.superL,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.metaRight)),
        Keysyms.superR,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.capsLock)),
        Keysyms.capsLock,
      );
    });

    test('editing keys map to their keysyms', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.backspace)),
        Keysyms.backspace,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.tab)), Keysyms.tab);
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.enter)), Keysyms.enter);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadEnter)),
        Keysyms.kpEnter,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.escape)), Keysyms.escape);
    });

    test('lock and system keys map', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numLock)),
        Keysyms.numLock,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.scrollLock)),
        Keysyms.scrollLock,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.printScreen)),
        Keysyms.printScreen,
      );
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.pause)), Keysyms.pause);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.contextMenu)),
        Keysyms.menu,
      );
    });

    test('numpad operators and digits map to keypad keysyms', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadAdd)),
        Keysyms.kpAdd,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadSubtract)),
        Keysyms.kpSubtract,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadMultiply)),
        Keysyms.kpMultiply,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadDivide)),
        Keysyms.kpDivide,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadDecimal)),
        Keysyms.kpDecimal,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.numpadEqual)),
        Keysyms.kpEqual,
      );
      const digits = [
        LogicalKeyboardKey.numpad0,
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad2,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad4,
        LogicalKeyboardKey.numpad5,
        LogicalKeyboardKey.numpad6,
        LogicalKeyboardKey.numpad7,
        LogicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad9,
      ];
      for (var i = 0; i < digits.length; i++) {
        expect(rfbKeysymFor(keyDown(digits[i])), Keysyms.kp0 + i);
      }
    });
  });

  group('rfbKeysymFor — characters', () {
    test('ASCII characters map 1:1 (EN layout)', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyA, character: 'a')),
        0x61,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyA, character: 'A')),
        0x41,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.digit1, character: '1')),
        0x31,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.space, character: ' ')),
        0x20,
      );
    });

    test('Latin-1 characters keep their code point (ES/DE layouts)', () {
      // Spanish ñ and accented vowels, German umlauts and ß — the
      // character produced by the host layout becomes the keysym.
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.semicolon, character: 'ñ')),
        0xF1,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyA, character: 'á')),
        0xE1,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyU, character: 'ü')),
        0xFC,
      );
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyS, character: 'ß')),
        0xDF,
      );
    });

    test('higher code points get the UCS keysym prefix', () {
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyE, character: '€')),
        0x01000000 | 0x20AC,
      );
    });

    test('null or control characters map to nothing useful', () {
      expect(rfbKeysymFor(keyDown(LogicalKeyboardKey.keyA)), isNull);
      expect(
        rfbKeysymFor(keyDown(LogicalKeyboardKey.keyA, character: '')),
        -1,
      );
    });
  });

  group('RfbKeyTracker', () {
    test('down/up round trip releases the recorded keysym', () {
      final tracker = RfbKeyTracker();
      tracker.recordDown(LogicalKeyboardKey.keyA, 0x41); // sent 'A'
      expect(tracker.heldCount, 1);
      expect(tracker.isHeld(LogicalKeyboardKey.keyA), isTrue);
      expect(tracker.release(LogicalKeyboardKey.keyA), 0x41);
      expect(tracker.heldCount, 0);
      expect(tracker.release(LogicalKeyboardKey.keyA), isNull);
    });

    test('releaseAll returns every held keysym and clears', () {
      final tracker = RfbKeyTracker();
      tracker
        ..recordDown(LogicalKeyboardKey.shiftLeft, Keysyms.shiftL)
        ..recordDown(LogicalKeyboardKey.controlLeft, Keysyms.ctrlL)
        ..recordDown(LogicalKeyboardKey.delete, Keysyms.delete);
      expect(tracker.releaseAll(), [
        Keysyms.shiftL,
        Keysyms.ctrlL,
        Keysyms.delete,
      ]);
      expect(tracker.heldCount, 0);
      expect(tracker.releaseAll(), isEmpty);
    });

    test('release of an unheld key returns null', () {
      final tracker = RfbKeyTracker();
      expect(tracker.release(LogicalKeyboardKey.keyZ), isNull);
    });
  });
}
