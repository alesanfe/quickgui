import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:quickgui/core/logging/app_logging.dart';

/// Opt-in performance instrumentation (`QUICKGUI_PERF=1`): records
/// launch→first-frame latency and rolling p50/p95/jank frame-time
/// stats into [AppLog] so the diagnostics export carries real numbers
/// instead of anecdote. Zero cost when the env flag is unset.
class PerfReporter {
  PerfReporter._();

  static final _clock = Stopwatch()..start();
  static final _frames = <double>[];
  static Timer? _flush;

  /// Startup timestamp, exposed for tests and for "time to X" events
  /// beyond the first frame.
  static Stopwatch get clock => _clock;

  static void install() {
    if (Platform.environment['QUICKGUI_PERF'] != '1') return;
    // Static finals are lazy — force the clock to start now so the
    // measurement covers install→first-frame, not callback-internal time.
    _clock.elapsed;
    // The console listener is opt-in too — without it records only live
    // in the in-memory LogStore surfaced by the Diagnostics page.
    AppLog.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLog.event(
        AppLog.perf,
        Level.INFO,
        'startup.first_frame '
        'elapsed_us=${_clock.elapsedMicroseconds} '
        'elapsed_ms=${_clock.elapsedMilliseconds}',
      );
    });
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        _frames.add(t.totalSpan.inMicroseconds / 1000.0);
      }
      if (_frames.length >= 300) _reportWindow();
    });
    // Idle desktop apps draw few frames — flush partial windows too.
    _flush = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_frames.isNotEmpty) _reportWindow();
    });
  }

  static void _reportWindow() {
    _frames.sort();
    final p50 = _frames[_frames.length ~/ 2];
    final p95 = _frames[(_frames.length * 95) ~/ 100];
    final jank = _frames.where((f) => f > 16.7).length;
    AppLog.event(
      AppLog.perf,
      Level.INFO,
      'frames.window n=${_frames.length} '
      'p50_ms=${p50.toStringAsFixed(1)} '
      'p95_ms=${p95.toStringAsFixed(1)} '
      'jank_pct=${(100 * jank / _frames.length).toStringAsFixed(1)}',
    );
    _frames.clear();
  }

  /// Test/maintenance hook: cancels the periodic flush.
  static void dispose() {
    _flush?.cancel();
    _flush = null;
    _frames.clear();
  }
}
