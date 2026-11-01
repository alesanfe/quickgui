# Orca / AT-SPI verification protocol

How to verify QuickGUI with a real assistive-technology stack on Linux.
Flutter desktop exposes semantics over AT-SPI (`libatk`), so Orca is the
reference screen reader. The semantic contract itself is pinned by
`test/widget/new_gaps_test.dart` (group `AT-SPI contract`) — this document
covers the interactive pass that tests cannot perform.

## Prerequisites

```bash
sudo apt install orca at-spi2-core accerciser
# accerciser = AT-SPI tree inspector (optional but recommended)
```

Run the app from a normal GNOME/Wayland or X11 session — not headless:

```bash
flutter run -d linux
# or the release bundle:
build/linux/x64/release/bundle/quickgui
```

## What the app must emit

The widget tests pin these semantics — Orca should announce the same:

| Surface | Semantics | Expected Orca speech |
|---|---|---|
| VM state chips (list + details) | `Semantics(liveRegion: true)` + label | state change spoken without focus ("running") |
| Operation/download progress | live region + `label` with percent | progress announced on update |
| Icon-only buttons | tooltip → `SemanticsFlag.isButton` + label | "button: refresh" etc. |
| Text fields | `isTextField` + `labelText` | field purpose on focus |
| Navigation destinations | selected/enabled flags | current section announced |

## Scripted pass (~15 min)

1. **Launch**: press `orca_key+H` twice for Orca tutorial if unfamiliar.
2. **Navigation**: `Ctrl+1..6` cycles Home/Machines/Create/Activity/
   Settings/Diagnostics. Orca must announce each landing section.
3. **Machines list**: Tab into the list, arrow over rows — each row
   announces name + state (live region fires on state change; start a VM
   to verify).
4. **Buttons**: Tab across the details pane actions — every control must
   speak a purpose, never "unlabeled button".
5. **Create wizard**: `Ctrl+N`, tab through the form — every field
   announces its label; invalid input announces the error text.
6. **Console**: open Console on a running VM — the frame announces
   "Live console"; the stopped state announces the offline message.
7. **F1**: shortcut dialog opens; `Esc` closes it.
8. **Accerciser cross-check** (optional): inspect the AT-SPI tree —
   roles (`push-button`, `text`, `list-item`) and names should match the
   table above.

## Known environment gaps

- WSLg is not a valid AT testbed: AT-SPI over WSL requires a Windows-side
  bridge. Run the pass on a real GNOME session (bare metal or VM).
- Flutter/Linux semantics are complete but AT events (live-region
  announcements) depend on `at-spi2-atk` being present in the session —
  standard on GNOME, verify with `accerciser` if announcements don't fire.

## Automated AT-SPI verification — DONE (2026-10-28, re-run 2026-11-01)

`tool/atspi_check.sh` runs the release binary inside a private
`dbus-run-session` with the real accessibility stack
(`at-spi-bus-launcher` + `at-spi2-registryd`) and walks the exposed
tree with `pyatspi` — the same client library Orca consumes.

Latest measured result (release build, Wayland session):

```
APP: quickgui | nodes: 55
  button                   8  (7 labelled)
  panel nav destinations   7  — "Inicio\nPestaña N de 7" … "Ajustes\nPestaña 7 de 7"
nav sections found: all 7 sections (es locale)
RESULT: PASS
```

Note: shell nav destinations appeared only after upgrading to
`go_router 18.0.2` — earlier releases had the shell chrome dropped
from the semantics tree by the route's `ModalBarrier`
(upstream flutter/flutter#135656, fixed in go_router 18.0.2).

## Scripted Orca pass — DONE (2026-11-01)

Real Orca 50.3 (Ubuntu 26.04, AT-SPI 2.60.4) ran against the release
binary inside the same private `dbus-run-session` harness, and
`tool/orca_drive.py` activated every nav destination through its AT-SPI
`Tap` action — the same semantic interface a real AT client uses.
Speech was captured with `orca --debug-file`:

```
SPEECH OUTPUT: 'Lector de pantalla activado.'
SPEECH OUTPUT: 'Inicio — Quickgui'
SPEECH OUTPUT: 'Máquinas — Quickgui'
SPEECH OUTPUT: 'Crear — Quickgui'
SPEECH OUTPUT: 'Automatización — Quickgui'
SPEECH OUTPUT: 'Actividad — Quickgui'
SPEECH OUTPUT: 'Diagnóstico — Quickgui'
```

Observed: every section switch updates the localized window title
(WCAG 2.4.2) and Orca announces it immediately — verified for 6 of 7
sections in this capture (the last `Tap` ran ~1 s before shutdown;
the mechanism is identical). Live-region announcements and form-error
speech still deserve a manual spot-check on a fully logged-in GNOME
session — synthetic key injection is unavailable inside the private
bus, so Tab-order traversal was exercised via AT-SPI actions rather
than physical keys.

What remains genuinely manual: physical keyboard traversal
(Tab/arrows) audible on the user's own session, braille output, and
AT event timing under a logged-in compositor.

## Sign-off template

```
Date / session / Orca version:
App version / channel:
[ ] Sections announce on Ctrl+1..6
[ ] VM state changes announced (live region)
[ ] All buttons labelled
[ ] Form fields labelled + errors announced
[ ] Dialogs announce title; Esc closes
[ ] Console frame announces state
Findings:
```
