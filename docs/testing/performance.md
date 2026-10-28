# Performance benchmark protocol

`QUICKGUI_PERF=1` enables opt-in, local-only performance telemetry
(`lib/core/telemetry/perf_reporter.dart`). Nothing is sent anywhere —
records go to `AppLog` (console + Diagnostics page log store).

## Metrics

| Event | Meaning |
|---|---|
| `startup.first_frame` | install→first frame, in µs (bootstrap work until the UI first paints) |
| `frames.window` | rolling window of rendered frames: `n`, `p50_ms`, `p95_ms`, `jank_pct` (frames > 16.7 ms) |

A `frames.window` record is emitted every 300 frames and every 10 s when
a partial window is pending — idle desktop apps draw very few frames.

## Running the benchmark

```bash
# release build — never benchmark debug/profile
flutter build linux --release
cd build/linux/x64/release/bundle

QUICKGUI_PERF=1 ./quickgui 2>&1 | grep ui.perf
```

Protocol for comparable numbers:

1. Cold caches: `sync && echo 3 | sudo tee /proc/sys/vm/drop_caches`.
2. Record 3 launches; report the median `first_frame`.
3. Exercise the UI during the run: switch sections (Ctrl+1..6), scroll
   the machine list, open a dialog — frame windows only cover frames
   actually drawn.
4. Report environment: bare metal vs VM, GPU driver, compositor, scale.

## Recorded baseline

| Environment | first_frame | p50 | p95 | jank |
|---|---|---|---|---|
| WSLg, llvmpipe software raster, release | 220 ms | 65 ms | 92 ms | 82 % |

Interpretation: the 220 ms first frame shows bootstrap is cheap. The
frame times are dominated by llvmpipe (software GL under WSLg) — an
idle GTK/Qt app shows the same profile there. On real hardware with
EGL/Vulkan, re-run the protocol; healthy targets are p50 ≤ 8 ms,
p95 ≤ 16.7 ms, jank < 5 %.

## Budgets

| Metric | Budget | Verified where |
|---|---|---|
| first frame | ≤ 2 s cold | `startup.first_frame` |
| frame p95 | ≤ 16.7 ms | `frames.window` |
| jank | < 5 % of frames | `frames.window` |

The numbers are also reachable from Diagnostics → log store under the
`ui.perf` logger, so a support bundle carries them.
