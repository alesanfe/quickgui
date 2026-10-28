# Accessibility

WCAG 2.2 audit for the QuickGUI desktop app. Status per criterion:

## Implemented and verified

| Criterion | Evidence |
|---|---|
| 1.1.1 Non-text content (A) | `semanticLabel` on icon buttons (SSH, SPICE, VM actions); icons never carry meaning alone |
| 1.4.1 Use of colour (A) | VM state shown as text (`Running`/`Stale`/`Stopped`) + icon + colour chip — verified on captures |
| 1.4.3 Contrast (AA) | Material 3 `flex_color_scheme` theme; light + dark captures legible |
| 2.1.1 Keyboard (A) | Ctrl+1..6 section nav, F1 shortcut help, Ctrl+F/N/R in Machines, Esc exits multi-select/dialogs; Tab traversal verified by widget test |
| 4.1.3 Status messages (AA) | `Semantics(liveRegion: true)` on VM state chips/rows, download progress and console state — state changes announced without focus |
| 2.4.3 Focus order (A) | `FocusTraversalGroup` on the machines page — predictable Tab order |
| 2.4.7 Focus visible (AA) | Theme sets `inputDecoratorFocusedBorderWidth: 2` — visible focus border on inputs |
| 2.5.8 Target size (AA) | Material icon buttons ≥ 24dp touch targets |
| 3.3.2 Labels or instructions (A) | `labelText`/`hintText` on all text fields |
| Destructive actions | Explicit confirmation dialogs for delete/apply/restore |
| Text scale | `MediaQuery.textScalerOf` fallback for the "New machine" button at >1.5×; golden tests render at 100/150/200% scale |

## Deferred — needs interactive audit on Linux

| Criterion | Why deferred |
|---|---|
| 2.1.1 full traversal | Widget-level Tab test exists; a real-session walkthrough is scripted in `orca-verification.md` — pending a GNOME session |
| 1.4.3 formal contrast | Palette passes by construction (M3); a WCAG contrast audit tool pass is pending |
| 2.4.13 Focus appearance (AAA) | Out of scope — A/AA only |
| Screen reader | AT-SPI semantics contract pinned in `new_gaps_test.dart` (button flags, labels, live regions); interactive Orca pass scripted in `orca-verification.md` — requires a real session (WSLg is not a valid AT testbed) |

## Test coverage

- `test/golden/diagnostics_page_golden_test.dart` renders the page at
  100/150/200% text scale in both themes.
- `test/widget/new_gaps_test.dart` — `AT-SPI contract` group: live-region
  flags, button flag + non-empty label on every reachable IconButton,
  text-field semantics; `keyboard traversal` group: Tab focus movement
  and Esc dismissal.
- Capture suite (`test/capture`) covers 50 interface states — used to
  spot a missing-translation crash that rendered exception text.
