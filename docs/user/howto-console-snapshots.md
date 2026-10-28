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
