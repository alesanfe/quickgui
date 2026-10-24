# AGENTS.md

Quickgui is a Flutter desktop app that fronts Quickemu/Quickget: discover OS
images (~950 via `quickget --list`), download them into a working directory
and manage the resulting VMs (run, stop, SSH, SPICE, snapshots, config).

## Project structure

Layered architecture — presentation widgets only talk to the
`VirtualizationBackend` interface, never to processes directly.

```
lib/
  main.dart                 # Entry point: backend wiring, catalogue/icons preload, PATH checks
  app/                      # app.dart, dependencies/providers.dart (DI surface), localization/, theme/
  core/result/              # Result/Failure types
  features/                 # catalog diagnostics downloads home machines settings
    <feature>/domain        # models (no flutter/dart:io)
    <feature>/application   # use cases + ports (virtualization_backend, host_probe)
    <feature>/presentation  # widgets
    <feature>/providers     # Riverpod providers
  infrastructure/
    process/                # ProcessRunner, SystemProcessRunner, host_process.dart (runHost/hostWrap)
    platform/               # HostPlatform, SystemHostProbe, executable_locator
    persistence/            # PreferencesRepository + SharedPreferences impl + pref keys
    quickemu/               # QuickemuBackend (port implementation)
    app_info/               # AppVersion (package_info_plus)
    vm_config.dart          # VmConfig + confValue/writeConfValue
  shared/presentation/      # widgets, os_assets/loadOsIcons
assets/                     # images, i18n (.po files + quickgui.pot)
test/
  unit/ widget/ fixtures/ fakes/ helpers/
integration_test/           # backend-absence checks
flatpak/                    # Flatpak manifest + metainfo + build docs
docs/                       # architecture/, backend-integration/
```

## Development commands

```bash
flutter pub get
flutter analyze             # must stay clean (0 issues)
flutter test                # unit/widget tests
dart format lib test        # format is enforced in CI
flutter run -d linux        # run the app
flutter build linux|macos   # release build
```

## External tool integration

All external commands (quickget, quickemu, quickreport, spicy, ssh-keygen,
chunkcheck, tar, xdg-open/open) MUST go through `runHost()` / `hostWrap()`
in `lib/infrastructure/process/host_process.dart` so they escape the Flatpak
sandbox via `flatpak-spawn --host` when needed. Never call
`Process.run`/`Shell().run` with a bare command for these tools.

VM .conf files are key="value" files: read with `confValue()`, write with
`writeConfValue()` (both in `lib/infrastructure/vm_config.dart`). Runtime
state lives in `<vm>/<vm>.pid`, `<vm>/<vm>.ports`, `<vm>/<vm>.sock`.

## i18n

- Strings are wrapped with `context.t('...')`.
- New msgids must be appended to `assets/i18n/quickgui.pot` (msgid + empty
  msgstr) and ideally translated in the `.po` files.
- Supported locales live in `lib/app/localization/supported_locales.dart`.

## Code conventions

- Dart 3.13+ / Flutter 3.47+; Material 3; `gettext_i18n` for translations.
- Always `dart format` before committing.
- Use `context.mounted`/`mounted` guards after async gaps before touching
  `context` or calling `setState`.
- Destructive actions (delete VM/disk) require explicit confirmation dialogs.
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`,
  `ci:`, `test:`.

## Testing

- `flutter analyze` → 0 issues; `flutter test` → all passing.
- For VM-management changes verify the command actually works against a real
  quickemu install (`quickemu --vm x.conf --status`, etc.) — the sibling repo
  quickemu lives in the same parent directory in this workspace.

## Platform notes

- Linux uses `xdg-open` for folder opening, macOS uses `open`.
- macOS app launches have a minimal PATH — `/opt/homebrew/bin` and
  `/usr/local/bin` are probed explicitly in `main()`.
- The `.conf`-based `display=` setting overrides the UI SPICE toggle at
  launch time.

## State, models and UI stack (learned)

- State: Riverpod only (`package:provider` removed). Settings live in
  `features/settings/providers/settings_providers.dart`; `main()` loads them
  with `LoadSettings` and overrides `initialSettingsProvider` /
  `preferencesRepositoryProvider` in `ProviderScope`.
- DI surface: `app/dependencies/providers.dart` exposes `backendProvider`,
  `osCatalogueProvider` and `osIconsProvider`; `main()` constructs the
  backend once and overrides them. Preferences go through
  `preferencesRepositoryProvider` (`getAs<T>`/`set`), not the old
  `PreferencesMixin`.
- Models: Freezed + json_serializable. After editing a `@freezed` class run
  `dart run build_runner build --delete-conflicting-outputs`.
  Freezed 3.2.x + Dart 3.13 emits invalid `final` params for collection
  fields; use `@Freezed(makeCollectionsUnmodifiable: false)` on such models.
- Theme: `flex_color_scheme` is pinned to 8.4.x — 9.x targets the standalone
  `material_ui` package whose `ThemeData` is not the built-in Material one.
- Forms: Formz inputs in `features/machines/domain/forms/vm_inputs.dart`;
  single-field dialogs use `showValidatedTextDialog`.
- Tests that pump widgets using `context.t` must use
  `test/support/harness/test_app.dart` and `pumpAndSettle()` first.
- Goldens (Alchemist, CI mode only): `flutter test --update-goldens test/golden`.
