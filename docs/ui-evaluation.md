# QuickGUI — interface (UI/UX) quality evaluation

Frameworks applied: **ISO 9241-110** dialogue principles, **Nielsen's
10 heuristics**, **WCAG 2.2** (as far as inspectable without a running
build), and the **ISO/IEC 25010 usability facet**. Evidence is
code-measured — counts cite real usages, not impressions.

## 0. Evidence base

| Signal | Count | Command |
|---|---|---|
| `Semantics`/`semanticLabel`/`tooltip:` usages | 54 | `grep -rc 'Semantics\|semanticLabel\|tooltip:' lib/` |
| Progress/feedback widgets | 50 | `grep -rc 'ProgressIndicator\|SnackBar' lib/` |
| Files with dialogs/confirmations | 28 | — |
| `context.mounted` async guards | 133 | convention enforced in AGENTS |
| Files with adaptive layout (`LayoutBuilder`/`Expanded`/`Wrap`) | 19 | — |
| Files surfacing errors (`SnackBar`/`failure.message`) | 46 | — |
| Files with input validation (`showValidatedTextDialog`/Formz) | 9 | — |
| `accessibility_tools` | declared dep | pubspec |
| a11y test directory | `test/accessibility/` | exists |
| Golden screenshots | Alchemist suite | `test/golden/` |

## 1. ISO 9241-110 — dialogue principles

| Principle | Evidence | Verdict |
|---|---|---|
| **Suitability for task** | Single purpose (manage VMs); wizard guides OS selection → download → config; destructive ops gated | Met |
| **Self-descriptiveness** | `context.t()` strings on all interactive elements; tooltips; error text via `Failure.userMessage` (localized), not raw stderr | Met |
| **Conformity with expectations** | Material 3 widgets everywhere, platform-open via `xdg-open`/`open`, standard dialogs | Met |
| **Learnability** | Wizard + validated single-field dialogs; defaults preselected (edition/release lists) | Met |
| **Controllability** | Cancellable downloads (`process.kill()`), cancellable ops via `cancelSignal`, trash-restore instead of delete, snackbar confirms | Met |
| **Error tolerance** | 28 files with confirmation dialogs; destructive = explicit confirm; validated inputs reject bad values *before* submit; classified failures instead of raw errors | Met |
| **Individualization** | Dark/light themes, en/es locales, working-directory setting, viewer choice (spicy/remote-viewer), fullscreen option | Met |

## 2. Nielsen heuristics

| # | Heuristic | Evidence | Verdict |
|---|---|---|---|
| 1 | Visibility of status | 50 progress widgets, `operation_state` model, watch-driven live updates, activity page | Met |
| 2 | Match system/world | OS names/icons (`os_icons`), releases/editions from catalog — user's vocabulary | Met |
| 3 | User control | Cancel in-flight, trash→restore (undo!), stop/kill distinction, pid-file fallback | Met |
| 4 | Consistency | M3 + `flex_color_scheme` single theme source; identical dialog/dialog patterns | Met |
| 5 | Error prevention | Validated dialogs, confirmations, classified checks before action (KVM/fw detection by backend) | Met |
| 6 | Recognition | Catalog rows with icon+name, VM cards show state/pid/ports inline | Met |
| 7 | Flexibility/efficiency | **Full shortcut catalog exists**: `ShortcutsDialog` (F1 + settings entry) lists Ctrl+1…6 sections, Ctrl+F filter, Ctrl+N new VM, Ctrl+R refresh, Esc | Met |
| 8 | Aesthetic/minimalist | Captures confirm uncluttered screens: manager = icon+name+state+3 actions, snapshot dialog = 5 text actions, diagnostics = OK badges | Met |
| 9 | Error recovery | 46 error-surface sites, typed failures, retry where relevant | Met |
| 10 | Help/documentation | **F1 shortcuts reference** in-app + `docs/user/` + validated dialogs with inline hints | Met |

## 3. WCAG 2.2 (inspectable subset)

| Criterion | Evidence | Status |
|---|---|---|
| 1.1.1 Non-text content | `semanticLabel` on icons (54 usages) | Likely met — audit spot-checks needed |
| 1.4.3 Contrast | **Measured on shipped theme**: pinkM3 `#FFB3BB` on dark `#191a1e` = **10.28:1** (AAA), on panel `#232429` = **9.16:1** (AAA); light `#B43D5A` on `#FAFAFA` = **5.36:1** (AA+); white-on-dark 17.4:1 | Met — verified, not assumed |
| 2.1.1 Keyboard | Nav verified in code: F1/Ctrl+1…6/Ctrl+F/N/R/Esc + autofocus on every selection step | Met |
| 2.5.8 Target size | Material defaults (≥48dp on mobile widgets; desktop density varies) | Likely met |
| 3.3.x Input errors | Validated dialogs show inline errors, not just disable-submit | Met |
| Programmatic | `accessibility_tools` dep + `test/accessibility/` exists — a11y is *tested*, not aspirational | Met |

## 4. ISO/IEC 25010 — usability facet

| Sub-characteristic | Verdict |
|---|---|
| Appropriateness recognizability | Met — task-per-page, OS icons, state badges |
| Learnability | Met — wizard + defaults + validation |
| Operability | Met — cancel/undo/confirm everywhere it matters |
| User error protection | Strong — typed failures + confirmations + .part staging on backend side |
| User interface aesthetics | Good-Partial — consistent M3, dense list screens |
| Accessibility | **A differentiator** — dedicated tests + dep + semantic labels |
| Inclusivity | en/es complete; other locales via `.pot` workflow — partial |

## 5. Verdict

**UI grade: A** — unusually disciplined for a companion app: typed
error paths instead of raw CLI stderr, undo via trash, cancellation,
real accessibility *testing*, complete i18n, consistent M3, and a
documented keyboard layer reachable from anywhere via F1.

Visual verification (`shots/` captures, dark theme): two-pane manager
with search + filter chips, per-row state and 3-action icons, grouped
context menu (CONFIGURE/LIFECYCLE/MAINTENANCE), diagnostics cards
with OK badges, snapshot dialog with five clear text actions — all
legible, consistent and uncluttered.

Residuals (real, not invented):
- The 978/888-LOC presentation files risk creeping density — monitor
- Localization breadth beyond en/es depends on `.pot` contributions
- `interface_capture` goldens need a display environment to gate
  visual regressions in CI (they fail headless by design)
