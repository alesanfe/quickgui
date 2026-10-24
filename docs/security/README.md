# Security notes

- All external executions go through `SystemProcessRunner`, which
  escapes the Flatpak sandbox via `flatpak-spawn --host` only when the
  flatpak manifest grants it.
- `.conf` files are read key=value, never executed.
- The backend boundary prevents the UI from executing arbitrary
  commands — inputs are validated in the backend layer.
