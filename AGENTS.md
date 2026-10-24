# AGENTS.md

Quickgui is a Flutter desktop app that fronts Quickemu/Quickget: discover OS
images (~950 via `quickget --list`), download them into a working directory
and manage the resulting VMs (run, stop, SSH, SPICE, snapshots, config).

## Project structure

```
lib/
  main.dart                 # Entry point, OS catalogue loading, PATH checks
  src/app.dart              # MaterialApp, theme, locale wiring
  src/globals.dart          # Shared helpers (runHost/hostWrap, conf I/O, prefs)
  src/mixins/               # app_version, preferences_mixin
  src/model/                # operating_system, version, option, vminfo, app_settings
  src/pages/                # manager, downloader, *_selection dialogs
  src/widgets/              # home_page/, left_menu, app_bar_title, new_vm_tag
  src/supported_locales.dart
assets/                     # images, i18n (.po files + quickgui.pot)
test/                       # Dart tests
flatpak/                    # Flatpak manifest + metainfo + build docs
docs/                       # man-page sources
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
in `lib/src/globals.dart` so they escape the Flatpak sandbox via
`flatpak-spawn --host` when needed. Never call `Process.run`/`Shell().run`
with a bare command for these tools.

VM .conf files are key="value" files: read with `confValue()`, write with
`writeConfValue()` (both in globals.dart). Runtime state lives in
`<vm>/<vm>.pid`, `<vm>/<vm>.ports`, `<vm>/<vm>.sock`.

## i18n

- Strings are wrapped with `context.t('...')`.
- New msgids must be appended to `assets/i18n/quickgui.pot` (msgid + empty
  msgstr) and ideally translated in the `.po` files.
- Supported locales live in `lib/src/supported_locales.dart`.

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
