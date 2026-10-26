# Architecture overview

Layered Flutter app — presentation widgets only talk to ports, never
to processes directly.

```
lib/
  main.dart                     thin entry point → bootstrap()
  app/                          MaterialApp, router (GoRouter), theme,
                                bootstrap/, localization/, shell/
  core/
    errors/                     Failure, AppFailure (typed backend codes)
    result/                     Result/Ok/Err
    logging/                    AppLog + LogStore (structured, local-only)
    telemetry/                  LegacyTelemetry, LegacyPolicy
    constants/                  preference_keys.dart
    extensions/                 PreferencesRepositoryX (getAs<T>)
  features/
    activity/                   operation centre: states, history,
                                retry descriptors, reconciliation
    catalog/                    OS catalogue (OperatingSystem/Version/Option)
    create/                     download controls + 5-step wizard
    diagnostics/                CollectDiagnostics, DiagnosticsReport
    downloads/                  background download tasks
    home/                       dashboard
    machines/                   VM library, details, conf editor,
                                settings page, snapshots
      application/ports/        VirtualizationBackend, VmConfigStore
      presentation/list/        manager.dart (library + actions)
    settings/                   preferences, ui preferences
  infrastructure/
    process/                    ProcessRunner, SystemProcessRunner,
                                host_process.dart (runHost/hostWrap,
                                flatpak-spawn escape)
    quickemu/                   QuickemuBackend, StructuredQuickemu,
                                structured_or_legacy, vm envelope parsing
    storage/                    VmConfigFileStore (atomic writes,
                                fingerprint, backups, ConfDocument merge)
    settings/                   SharedPreferencesRepository
  shared/                       models (OperationState, os_icons),
                                widgets, dialogs (conf_conflict)
assets/                         images, icons, translations (.po/.pot),
                                themes, packaging resources
test/
  unit/ widget/ contract/ architecture/ integration/ capture/ golden/
  support/                      fakes + test_app harness
```

## Boundary rules

- Presentation → `VirtualizationBackend` interface → `QuickemuBackend`
  → `ProcessRunner` → `SystemProcessRunner` → `runHost`/`hostWrap`.
- VM commands prefer the **structured contract** (`--format json`
  envelope) via `StructuredQuickemu`/`runVmJson`; legacy text output is
  used only when the backend cannot produce an envelope (see
  `docs/architecture/structured-quickemu.md`).
- `.conf` files go through `VmConfigFileStore` — atomic write,
  fingerprinted external-change detection, rotated `.bak` backups and
  three-way merge (`ConfDocument` + `mergeConfDocuments`).
- Operations run through `activityProvider` — a single history with
  typed failures, retry descriptors, cancellation and restart
  reconciliation.

## State and DI

- Riverpod only. Providers live in `features/<f>/providers/`; fakes
  override `backendProvider`/`hostProbeProvider`/`osCatalogueProvider`
  in tests via `test/support/harness/test_app.dart`.
- Preferences flow through `preferencesRepositoryProvider` /
  `getAs<T>` — the old `PreferencesMixin`/`globals.dart` are gone.
- Freezed models: after edits run
  `dart run build_runner build --delete-conflicting-outputs`.

See also: `docs/backend-integration/quickemu.md`,
`docs/architecture/structured-quickemu.md`, `docs/adr/0001-backend-boundary.md`.
