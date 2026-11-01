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
                  // Incompatible batch actions explain themselves
                  // (QGUI-MACH-003): empty selection and busy state
                  // carry a keyboard-accessible reason.
                  if (_batchBusy || _selection.isEmpty)
                    DisabledReason(
                      reason: _batchBusy
                          ? context.t('A batch operation is in progress')
                          : context.t('Select machines first'),
                      child: OutlinedButton(
                        onPressed: null,
                        child: Text(action.$2),
                      ),
                    )
                  else
                    OutlinedButton(
                      onPressed: () => _batch(action.$1),
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
    void addVmRows(Iterable<String> vms) {
      for (final vm in vms) {
        final row = _buildRow(vm, buttonColor);
        if (_cards) {
          widgetList.add(Card(child: Column(children: row)));
        } else {
          widgetList.addAll(row);
        }
      }
    }

    // QG-032 — when any visible VM carries a `group:name` tag, section
    // the list by collection (collapsible, state kept per name);
    // ungrouped machines sort last.
    final grouped = groupMachines(filteredVms, tags);
    final hasCollections = grouped.keys.any((key) => key != null);
    if (!hasCollections) {
      addVmRows(grouped[null] ?? const []);
    } else {
      for (final entry in grouped.entries) {
        final collection = entry.key;
        if (collection != null) {
          final collapsed = _collapsedGroups.contains(collection);
          widgetList.add(
            ListTile(
              dense: true,
              leading: Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
              ),
              title: Text(
                collection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                context.t('{0} machines', args: ['${entry.value.length}']),
              ),
              onTap: () => setState(() {
                collapsed
                    ? _collapsedGroups.remove(collection)
                    : _collapsedGroups.add(collection);
              }),
            ),
          );
          if (!collapsed) addVmRows(entry.value);
        } else {
          addVmRows(entry.value);
        }
      }
    }

    return ListView(padding: const EdgeInsets.all(16.0), children: widgetList);
  }

  /// Warn chip when the VM journal recorded crashes or failed
  /// operations in the last 24 h — the journal is read once per
  /// library refresh, not tailed (QG-023/QG-041).
  Widget _journalBadge(String vm) {
    final issues = ref.watch(vmRecentIssuesProvider(vm)).asData?.value ?? 0;
    if (issues == 0) return const SizedBox.shrink();
    return Tooltip(
      message: context.t(
        '{0} journal event(s) need attention (24 h).',
        args: ['$issues'],
      ),
      child: Icon(
        Icons.warning_amber,
        size: 18,
        color: Theme.of(context).colorScheme.error,
      ),
    );
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
                unawaitedLogged(
                  tags.tagsFor(currentVm).contains('_favorite')
                      ? tags.removeTag(currentVm, '_favorite')
                      : tags.addTag(currentVm, '_favorite'),
                  AppLog.preferences,
                  'toggle favorite $currentVm',
                );
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
            _journalBadge(currentVm),
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
            // M-03 / QGUI-UX-002: the unavailable Stop is recognisably
            // disabled AND explains its precondition through the
            // DisabledReason wrapper (tooltip + semantics, keyboard
            // focusable) instead of a bare grey icon.
            reasonedIconButton(
              context: context,
              icon: active ? Icons.stop : Icons.stop_outlined,
              color: active ? Colors.red : null,
              tooltip: context.t('Shut down or stop the virtual machine'),
              semanticLabel: active ? 'Stop' : 'Not running',
              disabledReason: context.t('Available while the VM is running'),
              onPressed: !active ? null : () => _stopVm(currentVm),
            ),
            if (active)
              IconButton(
                icon: Icon(
                  _vmStates[currentVm] == 'paused'
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  semanticLabel: _vmStates[currentVm] == 'paused'
                      ? 'Resume'
                      : 'Pause',
                ),
                tooltip: _vmStates[currentVm] == 'paused'
                    ? context.t('Resume the virtual machine')
                    : context.t('Pause the virtual machine'),
                onPressed: () => _pauseResumeVm(currentVm),
              ),
            VmActionsMenu(
              icon: const Icon(Icons.more_vert, semanticLabel: 'More actions'),
              tooltip: context.t('More actions'),
              // Keep the menu inside the window: with ~17 items it exceeds
              // 800px and traps "Delete" below the fold.
              constraints: const BoxConstraints(maxHeight: 560),
              onSelected: (choice) => _vmMenuAction(currentVm, choice),
              itemBuilder: (context) => _vmMenuItems(
                context,
                currentVm,
                active: active,
                vmInfo: vmInfo,
                connectInfo: connectInfo,
                sshy: sshy,
                buttonColor: buttonColor,
              ),
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
              reasonedIconButton(
                context: context,
                icon: Icons.monitor,
                color: (_spicy && vmInfo.spicePort != null)
                    ? buttonColor
                    : null,
                semanticLabel: 'Connect display with SPICE',
                tooltip: context.t('Connect display with SPICE'),
                disabledReason: !_spicy
                    ? context.t('SPICE client not found')
                    : context.t('No SPICE display on this VM'),
                onPressed: !_spicy || vmInfo.spicePort == null
                    ? null
                    : () {
                        unawaitedLogged(
                          _backend.launchSpiceViewer(vmInfo.spicePort!),
                          AppLog.vmLifecycle,
                          'spice viewer :${vmInfo.spicePort!}',
                        );
                      },
              ),
              () {
                // Same disabled-reason treatment for the SVG SSH button
                // — reasonedIconButton only covers IconData icons.
                final button = IconButton(
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
                          final TextEditingController usernameController =
                              TextEditingController(
                                text:
                                    savedUser ??
                                    Platform.environment['USER'] ??
                                    '',
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
                                    unawaitedLogged(
                                      _backend.forgetSshHostKey(
                                        vmInfo.sshPort!,
                                      ),
                                      AppLog.vmLifecycle,
                                      'forget ssh key :${vmInfo.sshPort!}',
                                    );
                                  },
                                  child: Text(context.t('Forget host key')),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
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
                              unawaitedLogged(
                                _backend.connectSsh(
                                  terminalEmulator: _terminalEmulator!,
                                  user: usernameController.text,
                                  sshPort: vmInfo.sshPort!,
                                ),
                                AppLog.vmLifecycle,
                                'ssh :${vmInfo.sshPort!}',
                              );
                            }
                          });
                        },
                );
                if (!sshy || _terminalEmulator == null) {
                  return DisabledReason(
                    reason: !sshy
                        ? context.t('SSH server not detected on guest')
                        : context.t('No terminal emulator found'),
                    child: button,
                  );
                }
                return button;
              }(),
            ],
          ),
        ),
      const Divider(),
    ];
  }
}
