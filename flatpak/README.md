# Flatpak packaging

Build and install Quickgui as a Flatpak:

```shell
flatpak-builder --user --install --force-clean \
    build-dir flatpak/io.github.quickemu_project.Quickgui.yml
flatpak run io.github.quickemu_project.Quickgui
```

Notes:

- The manifest builds from the local source tree and downloads the Flutter
  SDK pinned by version and sha256.
- `--filesystem=home` is granted because Quickgui stores VMs in a
  user-selected working directory and shells out to `quickget`/`quickemu`.
- Quickemu itself must be installed and reachable in `PATH`. Inside a
  sandbox that means bundling it or using `flatpak-spawn --host`; the
  `--talk-name=org.freedesktop.Flatpak` permission is included so a future
  `flatpak-spawn` integration is possible.
