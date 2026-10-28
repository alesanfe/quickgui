# How-to — console, SPICE and snapshots

## Embedded console vs external SPICE

| | Embedded console | External viewer (`spicy`) |
|---|---|---|
| Display | QEMU `screendump` screenshots (~2 s poll) | Real-time SPICE video |
| Input | `sendkey` chords + typed text | Full keyboard/mouse/pointer grab |
| Audio/USB | — | Yes |
| Requires | nothing extra | `spice-gtk` / `spicy` installed |

Use the embedded console for headless troubleshooting (grub menus,
rescue shells). Use SPICE for daily driving.

## Send special keys in the embedded console

Chord chips send common combinations (`Ctrl+Alt+Del`, `Ctrl+Alt+F1..F7`,
`Alt+Tab`). The text field maps each typed character to a QEMU
`sendkey` event — US layout assumed, same as `quickemu --type`.

## Snapshots

From **Machines** → select VM → **Snapshots**:

- **Create**: names a snapshot (internal qcow2 snapshot, instant).
- **Apply**: reverts the disk to the snapshot — destructive to current
  state; the dialog confirms first.
- **Delete**: frees the qcow2 blocks on next commit.
- **Verify**: re-checks the snapshot metadata.
- **External snapshots** (qcow2 backing chains) are listed and can be
  committed (`--disk-resize-commit` flow) from the same menu.

Snapshot a VM while it is stopped for a consistent disk, or while
running if you also want live state — internal snapshots store RAM
state when the VM is running.

## Console modes

The console picks the best channel available, in order:

1. **VNC streaming** — when the VM runs with `display="vnc"`, QuickGUI
   connects a built-in RFB client (`lib/infrastructure/vnc/rfb_client.dart`)
   to `127.0.0.1:5900+N` and streams the live framebuffer with real
   pointer and keyboard input. Quickemu publishes the endpoint as
   `vnc,PORT,HOST` in `<vm>.ports`.
2. **Screendump polling** — otherwise the console polls QEMU
   `screendump` (~2 s): enough for rescue work, GRUB menus and OS
   installers, still one-way for input via `sendkey` chords.

For full interaction (audio, USB, clipboard) use **Open external
viewer** — `spicy`/SPICE remains the most complete path.
