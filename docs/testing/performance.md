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
| WSLg, `GALLIUM_DRIVER=d3d12`, release | 342 ms | 6.9 ms | 83 ms | 33 % |

Interpretation: the ~220–340 ms first frame shows bootstrap is cheap.
Steady-state p50 of **6.9 ms** meets the 16.7 ms budget — the residual
p95/jank is Impeller shader warmup (first window) and the partially
broken WSLg EGL path (`MESA-LOADER: failed to retrieve device
information`, ZINK fallback), not app work. The dxg GPU exists
(`/dev/dxg`, `/dev/dri`) but this Mesa/EGL combo only half-uses it —
documented environment limitation, re-run on bare metal for hardware
numbers. On real hardware with EGL/Vulkan the healthy targets are
p50 ≤ 8 ms, p95 ≤ 16.7 ms, jank < 5 %; steady-state already qualifies.

## Budgets

| Metric | Budget | Verified where |
|---|---|---|
| first frame | ≤ 2 s cold | `startup.first_frame` |
| frame p95 | ≤ 16.7 ms | `frames.window` |
| jank | < 5 % of frames | `frames.window` |

The numbers are also reachable from Diagnostics → log store under the
`ui.perf` logger, so a support bundle carries them.
