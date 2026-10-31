import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/infrastructure/vnc/console_scale.dart';
import 'package:quickgui/infrastructure/vnc/reconnect_policy.dart';

void main() {
  group('ReconnectPolicy', () {
    const policy = ReconnectPolicy();

    test('delays double each attempt and are capped', () {
      expect(policy.delayFor(0), const Duration(seconds: 1));
      expect(policy.delayFor(1), const Duration(seconds: 2));
      expect(policy.delayFor(2), const Duration(seconds: 4));
      expect(policy.delayFor(3), const Duration(seconds: 8));
      expect(policy.delayFor(4), const Duration(seconds: 15)); // capped
      expect(policy.delayFor(20), const Duration(seconds: 15));
    });

    test('attempts are bounded — no infinite retry loop', () {
      expect(policy.canRetry(0), isTrue);
      expect(policy.canRetry(9), isTrue);
      expect(policy.canRetry(10), isFalse);
      expect(policy.canRetry(100), isFalse);
    });
  });

  group('consoleTransform', () {
    const fb = Size(1280, 800);
    const box = Size(640, 480);

    test('fit preserves aspect and letterboxes', () {
      final t = consoleTransform(
        fbSize: fb,
        viewport: box,
        mode: ConsoleScaleMode.fit,
      );
      expect(t.scale, 640 / 1280);
      expect(t.dst.width, 640);
      expect(t.dst.height, 400); // 800 * 0.5
      expect(t.dst.left, 0);
      expect(t.dst.top, 40); // centred vertically
      expect(t.scrollable, isFalse);
    });

    test('stretch fills the whole viewport', () {
      final t = consoleTransform(
        fbSize: fb,
        viewport: box,
        mode: ConsoleScaleMode.stretch,
      );
      expect(t.dst, const Rect.fromLTWH(0, 0, 640, 480));
      expect(t.scrollable, isFalse);
    });

    test('native is 1:1 and scrollable', () {
      final t = consoleTransform(
        fbSize: fb,
        viewport: box,
        mode: ConsoleScaleMode.native,
      );
      expect(t.scale, 1.0);
      expect(t.scrollable, isTrue);
    });

    test('integer picks the largest whole factor that fits', () {
      // 1280x800 in 640x480 → only 1x fits.
      expect(
        consoleTransform(
          fbSize: fb,
          viewport: box,
          mode: ConsoleScaleMode.integer,
        ).scale,
        1,
      );
      // 640x480 fb in a 2000x1600 window → 3x.
      expect(
        consoleTransform(
          fbSize: const Size(640, 480),
          viewport: const Size(2000, 1600),
          mode: ConsoleScaleMode.integer,
        ).scale,
        3,
      );
    });

    test('manual honours the zoom factor with bounds', () {
      expect(
        consoleTransform(
          fbSize: fb,
          viewport: box,
          mode: ConsoleScaleMode.manual,
          zoom: 2.5,
        ).scale,
        2.5,
      );
      expect(
        consoleTransform(
          fbSize: fb,
          viewport: box,
          mode: ConsoleScaleMode.manual,
          zoom: 99,
        ).scale,
        8.0,
      );
    });
  });

  group('consolePointToFb', () {
    const fb = Size(100, 100);
    const box = Size(200, 200);

    test('fit maps the centred rect back to fb coords', () {
      // fit: scale 2, dst fills 200x200 → (50,50) → (25,25).
      expect(
        consolePointToFb(
          point: const Offset(50, 50),
          fbSize: fb,
          viewport: box,
          mode: ConsoleScaleMode.fit,
        ),
        const Offset(25, 25),
      );
    });

    test('fit returns null in the letterbox margin', () {
      // 100x100 fb in a 200x300 box: dst is 200x200 centred → 50px
      // vertical margins; y=10 is inside the top margin.
      expect(
        consolePointToFb(
          point: const Offset(100, 10),
          fbSize: fb,
          viewport: const Size(200, 300),
          mode: ConsoleScaleMode.fit,
        ),
        isNull,
      );
    });

    test('scrollable modes account for scroll offset', () {
      expect(
        consolePointToFb(
          point: const Offset(10, 10),
          fbSize: fb,
          viewport: const Size(50, 50),
          mode: ConsoleScaleMode.native,
          scrollOffset: const Offset(30, 30),
        ),
        const Offset(40, 40),
      );
    });
  });

  group('consoleScaleMode name round-trip', () {
    test('every mode survives parse(name)', () {
      for (final m in ConsoleScaleMode.values) {
        expect(consoleScaleModeParse(consoleScaleModeName(m)), m);
      }
    });

    test('unknown names fall back to fit', () {
      expect(consoleScaleModeParse('bogus'), ConsoleScaleMode.fit);
      expect(consoleScaleModeParse(null), ConsoleScaleMode.fit);
    });
  });
}
