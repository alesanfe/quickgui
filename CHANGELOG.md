# Changelog

All notable changes to this fork are documented here. The project follows
[Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

### Added

- feat: add send-keys, doctor and disk-resize VM actions
- feat: creation wizard, screenshots, drag-and-drop import and i18n pot
- feat: pause/resume/clone/export actions, VM settings, sorting and profiles
- feat: use quickget --list-json and badge driver-assisted VMs
- feat: full quickemu integration pass
- feat: deeper quickemu integration across the board
- feat: surface quickemu snapshots and warn when swtpm is missing
- feat: declutter VM rows with overflow menu and add page transitions
- feat: UX improvements from interface review
- feat: add Flatpak manifest and metainfo
- feat: import a pre-downloaded disk image from the home page
- feat: add expandable terminal output view to the download page
- feat: support more terminals and show quickemu console output
- feat: add 'Forget host key' button to the SSH connection dialog
- feat: make authors and project links clickable in the drawer menu
- feat: track newly installed VMs in prefs
- feat: add label for newly installed vms
- feat: added scroll controller in forms to make OS/Version/options lists scrollable
- feat: added scroll controller in forms to make OS/Version/options lists scrollable


### Fixed

- fix: require both quickget and quickemu in PATH; guard SSH button
- fix: warn on unmet macOS CPU requirements and fix working dir fallback
- fix: allow Flutter >=3.47.2 instead of an exact version pin
- fix: make downloader menu scrollable so bottom buttons are not cropped
- fix: search Homebrew prefixes when quickget is not in PATH
- fix: disable SPICE connect button when the VM reports no SPICE port
- fix: remove duplicate path dependency in pubspec.yaml


### Other

- style: dart format the recently touched files
- chore: regenerate pubspec.lock for flutter >=3.47.2
- po: add Indonesian translation
- docs: fix macOS build output path in README
- docs: restore trailing newline in CONTRIBUTING.md
- Merge branch 'pr-325'
- Merge branch 'pr-275'
- Merge branch 'pr-266'
- Merge branch 'pr-224'
- Merge branch 'pr-303'
- Merge branch 'pr-305'
- Merge branch 'pr-327'
- Merge branch 'pr-317'
- Merge branch 'pr-322'
- Merge branch 'pr-320'
- Merge branch 'pr-318'
- Merge branch 'pr-324'
- Merge branch 'pr-307'
- flake.lock: Update
- Changed "Desenvolvido com" to "Alimentado por"
- Capitalize "o"
- Update pt_PT.po
- build!: update Flutter desktop compatibility
- build(deps): bump DeterminateSystems/flake-checker-action from 12 to 13
- build(deps): bump flutter_distributor from 0.6.6 to 0.6.8
