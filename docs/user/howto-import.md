# How-to — import existing VMs and images

Three import paths, all reachable from **Create** (`Ctrl+3`) by dragging
a file onto the drop zone, or by picking the file.

## Import a disk image (`.iso`, `.qcow2`, `.img`, `.vdi`, `.vmdk`, `.vhdx`, `.raw`)

Drop the file into Create. QuickGUI runs the image-import flow: the
image is copied into the working directory and a `.conf` is generated
alongside it. Set `guest_os` in the conf if the guest type was
misdetected (Machines → select VM → edit conf).

## Import a `.conf`

Drop a `.conf` onto Create — it is copied into the working directory
and registered. Importing a conf executes its `boot=`/`disk_img=` lines
verbatim, so only import confs you trust; the app shows a warning when
the file contains executable directives.

## Import an exported archive (`.tar.gz` / `.tgz`)

Drop an archive onto Create — it is passed to `quickemu --import`,
which validates the manifest and integrity hashes written by
`quickemu --export` before unpacking. Tampered or incomplete archives
are rejected with a typed error, not a silent partial extract.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "unsupported file" on drop | extension must match the lists above |
| VM appears but won't start | open the conf editor — check `disk_img=`/`iso=` paths are relative to the VM dir |
| Archive rejected: integrity | re-export from the source machine; the manifest hashes must match |
