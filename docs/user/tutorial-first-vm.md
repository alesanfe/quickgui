# Tutorial — your first VM in ~10 minutes

This tutorial takes you from a fresh QuickGUI install to a running Linux
VM. You need `quickemu` and `qemu` installed and ~5 GB free disk space.

## 1. Open the Create page

Launch QuickGUI. Press `Ctrl+3` or click **Create** in the navigation.

## 2. Pick an operating system

Type "ubuntu" in the filter box, click the Ubuntu tile, then pick a
release (e.g. 24.04 LTS) and an edition (e.g. `desktop`).

## 3. Download

Click **Download**. The Activity page (`Ctrl+4`) shows live progress —
you can cancel there at any time. When the download finishes you get a
desktop notification (if enabled in Settings) and a ready-made
`<os>-<release>.conf`.

## 4. Start the VM

Go to **Machines** (`Ctrl+2`), select the new entry, click **Start**.
The state chip changes to *Running*.

## 5. See the screen

With the VM selected, click **Console**. The embedded viewer polls QEMU
screenshots — enough to watch the installer boot. For full interaction
(mobile pointer, audio, USB) click **Open external viewer** to attach
the SPICE client (`spicy`).

To send keys from the embedded console: use the chord chips
(`Ctrl+Alt+Del`, `Ctrl+Alt+F2`) or type into the text field and press
Send — each character is translated to a QEMU `sendkey` event.

## 6. Stop

Click **Stop** → *Shutdown* (graceful ACPI) or *Kill* (force). Next
steps: [snapshots](howto-console-snapshots.md),
[importing existing VMs](howto-import.md).
