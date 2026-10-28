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
