// Extension members on _ManagerState are part of the same library, but
// `setState` is @protected on State and the analyzer does not treat
// extension code as State instance members. The split is mechanical —
// calls behave exactly as before.
// ignore_for_file: invalid_use_of_protected_member
part of 'manager.dart';

extension on _ManagerState {
  Widget _buildVmList() {
    final List<Widget> widgetList = [];
    final Color buttonColor = Theme.of(context).colorScheme.primary;
    if (!_hasKvm) {
      widgetList.add(
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.t(
                'Hardware virtualisation (/dev/kvm) is not available; VMs will run slowly.',
              ),
            ),
          ),
        ),
      );
    }
    widgetList.addAll([
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              "${context.t('Directory where the machines are stored')}:",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: () async {
                final folder = await FilePicker.getDirectoryPath(
                  dialogTitle: "Pick a folder",
                );
                if (folder != null) {
                  setState(() {
                    Directory.current = folder;
                  });
                  _prefs.set(prefWorkingDirectory, Directory.current.path);
                }
              },
              child: Text(Directory.current.path),
            ),
          ],
        ),
      ),
      const Divider(thickness: 2),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: TextField(
          focusNode: _searchFocus,
          decoration: InputDecoration(
            hintText: context.t('Search virtual machine'),
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (value) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _vmFilter = value);
            });
          },
        ),
      ),
    ]);
    final tags = ref.watch(vmTagsProvider);
    widgetList.add(
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final filter in [
            ('all', context.t('All')),
            ('running', context.t('Running')),
            ('stopped', context.t('Stopped')),
            ('paused', context.t('Paused')),
            ('stale', context.t('Warnings')),
            ('favorite', context.t('Favourites')),
            ('new', context.t('New')),
          ])
            FilterChip(
              label: Text(filter.$2),
              selected: _statusFilter == filter.$1,
              onSelected: (_) => setState(() => _statusFilter = filter.$1),
            ),
          for (final tag in {
            for (final values in tags.values) ...values,
          }.where((t) => t != '_favorite'))
            FilterChip(
              label: Text(tag),
              selected: _tagFilter == tag,
              onSelected: (value) =>
                  setState(() => _tagFilter = value ? tag : null),
            ),
        ],
      ),
    );
    widgetList.add(const SizedBox(height: 12));
    if (_selectionMode) {
      widgetList.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.t('{0} selected', args: ['${_selection.length}'])),
                TextButton(
                  onPressed: () => setState(() {
                    _selection.addAll(_currentVms);
                  }),
                  child: Text(context.t('Select all')),
                ),
                for (final action in [
                  ('start', context.t('Start')),
                  ('stop', context.t('Shut down')),
                  ('pause', context.t('Pause')),
                  ('resume', context.t('Resume')),
                  ('check', context.t('Check VM')),
                  ('export', context.t('Export')),
                  ('tags', context.t('Edit tags')),
                ])
                  OutlinedButton(
                    onPressed: _batchBusy || _selection.isEmpty
                        ? null
                        : () => _batch(action.$1),
                    child: Text(action.$2),
                  ),
                if (_batchBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (_currentVms.isEmpty) {
      widgetList.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.computer, size: 48),
                const SizedBox(height: 12),
                Text(
                  context.t('No virtual machines yet'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.t(
                    'Download an operating system or import a disk image to create your first machine.',
                  ),
                ),
                if (GoRouter.maybeOf(context) != null)
                  TextButton(
                    onPressed: () => context.go('/create'),
                    child: Text(context.t('Create a machine')),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final filteredVms = _currentVms.where((vm) {
      final vmTags = tags[vm] ?? const <String>[];
      final state = _vmStates[vm] ?? 'stopped';
      final text =
          '$vm ${vmTags.join(' ')} ${_vmDetails[vm]?['guest_os'] ?? ''}'
              .toLowerCase();
      final matchesState = switch (_statusFilter) {
        'all' => true,
        'favorite' => vmTags.contains('_favorite'),
        'new' => _newVmNames.contains(vm),
        _ => state == _statusFilter,
      };
      return text.contains(_vmFilter.toLowerCase()) &&
          matchesState &&
          (_tagFilter == null || vmTags.contains(_tagFilter));
    }).toList();
    if (_currentVms.isNotEmpty && filteredVms.isEmpty) {
      widgetList.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.t('No machines match these filters')),
        ),
      );
    }
    if (_vmSort == 'running') {
      filteredVms.sort(
        (a, b) => (_activeVms.containsKey(b) ? 1 : 0).compareTo(
          _activeVms.containsKey(a) ? 1 : 0,
        ),
      );
    }
    final List<List<Widget>> rows = filteredVms.map((vm) {
      return _buildRow(vm, buttonColor);
    }).toList();
    for (final row in rows) {
      if (_cards) {
        widgetList.add(Card(child: Column(children: row)));
      } else {
        widgetList.addAll(row);
      }
    }

    return ListView(padding: const EdgeInsets.all(16.0), children: widgetList);
  }

  List<Widget> _buildRow(String currentVm, Color buttonColor) {
    final bool active = _activeVms.containsKey(currentVm);
    final bool sshy = _sshVms.contains(currentVm);
    final bool newVM = _newVmNames.contains(currentVm);

    VmInfo vmInfo = VmInfo();
    String connectInfo = '';
    if (active) {
      vmInfo = _activeVms[currentVm]!;
      if (vmInfo.spicePort != null) {
        connectInfo += '${context.t('SPICE port')}: ${vmInfo.spicePort!} ';
      }
      if (vmInfo.sshPort != null && _terminalEmulator != null) {
        connectInfo += '${context.t('SSH port')}: ${vmInfo.sshPort!} ';
        _detectSsh(int.tryParse(vmInfo.sshPort!) ?? 0).then((sshRunning) {
          if (sshRunning && !sshy) {
            setState(() {
              _sshVms.add(currentVm);
            });
          } else if (!sshRunning && sshy) {
            setState(() {
              _sshVms.remove(currentVm);
            });
          }
        });
      }
      for (final extra in vmInfo.other) {
        connectInfo += '$extra ';
      }
    }
    String vmStem = currentVm;
    SvgPicture? osIcon;
    while (vmStem.contains('-')) {
      vmStem = vmStem.substring(0, vmStem.lastIndexOf('-'));
      if (ref.read(osIconsProvider).containsKey(vmStem)) {
        osIcon = SvgPicture.asset(
          ref.read(osIconsProvider)[vmStem]!,
          width: 32,
          height: 32,
        );
        break;
      }
    }
    return <Widget>[
      ListTile(
        selected: currentVm == _selectedVm,
        isThreeLine: _cards,
        onLongPress: () => _editTags([currentVm]),
        onTap: () {
          if (MediaQuery.sizeOf(context).width < 1000 &&
              GoRouter.maybeOf(context) != null) {
            context.push('/machines/${Uri.encodeComponent(currentVm)}');
          } else {
            setState(() => _selectedVm = currentVm);
          }
        },
        leading: _selectionMode
            ? Checkbox(
                value: _selection.contains(currentVm),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selection.add(currentVm);
                  } else {
                    _selection.remove(currentVm);
                  }
                }),
              )
            : osIcon ?? const Icon(Icons.computer, size: 32),
        // Live region so screen readers announce VM state transitions
        // (e.g. stopped → running) as the row updates.
        subtitle: Semantics(
          liveRegion: true,
          child: Text(
            switch (_vmStates[currentVm] ?? 'stopped') {
              'running' => context.t('Running'),
              'paused' => context.t('Paused'),
              'stale' => context.t('Stale (process exited unexpectedly)'),
              _ => context.t('Stopped'),
            },
            style: TextStyle(
              fontSize: 12,
              color: switch (_vmStates[currentVm]) {
                'running' => Colors.green,
                'paused' => Theme.of(context).colorScheme.tertiary,
                'stale' => Theme.of(context).colorScheme.error,
                _ => Theme.of(context).colorScheme.onSurfaceVariant,
              },
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(currentVm, overflow: TextOverflow.ellipsis)),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: context.t('Favourite'),
              icon: Icon(
                (ref.watch(vmTagsProvider)[currentVm] ?? const <String>[])
                        .contains('_favorite')
                    ? Icons.star
                    : Icons.star_border,
                size: 18,
              ),
              onPressed: () {
                final tags = ref.read(vmTagsProvider.notifier);
                if (tags.tagsFor(currentVm).contains('_favorite')) {
                  tags.removeTag(currentVm, '_favorite');
                } else {
                  tags.addTag(currentVm, '_favorite');
                }
              },
            ),
            if (_cards) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${_vmDetails[currentVm]?['cpu_cores'] ?? '—'} CPU · ${_vmDetails[currentVm]?['ram'] ?? '—'} RAM',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            if (newVM) const NewVmTag() else const SizedBox.shrink(),
            if (File('$currentVm/virtio-win.iso').existsSync() ||
                File('$currentVm/unattended.iso').existsSync())
              Tooltip(
                message: context.t(
                  'VirtIO drivers / unattended install present',
                ),
                child: const Icon(Icons.download_done, size: 18),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: Icon(
                active ? Icons.play_arrow : Icons.play_arrow_outlined,
                color: active ? Colors.green : buttonColor,
                semanticLabel: active ? 'Running' : 'Run',
              ),
              tooltip: active
                  ? context.t('Running')
                  : context.t('Start the virtual machine'),
              onPressed: active ? null : () => _startVm(currentVm),
            ),
            IconButton(
              icon: Icon(
                active ? Icons.stop : Icons.stop_outlined,
                color: active ? Colors.red : null,
                semanticLabel: active ? 'Stop' : 'Not running',
              ),
              tooltip: active
                  ? context.t('Shut down or stop the virtual machine')
                  : context.t('Not running'),
              onPressed: !active ? null : () => _stopVm(currentVm),
            ),
            VmActionsMenu(
              icon: const Icon(Icons.more_vert, semanticLabel: 'More actions'),
              tooltip: context.t('More actions'),
              // Keep the menu inside the window: with ~17 items it exceeds
              // 800px and traps "Delete" below the fold.
              constraints: const BoxConstraints(maxHeight: 560),
              onSelected: (choice) async {
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
                    unawaited(_backend.openVmFolder(currentVm));
                  case 'snapshot':
                    _manageSnapshot(context, currentVm);
                  case 'shared':
                    _editVmConfValues(currentVm, {
                      'public_dir': context.t('Shared folder'),
                    }, title: context.t('Shared folder'));
                  case 'resources':
                    _editVmConfValues(currentVm, {
                      'ram': context.t('RAM (e.g. 4G)'),
                      'cpu_cores': context.t('CPU cores'),
                      'disk_size': context.t('Disk size (e.g. 64G)'),
                    }, title: context.t('Resources'));
                  case 'display':
                    _editVmConfValues(
                      currentVm,
                      {'viewer': context.t('Display viewer')},
                      title: context.t('Display viewer'),
                      options: {
                        'viewer': ['spicy', 'remote-viewer', 'none'],
                      },
                    );
                  case 'bootnet':
                    _editVmConfValues(
                      currentVm,
                      {
                        'boot': context.t('Boot mode'),
                        'network': context.t('Network'),
                        'macaddr': context.t('MAC address'),
                        'secureboot': context.t('Secure boot'),
                        'tpm': context.t('TPM'),
                      },
                      title: context.t('Boot & network'),
                      options: {
                        'boot': ['efi', 'legacy'],
                        'network': ['nat', 'restrict', 'bridged', 'none'],
                        'secureboot': ['on', 'off'],
                        'tpm': ['on', 'off'],
                      },
                    );
                  case 'devices':
                    _editVmConfValues(currentVm, {
                      'usb_devices': context.t('USB devices'),
                      'gpu_passthrough': context.t('GPU passthrough'),
                      'port_forwards': context.t('Port forwards'),
                      'sound': context.t('Sound'),
                      'display': context.t('Display'),
                    }, title: context.t('Devices'));
                  case 'pause':
                    await runVmActionOrLegacy(_backend, 'pause', [
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--pause',
                    ]);
                  case 'resume':
                    await runVmActionOrLegacy(_backend, 'resume', [
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--resume',
                    ]);
                  case 'screenshot':
                    final r = await runVmActionOrLegacy(
                      _backend,
                      'screenshot',
                      [
                        '--vm',
                        _vmConfFiles[currentVm] ?? '$currentVm.conf',
                        '--screenshot',
                      ],
                    );
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
                    final resetResult = await runVmActionOrLegacy(
                      _backend,
                      'monitor-cmd',
                      [
                        '--vm',
                        _vmConfFiles[currentVm] ?? '$currentVm.conf',
                        '--monitor-cmd',
                        'system_reset',
                      ],
                    );
                    if (!context.mounted) return;
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
                    if (File('$currentVm.tar.gz').existsSync()) {
                      final overwrite = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            context.t(
                              'Replace {0}?',
                              args: ['$currentVm.tar.gz'],
                            ),
                          ),
                          content: Text(
                            context.t(
                              'The file already exists and will be overwritten.',
                            ),
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
                    final r = await _backend.exportVm(currentVm);
                    if (!context.mounted) return;
                    _showProcessOutput([r]);
                  case 'settings':
                    _editVmSettings(currentVm);
                  case 'verify':
                    final iso = ref
                        .read(vmConfigStoreProvider)
                        .read(
                          _vmConfFiles[currentVm] ?? '$currentVm.conf',
                          'iso',
                        );
                    if (iso != null) {
                      final r = await _backend.verifyImage(iso);
                      if (!context.mounted) return;
                      _showProcessOutput([r]);
                    }
                  case 'delete':
                    _confirmDeleteVm(context, currentVm);
                }
              },
              itemBuilder: (context) => [
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
                if (active)
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
                  PopupMenuItem(
                    value: 'resume',
                    child: ListTile(
                      leading: const Icon(Icons.play_circle),
                      title: Text(context.t('Resume')),
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
                if (_cap('tomlConfig') &&
                    !_vmConfFiles[currentVm]!.endsWith('.toml'))
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (connectInfo.isNotEmpty)
        ListTile(
          title: Text(connectInfo, style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                icon: Icon(
                  Icons.monitor,
                  color: (_spicy && vmInfo.spicePort != null)
                      ? buttonColor
                      : null,
                  semanticLabel: 'Connect display with SPICE',
                ),
                tooltip: _spicy
                    ? context.t('Connect display with SPICE')
                    : context.t('SPICE client not found'),
                onPressed: !_spicy || vmInfo.spicePort == null
                    ? null
                    : () {
                        unawaited(
                          _backend.launchSpiceViewer(vmInfo.spicePort!),
                        );
                      },
              ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/images/console.svg',
                  semanticsLabel: 'Connect with SSH',
                  colorFilter: ColorFilter.mode(
                    sshy ? buttonColor : Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                tooltip: !sshy
                    ? context.t('SSH server not detected on guest')
                    : _terminalEmulator == null
                    ? context.t('No terminal emulator found')
                    : context.t('Connect with SSH'),
                onPressed: !sshy || _terminalEmulator == null
                    ? null
                    : () async {
                        final savedUser = await _prefs.getAs<String>(
                          'sshUser_$currentVm',
                        );
                        if (!mounted) return;
                        final TextEditingController
                        usernameController = TextEditingController(
                          text: savedUser ?? Platform.environment['USER'] ?? '',
                        );
                        showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(
                              context.t(
                                'Launch SSH connection to {0}',
                                args: [currentVm],
                              ),
                            ),
                            content: TextField(
                              controller: usernameController,
                              decoration: InputDecoration(
                                hintText: context.t("SSH username"),
                              ),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  // Remove the stale known_hosts entry, e.g.
                                  // when a new guest reuses the SSH port of a
                                  // deleted VM.
                                  unawaited(
                                    _backend.forgetSshHostKey(vmInfo.sshPort!),
                                  );
                                },
                                child: Text(context.t('Forget host key')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.t('Cancel')),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(context.t('Connect')),
                              ),
                            ],
                          ),
                        ).then((result) {
                          result = result ?? false;
                          if (result) {
                            _prefs.set(
                              'sshUser_$currentVm',
                              usernameController.text,
                            );
                            unawaited(
                              _backend.connectSsh(
                                terminalEmulator: _terminalEmulator!,
                                user: usernameController.text,
                                sshPort: vmInfo.sshPort!,
                              ),
                            );
                          }
                        });
                      },
              ),
            ],
          ),
        ),
      const Divider(),
    ];
  }
}
