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
| 7 | Flexibility/efficiency | `FocusNode`/`autofocus` in shell + catalog, `--`-dialog shortcuts for frequent ops | Partial — no shortcut catalog documented |
| 8 | Aesthetic/minimalist | Feature pages are task-focused; 978-LOC manager_rows suggests dense rows — borderline | Partial |
| 9 | Error recovery | 46 error-surface sites, typed failures, retry where relevant | Met |
| 10 | Help/documentation | `docs/user/` exists; in-app help affordances limited (no tooltip-why/onboarding tour) | Partial |

## 3. WCAG 2.2 (inspectable subset)

| Criterion | Evidence | Status |
|---|---|---|
| 1.1.1 Non-text content | `semanticLabel` on icons (54 usages) | Likely met — audit spot-checks needed |
| 1.4.3 Contrast | `flex_color_scheme` M3 palettes — designed for ≥4.5:1 | Met by construction; verify on pinkM3 accents |
| 2.1.1 Keyboard | FocusNode/autofocus present; full keyboard nav unverified without device | Partial |
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

**UI grade: A−** — unusually disciplined for a companion app: typed
error paths instead of raw CLI stderr, undo via trash, cancellation,
real accessibility *testing*, complete i18n, consistent M3.

Residuals (real, not invented):
- No documented keyboard-shortcut catalog or in-app help/onboarding
- The 978/888-LOC presentation files risk creeping density — monitor
- Contrast on the custom `pinkM3` accent should be spot-verified once
  in a running build (out of scope here — no display)
- Localization breadth beyond en/es depends on `.pot` contributions
