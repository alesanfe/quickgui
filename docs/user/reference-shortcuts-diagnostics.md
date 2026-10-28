# Reference — keyboard shortcuts and diagnostics

## Global shortcuts

| Keys | Action |
|---|---|
| `Ctrl+1..6` | Jump to Home / Machines / Create / Activity / Settings / Diagnostics |
| `F1` | Shortcut help dialog (also in Settings → Keyboard shortcuts) |
| `Ctrl+N` | New machine (Create page) |
| `Ctrl+F` | Focus machine search |
| `Ctrl+R` | Refresh machine list |
| `Esc` | Exit multi-select; close dialogs |

## Diagnostics page

`Ctrl+6` — self-service debugging:

- **Backend status**: quickemu/qemu/spicy versions detected on `PATH`.
- **Doctor**: runs `quickreport` plus app-side checks (stale locks,
  orphaned plans, conf parse errors); each finding offers a repair
  action.
- **Log store**: the session log (`AppLog`) with level filter —
  export it when filing a bug.
- **Performance**: with `QUICKGUI_PERF=1` in the environment, startup
  and frame-timing records appear under the `ui.perf` logger. See
  `docs/testing/performance.md`.

## Typed errors

Failures surface as `AppFailure` with a stable `code` (`VM_NOT_FOUND`,
`LOCK_BUSY`, `CHECKSUM_MISMATCH`, …) and a `retryable` flag. Codes map
to families (`vmNotFound`, `spaceLow`, `timeout`…) — report bugs with
the code + the Diagnostics log export.
