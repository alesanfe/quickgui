# AGENTS.md

Quickgui is a Flutter desktop app that fronts Quickemu/Quickget: discover OS
images (~950 via `quickget --list`), download them into a working directory
and manage the resulting VMs (run, stop, SSH, SPICE, snapshots, config).

## Project structure

Layered architecture — presentation widgets only talk to the
`VirtualizationBackend` interface, never to processes directly.

```
lib/
  main.dart                 # Thin entry point: delegates to bootstrap()
  app/                      # app.dart, app_version.dart,
                            #   bootstrap/ (app_bootstrap.dart), localization/
                            #   (supported_locales + QuickguiLocalizationsDelegate),
                            #   router/ (appRoute), theme/
  core/
    errors/                 # Failure
    result/                 # Result/Ok/Err (re-exports Failure)
    logging/                # AppLog
    constants/              # preference_keys.dart
    extensions/             # PreferencesRepositoryX (getAs<T>)
  features/                 # catalog diagnostics downloads home machines settings
    <feature>/domain        # models (no flutter/dart:io)
    <feature>/application   # use cases + ports (virtualization_backend, host_probe,
                            #   preferences_repository)
    <feature>/infrastructure # feature-owned port implementations
    <feature>/presentation  # widgets
    <feature>/providers     # Riverpod providers
  infrastructure/
    process/                # ProcessRunner, SystemProcessRunner, host_process.dart
                            #   (runHost/hostWrap), host_platform.dart
    quickemu/               # quickemu_backend / _process / _parser / _contract
    storage/                # vm_config.dart (VmConfigFileStore)
    settings/               # SharedPreferencesRepository
    networking/             # quickgui_releases.dart (update check)
  shared/
    widgets/                # bytes_formatter.dart
    dialogs/                # validated_text_dialog.dart (showValidatedTextDialog)
    forms/                  # (empty)
    providers/              # (empty)
    models/                 # operation_state.dart, os_icons.dart (loadOsIcons)
assets/                     # images/, icons/quickemu/, translations/ (.po + .pot),
                            #   themes/, resources/ (packaging files)
test/
  unit/ widget/ golden/ contract/ architecture/ integration/ capture/ support/
integration_test/           # backend-absence e2e checks (needs device/host)
flatpak/                    # Flatpak manifest + metainfo + build docs
docs/                       # architecture/, backend-integration/, screenshots/
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
`quickget chunkcheck`, tar, xdg-open/open) MUST go through `runHost()` / `hostWrap()`
in `lib/infrastructure/process/host_process.dart` so they escape the Flatpak
sandbox via `flatpak-spawn --host` when needed. Never call
`Process.run`/`Shell().run` with a bare command for these tools.

VM .conf files are key="value" files: accessed through `VmConfigFileStore`
(`lib/infrastructure/storage/vm_config.dart`, implements the
`VmConfigStore` port). Runtime state lives in `<vm>/<vm>.pid`, `<vm>/<vm>.ports`, `<vm>/<vm>.sock`.

## i18n

- Strings are wrapped with `context.t('...')`.
- New msgids must be appended to `assets/translations/quickgui.pot` (msgid + empty
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

- `tray_manager` links against AppIndicator on Linux: `flutter build linux`
  needs `libayatana-appindicator3-dev` (or `libappindicator3-dev` on
  distros without Ayatana). Missing → CMake pkg-config error; tray init
  itself is best-effort at runtime (headless/unsupported = no tray, no
  crash). Flatpak builds bundle it in the manifest.
- Linux uses `xdg-open` for folder opening, macOS uses `open`.
- macOS app launches have a minimal PATH — `/opt/homebrew/bin` and
  `/usr/local/bin` are probed explicitly in `main()`.
- The `.conf`-based `display=` setting overrides the UI SPICE toggle at
  launch time.

## State, models and UI stack (learned)

- State: Riverpod only (`package:provider` removed). Settings live in
  `features/settings/providers/settings_providers.dart`; `bootstrap()` loads them
  with `LoadSettings` and overrides `initialSettingsProvider` /
  `preferencesRepositoryProvider` in `ProviderScope`.
- DI surface: feature `providers/` dirs expose `backendProvider`,
  `osCatalogueProvider` and `osIconsProvider`; `bootstrap()` constructs the
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
