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
    // Left undisposed on purpose: the pop animation still rebuilds
    // the field and a disposed controller would throw.
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
  /// [fieldBuilders] lets a key render a structured editor (path picker,
  /// viewer selector) instead of the generic text/dropdown field, and
  /// [helpers] attaches always-visible helper text (QGUI-UX-001).
  Future<void> _editVmConfValues(
    String currentVm,
    Map<String, String> keys, {
    required String title,
    Map<String, List<String>>? options,
    Map<String, Widget Function(BuildContext, TextEditingController)>?
    fieldBuilders,
    Map<String, String>? helpers,
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
    final result = await QDialog.show<bool>(
      context,
      title: '$title — $currentVm',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: keys.entries.map((e) {
          final builder = fieldBuilders?[e.key];
          final opts = options?[e.key];
          final current = controllers[e.key]!.text;
          final helper = helpers?[e.key];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: builder != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      builder(context, controllers[e.key]!),
                      if (helper != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            helper,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  )
                : opts == null
                ? TextField(
                    controller: controllers[e.key],
                    decoration: InputDecoration(
                      labelText: e.value,
                      helperText: helper,
                      helperMaxLines: 4,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    // Keep the current value as an extra item when it
                    // is not one of the known options — picking
                    // opts.first would silently rewrite the .conf on OK.
                    initialValue: current.isEmpty ? null : current,
                    decoration: InputDecoration(
                      labelText: e.value,
                      helperText: helper,
                      helperMaxLines: 4,
                    ),
                    items: {...opts, if (current.isNotEmpty) current}
                        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) => controllers[e.key]!.text = v ?? '',
                  ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t('Save')),
        ),
      ],
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
              if (_activeVms.containsKey(currentVm))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FieldHelp(
                    description: context.t(
                      'This machine is currently running.',
                    ),
                    constraint: context.t(
                      'Stop it first — deleting a running VM can corrupt its disk image.',
                    ),
                  ),
                ),
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
        final r = await runVmActionOrLegacy(
          _backend,
          'delete-$result',
          command.sublist(1),
        );
        // Show the backend's own delete report so partial failures and
        // paths needing manual cleanup are visible (QGUI-DELETE-002).
        if (mounted) _showProcessOutput([r]);
        if (mounted) _getVms();
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
    // QGUI-CLONE-001/002: the two clone modes have different titles and
    // consequences — a full copy is independent but duplicates the disk;
    // a linked clone is instant and space-efficient but its disk reads
    // from the source image, which must not be moved or deleted.
    var linked = false;
    final running = _activeVms.containsKey(currentVm);
    // The controller lives outside the StatefulBuilder — recreating it
    // on every setState would reset the typed name to the default.
    final controller = TextEditingController(text: '$currentVm-copy');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return QDialog(
            title: linked
                ? context.t('Create linked clone of {0}', args: [currentVm])
                : context.t('Clone {0}', args: [currentVm]),
            width: 480,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.t('Cancel')),
              ),
              // The confirm action disables itself while the name is
              // invalid — the reason stays keyboard-accessible next
              // to the button (QGUI-UX-002/004).
              Builder(
                builder: (context) {
                  final v = controller.text.trim();
                  final inputError = VmNameInput.dirty(v).error;
                  final error = v.isEmpty
                      ? context.t('Enter a name')
                      : inputError == null
                      ? null
                      : context.vmNameError(inputError) ??
                            context.t('Enter a name');
                  final label = linked
                      ? context.t('Create linked clone')
                      : context.t('Clone');
                  if (error != null) {
                    return DisabledReason(
                      reason: error,
                      child: FilledButton(onPressed: null, child: Text(label)),
                    );
                  }
                  return FilledButton(
                    onPressed: () => Navigator.of(context).pop(v),
                    child: Text(label),
                  );
                },
              ),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioGroup<String>(
                  groupValue: linked ? 'linked' : 'full',
                  onChanged: (v) => setState(() => linked = v == 'linked'),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'full',
                        title: Text(context.t('Full clone')),
                        subtitle: Text(
                          context.t(
                            'Copies the whole disk — independent, uses as much space as the original.',
                          ),
                        ),
                      ),
                      RadioListTile<String>(
                        value: 'linked',
                        title: Text(context.t('Linked clone')),
                        subtitle: Text(
                          context.t(
                            'Shares the source disk — instant and small, but moving or deleting {0} breaks the clone.',
                            args: [currentVm],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (running)
                  FieldHelp(
                    description: context.t(
                      'The machine is running — cloning an active disk may produce an inconsistent copy.',
                    ),
                    constraint: context.t(
                      'Stop the machine first for a reliable clone.',
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.t('New VM name'),
                    helperText: context.t(
                      'Ports and other identifiers are regenerated for the clone.',
                    ),
                    helperMaxLines: 3,
                    errorText: context.vmNameError(
                      VmNameInput.dirty(controller.text.trim()).error,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          );
        },
      ),
    );
    // Not disposing [controller] here: showDialog's future resolves
    // before the exit transition finishes, and the field rebuilds
    // during it — disposing now would throw "controller used after
    // dispose". The controller has no native resources, so leaving
    // it to the GC is safe.
    if (name == null || name.isEmpty || !mounted) return;
    if (linked) {
      try {
        await _backend.linkedClone(currentVm, name);
      } catch (e) {
        if (!mounted) return;
        _showProcessOutput([ProcResult(1, '', '$e')]);
        return;
      }
      if (!mounted) return;
      _getVms();
      return;
    }
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

  /// Card quick-action (QG-031): pause a running VM or resume a
  /// paused one — the batch path already proves the command pair.
  Future<void> _pauseResumeVm(String currentVm) async {
    final paused = _vmStates[currentVm] == 'paused';
    final r = await runVmActionOrLegacy(_backend, paused ? 'resume' : 'pause', [
      '--vm',
      _vmConfFiles[currentVm] ?? '$currentVm.conf',
      if (paused) '--resume' else '--pause',
    ]);
    if (!mounted) return;
    _showProcessOutput([r]);
    if (r.exitCode == 0) {
      setState(() => _vmStates[currentVm] = paused ? 'running' : 'paused');
    }
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
      // QGUI-STOP-002: a graceful powerdown request does not mean the
      // machine is off — offer a visible force-stop path for guests
      // that ignore ACPI instead of leaving the user guessing.
      if (r.exitCode == 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t(
                'Shutdown requested — {0} will stop when the guest finishes.',
                args: [currentVm],
              ),
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: context.t('Force stop'),
              onPressed: () => _forceStopVm(currentVm),
            ),
          ),
        );
      }
    } else if (choice == 'kill') {
      await _forceStopVm(currentVm);
    }
  }

  /// Immediate termination path shared by the confirmation dialog and
  /// the post-shutdown snackbar action (QGUI-STOP-002).
  Future<void> _forceStopVm(String currentVm) async {
    {
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

  /// Single structured editor for every conf surface (QGUI-ALLSET-006):
  /// the sectioned VmSettingsPage is pushed as a full route, with
  /// [section] filtering it to the domain group the menu named.
  void _openVmSettings(String currentVm, [String? section]) {
    final page = VmSettingsPage(vmName: currentVm, section: section);
    if (GoRouter.maybeOf(context) != null) {
      final query = section == null
          ? ''
          : '?section=${Uri.encodeComponent(section)}';
      context.push(
        '/machines/${Uri.encodeComponent(currentVm)}/settings$query',
      );
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (context) => page));
    }
  }

  void _editVmSettings(String currentVm) => _openVmSettings(currentVm);

  void _resizeVmDisk(BuildContext context, String currentVm) async {
    // Prefill with the current size so the user knows what they grow from.
    final currentSize =
        ref
            .read(vmConfigStoreProvider)
            .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'disk_size') ??
        '64G';
    if (!context.mounted) return;
    // Structured number+unit field (QGUI-RESIZE-001): the current size
    // and the grow-only constraint are persistent text, not stuffed
    // into the label where long translations truncate.
    final controller = TextEditingController(text: currentSize);
    final size = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => QDialog(
          title: context.t('Resize disk of {0}', args: [currentVm]),
          width: 480,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('Cancel')),
            ),
            // Disabled while the value is not a larger size than the
            // current one — the comparison runs on bytes so 512M <
            // 32G is handled correctly (QGUI-RESIZE-003).
            Builder(
              builder: (context) {
                final v = controller.text.trim();
                final isSize = RegExp(
                  r'^\d+(?:\.\d+)?[KMGT]$',
                  caseSensitive: false,
                ).hasMatch(v);
                final parse = _sizeToBytes(v);
                final current = _sizeToBytes(currentSize);
                final tooSmall =
                    parse != null && current != null && parse <= current;
                final error = !isSize
                    ? context.t('Enter a size')
                    : (tooSmall
                          ? context.t(
                              'The new size must be larger than {0}',
                              args: [currentSize],
                            )
                          : null);
                if (error != null) {
                  return DisabledReason(
                    reason: error,
                    child: FilledButton(
                      onPressed: null,
                      child: Text(context.t('Resize')),
                    ),
                  );
                }
                return FilledButton(
                  onPressed: () => Navigator.of(context).pop(v.toUpperCase()),
                  child: Text(context.t('Resize')),
                );
              },
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('Current size: {0}', args: [currentSize]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizeField(
                controller: controller,
                label: context.t('New size'),
                units: const ['G', 'M', 'T'],
                allowEmpty: false,
                onChanged: () => setState(() {}),
              ),
              FieldHelp(
                description: context.t(
                  'Disks can only grow — shrinking is not supported.',
                ),
                constraint: context.t(
                  'The new size must be larger than the current one and the machine should be stopped.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // See above — the exit transition still rebuilds the field, so
    // disposing [controller] here would crash. It is left to the GC.
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

  /// `4G` → bytes for the grow-only comparison (QGUI-RESIZE-003).
  static int? _sizeToBytes(String v) {
    final m = RegExp(
      r'^(\d+(?:\.\d+)?)([KMGT])$',
      caseSensitive: false,
    ).firstMatch(v.trim());
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    const mult = {'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30, 'T': 1 << 40};
    return (n * mult[m.group(2)!.toUpperCase()]!).round();
  }

  void _showProcessOutput(List<ProcResult> results) {
    final output = results
        .map((r) => '${r.stdout}${r.stderr}')
        .where((s) => s.trim().isNotEmpty)
        .join('\n')
        .trim();
    final anyFailed = results.any((r) => r.exitCode != 0);
    if (output.isEmpty && !anyFailed) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) {
        // stdout and stderr are labelled channels — not colour-coded
        // hints — and the exit code is explicit (QGUI-OUTPUT-001/002).
        const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
        return QDialog(
          title: context.t('Command output'),
          width: 640,
          actions: [
            if (output.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(context.t('Copy')),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: output));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t('Copied'))),
                    );
                  }
                },
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('Dismiss')),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in results) ...[
                Text(
                  r.exitCode == 0
                      ? context.t('Exit code: 0 (success)')
                      : context.t(
                          'Exit code: {0} (failed)',
                          args: ['${r.exitCode}'],
                        ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: r.exitCode == 0
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                if ('${r.stdout}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.t('Standard output'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText('${r.stdout}'.trim(), style: mono),
                ],
                if ('${r.stderr}'.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.t('Standard error'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  SelectableText('${r.stderr}'.trim(), style: mono),
                ],
              ],
              if (output.isEmpty)
                Text(context.t('The command produced no output.')),
            ],
          ),
        );
      },
    );
  }
}
