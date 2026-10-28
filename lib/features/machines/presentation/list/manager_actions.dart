// Extension members on _ManagerState are part of the same library, but
// `setState` is @protected on State and the analyzer does not treat
// extension code as State instance members. The split is mechanical —
// calls behave exactly as before.
// ignore_for_file: invalid_use_of_protected_member
part of 'manager.dart';

extension on _ManagerState {
  Future<void> _editTags(Iterable<String> machines) async {
    final targets = machines.toList();
    final controller = TextEditingController(
      text: targets.length == 1
          ? ref
                .read(vmTagsProvider.notifier)
                .tagsFor(targets.single)
                .where((tag) => tag != '_favorite')
                .join(', ')
          : '',
    );
    final tags = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Edit tags')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.t('Comma-separated tags'),
            helperText: context.t('Use group:name to organise a collection'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.t('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (tags == null || !mounted) return;
    final notifier = ref.read(vmTagsProvider.notifier);
    for (final name in targets) {
      await notifier.setTags(
        name,
        {
          ...tags
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty && t != '_favorite'),
          if (notifier.tagsFor(name).contains('_favorite')) '_favorite',
        }.toList(),
      );
    }
  }

  Future<void> _batch(String action) async {
    final names = _selection.toList();
    if (names.isEmpty || _batchBusy) return;
    final included = names.toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(context.t('Review batch operation')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.t('Action: {0}', args: [action])),
                  for (final name in names)
                    CheckboxListTile(
                      value: included.contains(name),
                      title: Text(name),
                      subtitle: Text(_vmStates[name] ?? 'stopped'),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          included.add(name);
                        } else {
                          included.remove(name);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: included.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: Text(context.t('Continue')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    if (action == 'tags') {
      await _editTags(included);
      return;
    }
    setState(() => _batchBusy = true);
    final failures = <String>[];
    try {
      for (final name in included) {
        try {
          final conf = _vmConfFiles[name] ?? '$name.conf';
          if (action == 'start') {
            await _startVm(name);
            continue;
          }
          final result = action == 'export'
              ? await _backend.exportVm(name)
              : await runVmActionOrLegacy(
                  _backend,
                  switch (action) {
                    'stop' => 'powerdown',
                    'pause' => 'pause',
                    'resume' => 'resume',
                    _ => 'doctor',
                  },
                  [
                    '--vm',
                    conf,
                    switch (action) {
                      'stop' => '--powerdown',
                      'pause' => '--pause',
                      'resume' => '--resume',
                      _ => '--doctor',
                    },
                  ],
                );
          if (result.exitCode != 0) failures.add(name);
        } catch (_) {
          failures.add(name);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
        _getVms();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failures.isEmpty
                  ? context.t('Batch operation completed')
                  : context.t(
                      'Some machines failed: {0}',
                      args: [failures.join(', ')],
                    ),
            ),
          ),
        );
      }
    }
  }

  /// [title] names the purpose of the dialog (e.g. 'Resources') so the
  /// user sees a semantic heading instead of the raw .conf filename.
  Future<void> _editVmConfValues(
    String currentVm,
    Map<String, String> keys, {
    required String title,
    Map<String, List<String>>? options,
  }) async {
    // The editor speaks key="value" .conf syntax - a migrated VM may
    // expose its .toml as the backend path, so always edit the .conf
    // and re-migrate afterwards to keep TOML in sync.
    final confPath = (_vmConfFiles[currentVm] ?? '$currentVm.conf').replaceAll(
      RegExp(r'\.toml$'),
      '.conf',
    );
    final file = File(confPath);
    final lines = file.existsSync() ? await file.readAsLines() : <String>[];
    final controllers = <String, TextEditingController>{};
    for (final key in keys.keys) {
      final re = RegExp('^$key="(.*)"');
      var current = '';
      for (final l in lines) {
        final m = re.firstMatch(l);
        if (m != null) current = m.group(1)!;
      }
      controllers[key] = TextEditingController(text: current);
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title — $currentVm'),
        content: SizedBox(
          width: double.maxFinite,
          // Scrollable: the 16-field "Settings (all)" dialog must stay
          // usable at the minimum window height (~800px).
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: keys.entries.map((e) {
                final opts = options?[e.key];
                final current = controllers[e.key]!.text;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: opts == null
                      ? TextField(
                          controller: controllers[e.key],
                          decoration: InputDecoration(labelText: e.value),
                        )
                      : DropdownButtonFormField<String>(
                          // Keep the current value as an extra item when it
                          // is not one of the known options — picking
                          // opts.first would silently rewrite the .conf on OK.
                          initialValue: current.isEmpty ? null : current,
                          decoration: InputDecoration(labelText: e.value),
                          items: {...opts, if (current.isNotEmpty) current}
                              .map(
                                (o) =>
                                    DropdownMenuItem(value: o, child: Text(o)),
                              )
                              .toList(),
                          onChanged: (v) => controllers[e.key]!.text = v ?? '',
                        ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('OK')),
          ),
        ],
      ),
    );
    if (result != true) return;
    for (final key in keys.keys) {
      final value = encodeVmValue(controllers[key]!.text);
      final re = RegExp('^$key="');
      var replaced = false;
      for (var i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) {
          lines[i] = '$key="$value"';
          replaced = true;
          break;
        }
      }
      if (!replaced) lines.add('$key="$value"');
    }
    // Atomic commit (temp + verify + .bak + rename) — a torn write must
    // never corrupt the VM configuration.
    VmConfigFileStore.unawaitedWrite(confPath, '${lines.join('\n')}\n');
    // Keep a migrated .toml in sync — the backend prefers it over .conf.
    if (File(confPath.replaceAll(RegExp(r'\.conf$'), '.toml')).existsSync()) {
      try {
        await _backend.migrateConfToToml(confPath);
      } catch (_) {
        // Legacy backend without --migrate-conf: the .conf still applies.
      }
    }
  }

  void _manageSnapshot(BuildContext context, String currentVm) async {
    // Expose quickemu's --snapshot apply/create/delete/info actions.
    // Load the existing snapshots first (v1 vm-snapshots contract) so
    // the dialog can list them like VirtualBox/Boxes do.
    final confPath = _vmConfFiles[currentVm] ?? '$currentVm.conf';
    final snapshots = await _backend.listSnapshots(confPath);
    if (!context.mounted) return;
    final tagController = TextEditingController();
    final selection = await showDialog<({String action, String tag})>(
      context: context,
      builder: (context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: tagController,
        builder: (context, value, _) {
          final tag = value.text.trim();
          return AlertDialog(
            title: Text(context.t('Snapshots {0}', args: [currentVm])),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshots.isNotEmpty) ...[
                  Text(
                    context.t('Existing snapshots'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  // Fixed size: a shrink-wrap ListView breaks the
                  // AlertDialog intrinsic-dimension pass.
                  SizedBox(
                    height: snapshots.length.clamp(1, 4) * 48.0,
                    width: 360,
                    child: ListView(
                      children: [
                        for (final s in snapshots)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history),
                            title: Text('${s['name']}'),
                            subtitle: Text(_formatSnapshotDate(s['date'])),
                            onTap: () => tagController.text = '${s['name']}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: tagController,
                  decoration: InputDecoration(
                    hintText: context.t('Snapshot tag'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('Cancel')),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop((action: 'info', tag: '')),
                child: Text(context.t('Info')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'create', tag: tag)),
                child: Text(context.t('Create')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'apply', tag: tag)),
                child: Text(context.t('Apply')),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'delete', tag: tag)),
                child: Text(context.t('Delete')),
              ),
            ],
          );
        },
      ),
    );
    if (selection == null) return;
    // Applying a snapshot replaces the current disk state and deleting
    // removes it permanently — both need an explicit confirmation.
    if (selection.action == 'apply' || selection.action == 'delete') {
      if (!context.mounted) return;
      final isDelete = selection.action == 'delete';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            isDelete
                ? context.t('Delete snapshot {0}', args: [selection.tag])
                : context.t('Apply snapshot {0}', args: [selection.tag]),
          ),
          content: Text(
            isDelete
                ? context.t(
                    'The snapshot {0} of {1} will be permanently deleted. This cannot be undone.',
                    args: [selection.tag, currentVm],
                  )
                : context.t(
                    'The current state of {0} will be replaced by the snapshot {1}. This cannot be undone.',
                    args: [currentVm, selection.tag],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: isDelete
                  ? Text(context.t('Delete'))
                  : Text(context.t('Apply')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final results = await runVmActionOrLegacy(
      _backend,
      'snapshot-${selection.action}',
      [
        '--vm',
        confPath,
        '--snapshot',
        selection.action,
        if (selection.tag.isNotEmpty) selection.tag,
      ],
    );
    if (!mounted) return;
    _showProcessOutput([results]);
  }

  void _confirmDeleteVm(BuildContext context, String currentVm) async {
    // Preview what will be deleted via the backend's safe delete plan.
    final planResult = await DeleteVm(_backend).plan(currentVm);
    var planText = switch (planResult) {
      Ok<DeletePlan>(value: final v) when v.files.isNotEmpty => v.files.join(
        '\n',
      ),
      _ => '',
    };
    final planId = switch (planResult) {
      Ok<DeletePlan>(value: final v) => v.planId,
      _ => null,
    };
    if (planText.isEmpty) {
      // Backends without a delete plan still need to show exactly what is
      // about to be removed: the .conf plus every file in the VM folder.
      final paths = <String>[
        _vmConfFiles[currentVm] ?? '$currentVm.conf',
        if (Directory(currentVm).existsSync())
          ...Directory(currentVm).listSync(recursive: true).map((e) => e.path),
      ]..sort();
      planText = paths.join('\n');
    }
    if (!context.mounted) return;
    showDialog<String?>(
      context: context,
      builder: (BuildContext context) {
        final error = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: error),
              const SizedBox(width: 8),
              Flexible(child: Text(context.t('Delete {0}', args: [currentVm]))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(
                  'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?',
                  args: [currentVm],
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    planText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text(context.t('Cancel')),
              onPressed: () => Navigator.pop(context, 'cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: error),
              onPressed: () => Navigator.pop(context, 'disk'),
              child: Text(context.t('Delete disk image')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, 'vm'),
              child: Text(context.t('Delete whole VM')),
            ),
          ],
        );
      },
    ).then((result) async {
      result = result ?? 'cancel';
      if (result != 'cancel') {
        final List<String> command = [
          'quickemu',
          '--vm',
          '$currentVm.conf',
          '--delete-$result',
          // The planId proves the file set did not change since the
          // plan preview — the backend refuses stale plans.
          if (planId != null) ...['--plan-id', planId],
        ];
        await runVmActionOrLegacy(
          _backend,
          'delete-$result',
          command.sublist(1),
        );
      }
    });
  }

  /// `--migrate-conf`: writes `<vm>.toml` next to the `.conf`; the
  /// scanner then prefers the TOML so every backend call uses it.
  Future<void> _migrateToToml(String vm) async {
    final confPath = _vmConfFiles[vm] ?? '$vm.conf';
    try {
      await _backend.migrateConfToToml(confPath);
      _getVms();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t('Migrated to TOML'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${context.t('Error')}: $e')));
      }
    }
  }

  /// Backend trash (`--trash-list`) — VMs deleted via the structured
  /// path land here and can be restored instead of lost.
  void _showTrash() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          _TrashDialog(backend: _backend, onRestored: _getVms),
    );
  }

  void _cloneVm(BuildContext context, String currentVm) async {
    final name = await showValidatedTextDialog<VmNameError>(
      context: context,
      title: context.t('Clone {0}', args: [currentVm]),
      label: context.t('New VM name'),
      confirmLabel: context.t('Clone'),
      initialValue: '$currentVm-copy',
      dirty: VmNameInput.dirty,
      message: (context, e) => context.vmNameError(e),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final r = await runVmActionOrLegacy(_backend, 'clone', [
      '--vm',
      _vmConfFiles[currentVm] ?? '$currentVm.conf',
      '--clone',
      name,
    ]);
    if (!mounted) return;
    _showProcessOutput([r]);
    _getVms();
  }

  Future<void> _startVm(String currentVm) async {
    final Map<String, VmInfo> activeVms = _activeVms;
    final List<String> command = ['quickemu', '--vm', '$currentVm.conf'];
    // Respect a display= setting in the .conf; fall back
    // to the SPICE toggle.
    final confDisplay = ref
        .read(vmConfigStoreProvider)
        .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'display');
    if (confDisplay != null && confDisplay.isNotEmpty) {
      if (confDisplay != 'none') {
        command.addAll(['--display', confDisplay]);
      }
    } else if (_spicy) {
      command.addAll(['--display', 'spice']);
    }
    final startResult = await StartVm(_backend)(
      currentVm,
      display: command.contains('--display')
          ? command[command.indexOf('--display') + 1]
          : null,
    );
    if (!mounted) return;
    if (startResult is Err) {
      _showProcessOutput([ProcResult(1, '', startResult.failure.message)]);
    }
    final VmInfo info = _parseVmInfo(currentVm);
    activeVms[currentVm] = info;
    setState(() {
      _activeVms = activeVms;
      _vmStates[currentVm] = 'running';
    });
  }

  Future<void> _stopVm(String currentVm) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final error = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: Text(context.t('Stop {0}', args: [currentVm])),
          content: Text(
            context.t(
              'Shut down {0} gracefully, or force it to stop? Forcing discards unsaved changes in the guest.',
              args: [currentVm],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: error),
              onPressed: () => Navigator.pop(context, 'kill'),
              child: Text(context.t('Force stop')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'shutdown'),
              child: Text(context.t('Shut down')),
            ),
          ],
        );
      },
    );
    if (choice == 'shutdown') {
      // ACPI powerdown via the QEMU monitor socket; the
      // VM keeps running until the guest OS finishes.
      final r = await runVmActionOrLegacy(_backend, 'monitor-cmd', [
        '--vm',
        _vmConfFiles[currentVm] ?? '$currentVm.conf',
        '--monitor-cmd',
        'system_powerdown',
      ]);
      if (!mounted) return;
      _showProcessOutput([r]);
    } else if (choice == 'kill') {
      // If Quickemu is newer than 4.9.6, use the new --kill option
      // which is macOS compatible.
      final quickemuVersion = Version.parse(await _backend.version());
      if (quickemuVersion >= Version(4, 9, 6)) {
        StopVm(_backend)(currentVm);
      } else {
        unawaitedLogged(
          _backend.killVmProcess(currentVm),
          AppLog.vmLifecycle,
          'kill $currentVm',
        );
      }
      setState(() {
        _activeVms.remove(currentVm);
        _vmStates[currentVm] = 'stopped';
      });
    }
  }

  void _editVmSettings(String currentVm) {
    _editVmConfValues(
      currentVm,
      title: context.t('Settings (all)'),
      {
        'guest_os': context.t('Guest OS'),
        'ram': context.t('RAM'),
        'cpu_cores': context.t('CPU cores'),
        'disk_size': context.t('Disk size'),
        'boot': context.t('Boot mode'),
        'network': context.t('Network'),
        'macaddr': context.t('MAC address'),
        'secureboot': context.t('Secure boot'),
        'tpm': context.t('TPM'),
        'usb_devices': context.t('USB devices'),
        'gpu_passthrough': context.t('GPU passthrough'),
        'port_forwards': context.t('Port forwards'),
        'public_dir': context.t('Shared folder'),
        'viewer': context.t('Display viewer'),
        'display': context.t('Display'),
        'sound': context.t('Sound'),
      },
      options: {
        'boot': ['efi', 'legacy'],
        'network': ['nat', 'restrict', 'bridged', 'none'],
        'secureboot': ['on', 'off'],
        'tpm': ['on', 'off'],
        'viewer': ['spicy', 'remote-viewer', 'none'],
      },
    );
  }

  void _resizeVmDisk(BuildContext context, String currentVm) async {
    // Prefill with the current size so the user knows what they grow from.
    final currentSize =
        ref
            .read(vmConfigStoreProvider)
            .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'disk_size') ??
        '64G';
    if (!context.mounted) return;
    final size = await showValidatedTextDialog<SizeError>(
      context: context,
      title: context.t('Resize disk of {0}', args: [currentVm]),
      label: context.t(
        'New size (current: {0}, grow only)',
        args: [currentSize],
      ),
      confirmLabel: context.t('Resize'),
      initialValue: currentSize,
      dirty: SizeInput.dirty,
      message: (context, e) => context.sizeError(e),
    );
    if (size == null || size.isEmpty || !mounted) return;
    final r = await runVmActionOrLegacy(_backend, 'disk-resize', [
      '--vm',
      _vmConfFiles[currentVm] ?? '$currentVm.conf',
      '--disk-resize',
      size,
    ]);
    if (!mounted) return;
    _showProcessOutput([r]);
  }

  void _showProcessOutput(List<ProcResult> results) {
    final output = results
        .map((r) => '${r.stdout}${r.stderr}')
        .where((s) => s.trim().isNotEmpty)
        .join('\n')
        .trim();
    if (output.isEmpty) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Command output')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              output,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Dismiss')),
          ),
        ],
      ),
    );
  }
}

/// 'YYYY-MM-DD HH:MM' from the contract's unix timestamp; '' when
/// the backend did not provide one.
String _formatSnapshotDate(dynamic date) {
  if (date is! num) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch((date * 1000).round())
      .toLocal()
      .toString();
  return dt.length >= 16 ? dt.substring(0, 16) : dt;
}
