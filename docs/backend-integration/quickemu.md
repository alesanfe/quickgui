# quickemu backend integration

quickgui consumes quickemu/quickget strictly as an **external
executable**, never as a library. All calls go through
`VirtualizationBackend`
(`lib/features/machines/application/ports/virtualization_backend.dart`)
implemented by `QuickemuBackend`/`StructuredQuickemu` in
`lib/infrastructure/quickemu/`.

## Boundary

```
presentation ──> VirtualizationBackend (interface)
                        │
                        └─ QuickemuBackend ──> ProcessRunner
                                                  └─ SystemProcessRunner
                                                       └─ runHost/hostWrap
                                                            └─ flatpak-spawn --host (sandboxed)
```

- `VirtualizationBackend` — app-owned contract (availability,
  capabilities, OS catalogue, VM list/status, downloads, actions).
- `QuickemuBackend` — adapts the external CLI: prefers the structured
  interface (`--capabilities`, `--list-vms --format json`,
  `--status --format json`, `quickget --list-json`) and falls back to
  CSV/text output on older releases.
- `ProcessRunner`/`SystemProcessRunner` — the only code allowed to
  spawn processes; honours the Flatpak sandbox escape.
- `test/fakes/FakeVirtualizationBackend` — widget/use-case tests never
  touch a real VM.

## Compatibility

- `quickemu --capabilities` reports `schemaVersion` and capability
  flags; quickgui branches on capabilities, not versions.
- Required minimum: any quickemu with `--vm`, `--kill`, `--delete-*`
  (pre-schema releases still work via text fallbacks).
- Exit codes: 0 = success, 1 = failure (documented in quickemu's
  `docs/architecture/public-cli-contract.md`).

## What stays outside the contract

- `.conf` files: quickgui reads/writes `key="value"` entries through
  `VmConfigFileStore` (`lib/infrastructure/storage/vm_config.dart`) —
  atomic writes, fingerprints, `.bak` rotation and three-way merges —
  the file format is quickemu's documented config interface.
- Runtime artefacts (`*.pid`, `*.ports`, `*.sock`): parsed where the
  CLI does not expose them yet (`--list-vms`/`--status --format json`
  is preferred for liveness).
