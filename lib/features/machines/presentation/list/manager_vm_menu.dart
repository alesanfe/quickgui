// Menu actions and items for the VM row overflow menu. Split out of
// manager_rows.dart — the cascading menu grew to ~800 lines. Same library
// (`part of`), same extension on _ManagerState: calls behave as before.
part of 'manager.dart';

extension on _ManagerState {
  /// Choices whose execution depends on the VM's live state — these
  /// revalidate before running so a stale menu can never start an
  /// already-running VM or delete one that changed (QGUI-X-004).
  static const _stateDependentChoices = {
    'start',
    'pause',
    'resume',
    'suspend',
    'reset',
    'send-keys',
    'screenshot',
    'start-offline',
    'start-profile',
    'guest-agent',
    'serial-console',
    'monitor-console',
    'verify',
    'export',
    'launch-plan',
    'doctor',
    'shortcut',
    'remove-shortcut',
  };

  /// Dispatches a VmActionsMenu selection for [currentVm].
  Future<void> _vmMenuAction(String currentVm, String choice) async {
    // Never act on the state captured when the menu was rendered:
    // revalidate the conf and, for state-dependent actions, the live
    // state (QGUI-X-004 / QGUI-MENU-103).
    if (!await _revalidateVm(
          currentVm,
          stateSensitive: _stateDependentChoices.contains(choice),
        ) ||
        !mounted) {
      return;
    }
    switch (choice) {
      case 'migrate-toml':
        _migrateToToml(currentVm);
      case 'move':
        showDialog<void>(
          context: context,
          builder: (dialogContext) => _MoveRenameDialog(
            backend: _backend,
            vm: currentVm,
            confPath: _vmConfFiles[currentVm]!,
            onChanged: _getVms,
          ),
        );
      case 'hotplug':
        showDialog<void>(
          context: context,
          builder: (dialogContext) => _HotplugDialog(
            backend: _backend,
            vm: currentVm,
            confPath: _vmConfFiles[currentVm]!,
          ),
        );
      case 'backup':
        showDialog<void>(
          context: context,
          builder: (dialogContext) => _BackupsDialog(
            backend: _backend,
            vm: currentVm,
            confPath: _vmConfFiles[currentVm] ?? '$currentVm.conf',
            onChanged: _getVms,
          ),
        );
      case 'config':
        showDialog<void>(
          context: context,
          builder: (context) => VmConfigEditorDialog(
            vmName: currentVm,
            confPath: _vmConfFiles[currentVm]!,
          ),
        );
      case 'folder':
        unawaitedLogged(
          _backend.openVmFolder(currentVm),
          AppLog.vmLifecycle,
          'open folder $currentVm',
        );
      case 'snapshot':
        // Same surface as the details pane: the full
        // snapshots view (tree, sizes, live-create options,
        // policy, verify) instead of the legacy mini-dialog.
        showSnapshotsDialog(
          context,
          vm: currentVm,
          confPath: _vmConfFiles[currentVm] ?? '$currentVm.conf',
        );
      case 'shared':
        // Structured model (QGUI-SHARE-101/103): primary share via
        // public_dir, optional extra 9p shares (share_dirs/share_tags
        // pair) and guest→host inboxes, each with its own explanation.
        _editVmConfValues(
          currentVm,
          {
            'public_dir': context.t('Host directory to share'),
            'share_dirs': context.t('Extra shared directories'),
            'share_tags': context.t('Mount tags'),
            'share_in_dirs': context.t('Guest-to-host inbox directories'),
          },
          title: context.t('Shared folder'),
          helpers: {
            'public_dir': context.t(
              'Exposed to the guest as a network/shared folder. The guest needs the matching driver or mount helper, and changes apply on the next start. Prefer read-only data — guests can modify these files. Avoid sharing your whole home directory or credential folders.',
            ),
            'share_dirs': context.t(
              'Optional space-separated host paths shared via virtiofs (quickemu 5.0+).',
            ),
            'share_tags': context.t(
              'Space-separated mount tags matching the extra directories, in the same order — the guest mounts them by tag.',
            ),
            'share_in_dirs': context.t(
              'Space-separated directories the guest can write into (inboxes). Leave empty unless a workflow needs guest-to-host transfers.',
            ),
          },
          fieldBuilders: {
            'public_dir': (context, controller) => PathPickerField(
              controller: controller,
              label: context.t('Host directory to share'),
            ),
          },
        );
      case 'resources':
        _openVmSettings(currentVm, 'resources');
      case 'display':
        // Viewer selector marks binaries the host probe did not find
        // (QGUI-VIEW-002) and explains when the change takes effect.
        // 'Automatic' is resolved against the real host probe so the
        // user sees which concrete viewer it will pick (QGUI-VIEW-101).
        final viewerLabel = context.t('Viewer');
        // The dialog shell already appends the VM name to the title.
        final viewerTitle = context.t('Display viewer');
        final available = <String, bool>{};
        for (final v in const ['spicy', 'remote-viewer']) {
          available[v] = await _probe.hasTool(v);
        }
        if (!mounted) return;
        final resolved = available.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .firstOrNull;
        final viewerHelper = resolved == null
            ? context.t(
                'No supported viewer (spicy, remote-viewer) was found on this host — install one or pick a different display type. Tools marked "not installed" will fail at launch; check Diagnostics.',
              )
            : context.t(
                'Automatic resolves to {0} on this host. The change applies on the next start; tools marked "not installed" will fail at launch — check Diagnostics.',
                args: [resolved],
              );
        _editVmConfValues(
          currentVm,
          {'viewer': viewerLabel},
          title: viewerTitle,
          helpers: {'viewer': viewerHelper},
          fieldBuilders: {
            'viewer': (context, controller) => ViewerSelector(
              controller: controller,
              label: viewerLabel,
              available: available,
            ),
          },
        );
      case 'bootnet':
        _openVmSettings(currentVm, 'boot,network');
      case 'devices':
        _openVmSettings(currentVm, 'devices');
      case 'pause':
        await _runVmOp(OperationKind.command, currentVm, 'pause', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--pause',
        ]);
      case 'start':
        _startVm(currentVm);
      case 'resume':
        await _runVmOp(OperationKind.command, currentVm, 'resume', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--resume',
        ]);
      case 'screenshot':
        final r = await runVmActionOrLegacy(_backend, 'screenshot', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--screenshot',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'send-keys':
        final r = await runVmActionOrLegacy(_backend, 'send-keys', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--send-keys',
          'ctrl-alt-delete',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'start-profile':
        final profileId = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(context.t('Start with profile')),
            children: [
              for (final p in vmProfiles)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, p.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name),
                        if (p.description.isNotEmpty)
                          Text(
                            p.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
        if (profileId == null || !context.mounted) return;
        await _runVmOpRaw(
          OperationKind.start,
          currentVm,
          () => _backend.startWithProfile(currentVm, profileId),
        );
        _getVms();
      case 'start-offline':
        final r = await _runVmOp(OperationKind.start, currentVm, 'start', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--offline',
        ]);
        if (!context.mounted || r == null) return;
        _showProcessOutput([r]);
        _getVms();
      case 'suspend':
        final r = await _runVmOp(OperationKind.command, currentVm, 'suspend', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--suspend',
        ]);
        if (!context.mounted || r == null) return;
        _showProcessOutput([r]);
        _getVms();
      case 'guest-agent':
        await showDialog<void>(
          context: context,
          builder: (context) => _GuestAgentDialog(
            backend: _backend,
            vm: currentVm,
            confPath: _vmConfFiles[currentVm] ?? '$currentVm.conf',
          ),
        );
        _getVms();
      case 'serial-console':
      case 'monitor-console':
        // Interactive telnet attach — needs a real TTY, so
        // it launches inside the configured terminal
        // emulator rather than a captive pipe.
        final r = await _backend.launchVmToolInTerminal(
          _terminalEmulator ?? 'xterm',
          choice,
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
        );
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'shortcut':
        final r = await runVmActionOrLegacy(_backend, 'shortcut', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--shortcut',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'remove-shortcut':
        final r = await runVmActionOrLegacy(_backend, 'shortcut-delete', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--delete-shortcut',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'launch-plan':
        // `--echo` resolves the conf and prints the assembled
        // QEMU invocation (vm.plan envelope) without booting.
        final r = await runVmActionOrLegacy(_backend, 'plan', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--echo',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'reset':
        // QEMU monitor `system_reset` — equivalent to pressing
        // the reset button: abrupt reboot, unsaved guest state
        // may be lost, so confirm first.
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.t('Reset {0}?', args: [currentVm])),
            content: Text(
              context.t(
                'The virtual machine reboots immediately. Unsaved guest state may be lost.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.t('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.t('Reset')),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        final resetResult = await _runVmOp(
          OperationKind.command,
          currentVm,
          'monitor-cmd',
          [
            '--vm',
            _vmConfFiles[currentVm] ?? '$currentVm.conf',
            '--monitor-cmd',
            'system_reset',
          ],
        );
        if (!context.mounted || resetResult == null) return;
        _showProcessOutput([resetResult]);
      case 'doctor':
        final r = await runVmActionOrLegacy(_backend, 'doctor', [
          '--vm',
          _vmConfFiles[currentVm] ?? '$currentVm.conf',
          '--doctor',
        ]);
        if (!context.mounted) return;
        _showProcessOutput([r]);
      case 'resize':
        _resizeVmDisk(context, currentVm);
      case 'clone':
        _cloneVm(context, currentVm);
      case 'export':
        // Export writes <vm>.tar.gz in the working directory —
        // confirm before overwriting an existing archive.
        if (File(
          path.join(ref.read(workingDirectoryProvider), '$currentVm.tar.gz'),
        ).existsSync()) {
          final overwrite = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                context.t('Replace {0}?', args: ['$currentVm.tar.gz']),
              ),
              content: Text(
                context.t('The file already exists and will be overwritten.'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.t('Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.t('Replace')),
                ),
              ],
            ),
          );
          if (overwrite != true) return;
        }
        final r = await _runVmOpRaw(
          OperationKind.export,
          currentVm,
          () => _backend.exportVm(currentVm),
        );
        if (!context.mounted || r == null) return;
        _showProcessOutput([r]);
      case 'settings':
        // Same surface as the details pane Configure button:
        // the sectioned settings page when a router exists,
        // the compact dialog only as a no-router fallback.
        if (GoRouter.maybeOf(context) != null) {
          context.push('/machines/${Uri.encodeComponent(currentVm)}/settings');
        } else {
          _editVmSettings(currentVm);
        }
      case 'verify':
        final iso = ref
            .read(vmConfigStoreProvider)
            .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'iso');
        if (iso != null) {
          final r = await _runVmOpRaw(
            OperationKind.verify,
            currentVm,
            () => _backend.verifyImage(iso),
          );
          if (!context.mounted || r == null) return;
          _showProcessOutput([r]);
        }
      case 'delete':
        _confirmDeleteVm(context, currentVm);
    }
  }

  /// PopupMenuEntry list for the row's VmActionsMenu.
  List<PopupMenuEntry<String>> _vmMenuItems(
    BuildContext context,
    String currentVm, {
    required bool active,
    required VmInfo vmInfo,
    required String connectInfo,
    required bool sshy,
    required Color buttonColor,
  }) => [
    PopupMenuItem(
      value: 'config',
      child: ListTile(
        leading: const Icon(Icons.settings),
        title: Text(context.t('Edit configuration')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'folder',
      child: ListTile(
        leading: const Icon(Icons.folder_open),
        title: Text(context.t('Open VM folder')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuDivider(),
    if (_cap('snapshots'))
      PopupMenuItem(
        value: 'snapshot',
        child: ListTile(
          leading: const Icon(Icons.photo_camera),
          title: Text(context.t('Snapshots')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'shared',
      child: ListTile(
        leading: const Icon(Icons.folder_shared),
        title: Text(context.t('Shared folder')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'resources',
      child: ListTile(
        leading: const Icon(Icons.memory),
        title: Text(context.t('Resources')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'display',
      child: ListTile(
        leading: const Icon(Icons.display_settings),
        title: Text(context.t('Display viewer')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'bootnet',
      child: ListTile(
        leading: const Icon(Icons.lan),
        title: Text(context.t('Boot & network')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'devices',
      child: ListTile(
        leading: const Icon(Icons.developer_board),
        title: Text(context.t('Devices')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    if (_cap('verifiedArchives'))
      PopupMenuItem(
        value: 'verify',
        child: ListTile(
          leading: const Icon(Icons.verified),
          title: Text(context.t('Verify image')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (_vmStates[currentVm] == 'paused' || _vmStates[currentVm] == 'suspended')
      PopupMenuItem(
        value: 'resume',
        child: ListTile(
          leading: const Icon(Icons.play_circle),
          title: Text(context.t('Resume')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      )
    else if (active)
      PopupMenuItem(
        value: 'pause',
        child: ListTile(
          leading: const Icon(Icons.pause),
          title: Text(context.t('Pause')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      )
    else
      // `--resume` errors on a stopped VM ("not running") —
      // offer the real start path instead.
      PopupMenuItem(
        value: 'start',
        child: ListTile(
          leading: const Icon(Icons.play_arrow),
          title: Text(context.t('Start')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active && _cap('screenshot'))
      PopupMenuItem(
        value: 'screenshot',
        child: ListTile(
          leading: const Icon(Icons.screenshot_monitor),
          title: Text(context.t('Screenshot')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active && _cap('sendKeys'))
      PopupMenuItem(
        value: 'send-keys',
        child: ListTile(
          leading: const Icon(Icons.keyboard),
          title: Text(context.t('Send Ctrl+Alt+Del')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active && _cap('monitorCommands'))
      PopupMenuItem(
        value: 'reset',
        child: ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Text(context.t('Reset')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (!active && _cap('profiles'))
      PopupMenuItem(
        value: 'start-profile',
        child: ListTile(
          leading: const Icon(Icons.playlist_play),
          title: Text(context.t('Start with profile')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (!active)
      PopupMenuItem(
        value: 'start-offline',
        child: ListTile(
          leading: const Icon(Icons.wifi_off),
          title: Text(context.t('Start offline (no network)')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active)
      PopupMenuItem(
        value: 'suspend',
        child: ListTile(
          leading: const Icon(Icons.bedtime),
          title: Text(context.t('Suspend to disk')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active)
      PopupMenuItem(
        value: 'guest-agent',
        child: ListTile(
          leading: const Icon(Icons.terminal),
          title: Text(context.t('Guest agent…')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (active) ...[
      PopupMenuItem(
        value: 'serial-console',
        child: ListTile(
          leading: const Icon(Icons.cable),
          title: Text(context.t('Serial console')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'monitor-console',
        child: ListTile(
          leading: const Icon(Icons.bug_report),
          title: Text(context.t('Monitor console')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
    PopupMenuItem(
      value: 'shortcut',
      child: ListTile(
        leading: const Icon(Icons.shortcut),
        title: Text(context.t('Create desktop shortcut')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    PopupMenuItem(
      value: 'remove-shortcut',
      child: ListTile(
        leading: const Icon(Icons.shortcut_outlined),
        title: Text(context.t('Remove desktop shortcut')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    if (!active)
      PopupMenuItem(
        value: 'launch-plan',
        child: ListTile(
          leading: const Icon(Icons.preview),
          title: Text(context.t('Preview launch command')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'doctor',
      child: ListTile(
        leading: const Icon(Icons.health_and_safety),
        title: Text(context.t('Check VM')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    if (_cap('diskOps'))
      PopupMenuItem(
        value: 'resize',
        child: ListTile(
          leading: const Icon(Icons.expand),
          title: Text(context.t('Resize disk')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (_cap('clone'))
      PopupMenuItem(
        value: 'clone',
        child: ListTile(
          leading: const Icon(Icons.content_copy),
          title: Text(context.t('Clone')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (_cap('exportImport'))
      PopupMenuItem(
        value: 'export',
        child: ListTile(
          leading: const Icon(Icons.archive),
          title: Text(context.t('Export')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (_cap('tomlConfig') && !_vmConfFiles[currentVm]!.endsWith('.toml'))
      PopupMenuItem(
        value: 'migrate-toml',
        child: ListTile(
          leading: const Icon(Icons.transform),
          title: Text(context.t('Migrate to TOML')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'move',
      child: ListTile(
        leading: const Icon(Icons.drive_file_move),
        title: Text(context.t('Move / Rename')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    if (_cap('hotplug'))
      PopupMenuItem(
        value: 'hotplug',
        child: ListTile(
          leading: const Icon(Icons.usb),
          title: Text(context.t('Hotplug devices')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    if (_cap('verifiedArchives'))
      PopupMenuItem(
        value: 'backup',
        child: ListTile(
          leading: const Icon(Icons.backup),
          title: Text(context.t('Backups')),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    PopupMenuItem(
      value: 'settings',
      child: ListTile(
        leading: const Icon(Icons.tune),
        title: Text(context.t('Settings (all)')),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ),
    const PopupMenuDivider(),
    if (_cap('safeDeletePlan'))
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            context.t('Delete'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
  ];
}
