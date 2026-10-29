# Capability coverage matrix

Generated from `assets/capabilities/capability_manifest.json` by `tool/generate_capability_matrix.dart`. Do not edit by hand.

| Capability | Domain | Backend | Quickgui | Tests | Status |
|---|---|---|---|---|---|
| `vm.lifecycle.start` | lifecycle | `--vm, --start` | vm_list.context_menu.start, vm_details.primary_action | 1 | Sí |
| `vm.lifecycle.status` | lifecycle | `--status` | vm_list.state_badge, vm_details.state | 2 | Sí |
| `vm.lifecycle.shutdown` | lifecycle | `--shutdown` | vm_list.context_menu.stop, vm_details.stop | 1 | Sí |
| `vm.lifecycle.kill` | lifecycle | `--kill, --stop` | vm_menu.force_stop, vm_menu.stop_confirm.force | 1 | Sí |
| `vm.lifecycle.reset` | lifecycle | `--reset` | vm_menu.lifecycle.reset | 1 | Sí |
| `vm.lifecycle.pause` | lifecycle | `--pause` | vm_menu.lifecycle.pause | 1 | Sí |
| `vm.lifecycle.resume` | lifecycle | `--resume` | vm_menu.lifecycle.resume | 1 | Sí |
| `vm.lifecycle.fullscreen` | lifecycle | `--fullscreen, --full-screen` | vm_menu.display_viewer.fullscreen, settings.preferred_viewer | 1 | Sí |
| `vm.lifecycle.statusQuo` | lifecycle | `--status-quo` | vm_menu.maintenance.check_vm | 1 | Sí |
| `vm.lifecycle.offline` | lifecycle | `--offline` | vm_settings.network_key | 1 | Sí |
| `vm.lifecycle.restart` | lifecycle | `--restart` | — | 0 | Pendiente |
| `vm.library.list` | library | `--list-vms` | machines.list, dashboard.vm_cards | 2 | Sí |
| `vm.library.inspectConf` | library | `--inspect-conf` | vm_settings.all_dialog, vm_page.configuration | 1 | Sí |
| `vm.library.doctor` | library | `--doctor` | diagnostics.host_checks, vm_page.doctor_action, vm_menu.maintenance.check_vm | 1 | Sí |
| `vm.library.doctorFix` | library | `--fix` | — | 0 | Pendiente |
| `vm.snapshot.create` | snapshots | `--snapshot` | vm_menu.snapshots.create | 2 | Sí |
| `vm.snapshot.apply` | snapshots | `--snapshot apply` | vm_menu.snapshots.apply | 1 | Sí |
| `vm.snapshot.delete` | snapshots | `--snapshot delete` | vm_menu.snapshots.delete | 1 | Sí |
| `vm.snapshot.info` | snapshots | `--snapshot info` | vm_menu.snapshots.info | 1 | Sí |
| `vm.snapshot.tree` | snapshots | `--snapshot-tree` | vm_menu.snapshots.tree | 1 | Sí |
| `vm.snapshot.verify` | snapshots | `--snapshot-verify` | — | 0 | Pendiente |
| `vm.delete.plan` | deletion | `--delete-plan` | vm_menu.delete.plan_dialog | 2 | Sí |
| `vm.delete.vm` | deletion | `--delete-vm, --plan-id, --trash` | vm_menu.delete.confirm | 1 | Sí |
| `vm.delete.disk` | deletion | `--delete-disk` | vm_menu.delete.disk_option | 1 | Sí |
| `vm.trash.list` | deletion | `--trash-list` | vm_menu.maintenance.trash | 2 | Sí |
| `vm.trash.restore` | deletion | `--trash-restore` | vm_menu.maintenance.trash_restore | 1 | Sí |
| `vm.trash.empty` | deletion | `--trash-empty` | — | 0 | Pendiente |
| `desktop.shortcut` | desktop | `--shortcut, --delete-shortcut` | — | 0 | No |
| `vm.backup.create` | backup | `--backup` | vm_menu.maintenance.backups.create | 1 | Sí |
| `vm.backup.list` | backup | `--backup-list` | vm_menu.maintenance.backups.list | 2 | Sí |
| `vm.backup.restore` | backup | `--backup-restore` | vm_menu.maintenance.backups.restore | 1 | Sí |
| `vm.backup.prune` | backup | `--backup-prune` | vm_menu.maintenance.backups.prune | 1 | Sí |
| `vm.backup.verify` | backup | `--backup-verify` | — | 0 | Pendiente |
| `vm.clone` | migration | `--clone, --full` | vm_menu.clone | 1 | Sí |
| `vm.linkedClone` | migration | `--linked-clone` | vm_menu.clone.linked | 1 | Sí |
| `vm.rename` | migration | `--rename` | vm_menu.rename | 1 | Sí |
| `vm.move` | migration | `--move` | vm_menu.move | 1 | Sí |
| `vm.export` | migration | `--export` | vm_menu.export, vm_list.batch.export | 1 | Sí |
| `vm.import` | migration | `--import` | create.import.drop, create.import.picker | 1 | Sí |
| `vm.disk.resize` | disks | `--disk-resize` | vm_menu.resize | 1 | Sí |
| `vm.disk.compact` | disks | `--disk-compact` | vm_menu.maintenance.disk_compact | 1 | Sí |
| `vm.disk.create` | disks | `--create-disk` | — | 0 | Pendiente |
| `vm.disk.resizeCommit` | disks | `--resize-commit` | — | 0 | Pendiente |
| `vm.image.verify` | disks | `quickget chunkcheck` | vm_menu.maintenance.verify_image | 1 | Sí |
| `vm.monitor.cmd` | monitor | `--monitor-cmd` | vm_menu.maintenance.monitor_cmd | 1 | Sí |
| `vm.input.sendKeys` | monitor | `--send-keys` | vm_menu.maintenance.send_keys | 1 | Sí |
| `vm.input.type` | monitor | `--type` | vm_menu.maintenance.type_text | 1 | Sí |
| `vm.monitor.screenshot` | monitor | `--screenshot` | vm_menu.maintenance.screenshot | 1 | Sí |
| `vm.hotplug.usb` | hotplug | `--hotplug-usb` | vm_menu.devices.hotplug_usb | 1 | Sí |
| `vm.hotplug.disk` | hotplug | `--hotplug-disk` | vm_menu.devices.hotplug_disk | 1 | Sí |
| `vm.hotplug.unplug` | hotplug | `--hotunplug` | — | 0 | Pendiente |
| `vm.hotplug.persist` | hotplug | `--persist` | vm_menu.devices.hotplug_* | 0 | Parcial |
| `ops.events` | operations | `--events` | activity.events_feed | 1 | Sí |
| `ops.status` | operations | `--op-status` | activity.operation_tile | 1 | Sí |
| `ops.list` | operations | `--op-list` | activity.list | 2 | Sí |
| `ops.watch` | operations | `--op-watch` | activity.live_updates | 1 | Sí |
| `ops.cancel` | operations | `--op-cancel` | activity.operation_tile.cancel | 1 | Sí |
| `ops.aliasLong` | operations | `--operation-status, --operation-list, --operation-cancel, --operation-watch` | — | 0 | Justificada |
| `backend.inventory` | registry | `--inventory` | diagnostics.inventory, machines.library_sync | 1 | Sí |
| `backend.plugins.list` | plugins | `--plugins` | diagnostics.plugins | 1 | Sí |
| `backend.plugins.dispatch` | plugins | `--plugin` | — | 0 | Pendiente |
| `vm.stats` | monitor | `--stats` | vm_details.stats | 2 | Sí |
| `vm.profile` | config | `--profile` | create_wizard.hardware_profiles, vm_menu.start_profile | 1 | Sí |
| `vm.config.migrateToml` | config | `--migrate-conf` | vm_menu.migrate_toml | 1 | Sí |
| `backend.hostInfo` | diagnostics | `--host-info` | diagnostics.host_section | 1 | Sí |
| `backend.capabilities` | diagnostics | `--capabilities` | diagnostics.capabilities_section, app.feature_gating | 1 | Sí |
| `backend.vfioScan` | diagnostics | `--vfio-scan` | diagnostics.vfio_scan | 1 | Sí |
| `backend.version` | diagnostics | `--version` | diagnostics.version_line, settings.about | 1 | Sí |
| `backend.report` | diagnostics | `quickreport` | diagnostics.copy_report, settings.quickemu_report | 1 | Sí |
| `backend.contract.json` | internal | `--format` | — | 0 | Justificada |
| `backend.dryRun` | internal | `--dry-run, --echo` | — | 0 | Justificada |
| `backend.external` | internal | `--external` | — | 0 | Justificada |
| `backend.param.vm` | internal | `--vm` | — | 0 | Justificada |
| `backend.param.planId` | internal | `--plan-id` | — | 0 | Justificada |
| `backend.alias` | internal | `--list, --vms, --conf, --plan, --scan, --keys, --cmd, --disk, --watch, --cancel, --restore, --verify, --quo, --msrs, --msrs-always, --apply, --info, --create, --delete, --resize, --console, --vnc, --spice-console, --publicdir, --snapshot-list, --snapshot-apply, --snapshot-create, --snapshot-delete, --snapshot-info, --ignore-msrs, --serial-console, --monitor-console, --disk-resize-commit, --extra-args, --keyboard-layout` | — | 0 | Justificada |
| `cli.help` | internal | `--help` | — | 0 | Justificada |
| `launch.display` | launch | `--display` | vm_settings.display_key, settings.preferred_viewer | 1 | Sí |
| `launch.viewer` | launch | `--viewer` | settings.preferred_viewer, vm_settings.viewer_key | 1 | Sí |
| `launch.publicDir` | launch | `--public-dir` | vm_settings.public_dir_key | 1 | Sí |
| `launch.usbPassthrough` | launch | `--usb-passthrough` | vm_settings.usb_devices_key | 1 | Sí |
| `launch.soundCard` | launch | `--sound-card, --sound-duplex` | vm_settings.sound_key | 0 | Parcial |
| `launch.geometry` | launch | `--width, --height` | — | 0 | Justificada |
| `launch.netTuning` | launch | `--ssh-port, --spice-port, --ssh-access, --access` | — | 0 | Justificada |
| `launch.hwTuning` | launch | `--monitor, --monitor-telnet-host, --monitor-telnet-port, --serial, --serial-telnet-host, --serial-telnet-port, --keyboard, --keyboard_layout, --mouse, --usb-controller` | — | 0 | Justificada |
| `launch.quirks` | launch | `--cpu-pinning, --braille, --ignore-msrs-always, --ignore-tsc-warning` | — | 0 | Justificada |
| `launch.extraArgs` | launch | `--extra_args` | — | 0 | No |
| `vm.autostart` | desktop | `--autostart` | — | 0 | Pendiente |
| `catalog.list` | catalog | `--list-json, --list, --list-csv` | create.catalog, home.quick_create | 2 | Sí |
| `catalog.show` | catalog | `--show` | — | 0 | Pendiente |
| `download.image` | downloads | `--download` | create.download, download_tasks | 1 | Sí |
| `download.check` | downloads | `--check` | create.download.preflight, download_controls.check | 1 | Sí |
| `download.checkAllArch` | downloads | `--check-all-arch` | — | 0 | Pendiente |
| `download.createConfig` | downloads | `--create-config` | create.import.flow | 1 | Sí |
| `download.arch` | downloads | `--arch` | create_wizard.system | 0 | Parcial |
| `download.unattended` | downloads | `--unattended, --disable-unattended` | — | 0 | Pendiente |
| `download.cloudInit` | downloads | `--cloud-init` | — | 0 | Pendiente |
| `download.update` | downloads | `--update` | — | 0 | Pendiente |
| `download.openHomepage` | downloads | `--open-homepage` | — | 0 | Pendiente |
| `download.urlOverride` | internal | `--url` | — | 0 | Justificada |
| `download.insecure` | security | `--insecure, --minimum-trust` | — | 0 | No |
| `quickget.version` | diagnostics | `--version` | diagnostics.version_line | 1 | Sí |
| `config.document.edit` | config | `VmConfigFileStore` | vm_settings.all_dialog | 2 | Sí |
| `library.state.refresh` | library | `VmLibraryProvider` | machines.list.state_badges | 1 | Sí |
| `activity.auditTrail` | operations | `ActivityProvider` | activity.list, activity.operation_tile | 1 | Sí |
| `app.downloadNotifications` | operations | `AppShell` | system.desktop_notification | 1 | Sí |

## Metrics

| Metric | Value |
|---|---|
| Capabilities | 105 |
| implemented | 70 |
| partiallyImplemented | 3 |
| planned | 16 |
| unsupported | 3 |
| notApplicable | 13 |
| Weighted coverage score | 89.8% |

