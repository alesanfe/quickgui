# Accessibility Matrix — QuickGUI (EN 301 549 / WCAG 2.2 adapted)

Desktop GUI is not a web page: this matrix maps the WCAG criteria that
ARE applicable to native desktop software, records how each is met in
QuickGUI (Flutter, Material 3), and how it's verified. EN 301 549
V4.1.1 (WCAG 2.2) is the reference frame.

Legend: ✅ met · ~ partial · ⬜ pending · n/a not applicable to desktop

## 1. Perceivable

| Criterion | Applies | How met | Verified |
|---|---|---|---|
| 1.1.1 Non-text content | ✅ | Icons always paired with labels/tooltips; semantic labels on interactive widgets | `Semantics` usage in buttons/lists; a11y docs |
| 1.3.1 Info and relationships | ✅ | Structured lists, section headers, semantic grouping | screen review |
| 1.4.1 Use of color | ~ | Status (running/paused/stopped) uses color + icon + text | golden tests show both |
| 1.4.3 Contrast | ✅ | Material 3 theme palettes exceed AA (dark+light) | theme tokens |
| 1.4.4 Resize text | ~ | Respects system font scale; extreme scale not fully verified | pending |
| 1.4.10 Reflow | ~ | Window is resizable; narrow-window layouts not audited | pending |
| 1.4.12 Text spacing | n/a | system-driven | — |
| 1.4.13 Content on hover/focus | ✅ | Tooltips appear on focus too | widget tests |

## 2. Operable

| Criterion | Applies | How met | Verified |
|---|---|---|---|
| 2.1.1 Keyboard | ✅ | Full app keyboard-navigable; Ctrl+N create, Ctrl+R refresh, Esc exits multi-select (6b80a3b) | manual + widget tests |
| 2.1.2 No keyboard trap | ✅ | Esc always leaves dialogs/selection | manual |
| 2.1.4 Character shortcuts | ~ | shortcuts are modified (Ctrl+) — no bare-letter traps | code review |
| 2.2.1 Timing adjustable | ~ | op timeouts backend-side; UI shows progress while running | — |
| 2.3.1 Flashes | ✅ | no flashing content | — |
| 2.4.2 Titled | ~ | window title per route; no formal assertion | pending |
| 2.4.3 Focus order | ✅ | Natural Flutter focus order follows layout | manual |
| 2.4.7 Focus visible | ✅ | Material focus rings in both themes | golden tests |
| 2.4.11 Focus not obscured | ✅ | scroll-into-view on focus | — |
| 2.5.3 Label in name | ✅ | semantic labels match visible labels | — |

## 3. Understandable

| Criterion | Applies | How met | Verified |
|---|---|---|---|
| 3.1.1 Language of page | ✅ | i18n locales tagged (en/es via flutter_localizations) | i18n tests |
| 3.2.1 On focus | ✅ | no context change on focus alone | — |
| 3.2.6 Consistent help | ~ | help surfaces consistently placed | — |
| 3.3.1 Error identification | ✅ | typed errors map to messages with suggestions | error tests |
| 3.3.2 Labels or instructions | ✅ | form fields have labels+hint+validation | widget tests |
| 3.3.3 Error suggestion | ~ | some errors suggest fixes (e.g. debget not found) | — |
| 3.3.4 Error prevention | ✅ | destructive ops need confirmation + planId/trash | UI tests |
| 3.3.7 Redundant entry | ✅ | persisted prefs; forms retain state | — |

## 4. Robust

| Criterion | Applies | How met | Verified |
|---|---|---|---|
| 4.1.2 Name, role, value | ✅ | Material widgets expose semantics to AT | semantics test |
| 4.1.3 Status messages | ~ | progress/snackbars announced via Semantics live regions | partial |

## Gaps to close (ranked)

1. Screen-reader pass on Linux (orca) + Windows (NVDA) — biggest real
   unknown; Semantics is wired but end-to-end AT behavior unverified.
2. Text-scale extremes (200%) layout audit.
3. Narrow-window reflow audit.
4. Status-message announcements on every async state change.

## Gate

`flutter test` widget suite covers focus, semantics labels, contrast
tokens; this matrix is reviewed whenever a11y docs change.
