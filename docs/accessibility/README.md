# Accessibility

WCAG 2.2 audit for the QuickGUI desktop app. Status per criterion:

## Implemented and verified

| Criterion | Evidence |
|---|---|
| 1.1.1 Non-text content (A) | `semanticLabel` on icon buttons (SSH, SPICE, VM actions); icons never carry meaning alone |
| 1.4.1 Use of colour (A) | VM state shown as text (`Running`/`Stale`/`Stopped`) + icon + colour chip — verified on captures |
| 1.4.3 Contrast (AA) | Material 3 `flex_color_scheme` theme; light + dark captures legible |
| 2.1.1 Keyboard (A) | Ctrl+F focuses search, Ctrl+N create, Ctrl+R refresh, Esc exits multi-select; all actions reachable by mouse equivalents |
| 2.4.3 Focus order (A) | `FocusTraversalGroup` on the machines page — predictable Tab order |
| 2.4.7 Focus visible (AA) | Theme sets `inputDecoratorFocusedBorderWidth: 2` — visible focus border on inputs |
| 2.5.8 Target size (AA) | Material icon buttons ≥ 24dp touch targets |
| 3.3.2 Labels or instructions (A) | `labelText`/`hintText` on all text fields |
| Destructive actions | Explicit confirmation dialogs for delete/apply/restore |
| Text scale | `MediaQuery.textScalerOf` fallback for the "New machine" button at >1.5×; golden tests render at 100/150/200% scale |

## Deferred — needs interactive audit on Linux

| Criterion | Why deferred |
|---|---|
| 2.1.1 full traversal | Real Tab-order walkthrough needs a running desktop session |
| 1.4.3 formal contrast | Palette passes by construction (M3); a WCAG contrast audit tool pass is pending |
| 2.4.13 Focus appearance (AAA) | Out of scope — A/AA only |
| Screen reader | Flutter desktop runs focus-mode only on Windows; a full Orca/NVDA pass is pending |

## Test coverage

- `test/golden/diagnostics_page_golden_test.dart` renders the page at
  100/150/200% text scale in both themes.
- Capture suite (`test/capture`) covers 50 interface states — used to
  spot a missing-translation crash that rendered exception text.
