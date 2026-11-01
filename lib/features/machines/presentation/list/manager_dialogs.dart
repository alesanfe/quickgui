part of 'manager.dart';

/// Dialog listing the backend trash (`--trash-list`) with per-VM
/// restore via `--trash-restore`.
class _TrashDialog extends StatefulWidget {
  const _TrashDialog({required this.backend, required this.onRestored});
  final VirtualizationBackend backend;
  final VoidCallback onRestored;

  @override
  State<_TrashDialog> createState() => _TrashDialogState();
}

class _TrashDialogState extends State<_TrashDialog> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.backend.listTrash();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _restore(String vm) async {
    try {
      await widget.backend.restoreFromTrash(vm);
      widget.onRestored();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Empty trash?')),
        content: Text(
          context.t(
            'All machines in the trash will be deleted permanently. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('Empty trash')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.backend.emptyTrash();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('Trash')),
    content: SizedBox(
      width: 420,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Text('${context.t('Error')}: $_error')
          : _items.isEmpty
          ? Text(context.t('The trash is empty.'))
          : ListView(
              shrinkWrap: true,
              children: [
                for (final item in _items)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.restore),
                    title: Text('${item['name'] ?? item['vm'] ?? '?'}'),
                    subtitle: item['deletedAt'] != null
                        ? Text('${item['deletedAt']}')
                        : null,
                    trailing: TextButton(
                      onPressed: () =>
                          _restore('${item['name'] ?? item['vm']}'),
                      child: Text(context.t('Restore')),
                    ),
                  ),
              ],
            ),
    ),
    actions: [
      if (_items.isNotEmpty)
        TextButton.icon(
          onPressed: _emptyTrash,
          icon: const Icon(Icons.delete_forever),
          label: Text(context.t('Empty trash')),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('Close')),
      ),
    ],
  );
}

/// Verified-archive backups for a VM (`--backup-list` / `--backup` /
/// `--backup-restore` / `--backup-prune`).
class _BackupsDialog extends StatefulWidget {
  const _BackupsDialog({
    required this.backend,
    required this.vm,
    required this.confPath,
    required this.onChanged,
  });
  final VirtualizationBackend backend;
  final String vm;
  final String confPath;
  final VoidCallback onChanged;

  @override
  State<_BackupsDialog> createState() => _BackupsDialogState();
}

class _BackupsDialogState extends State<_BackupsDialog> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.backend.listBackups(widget.vm);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('Backups for {0}', args: [widget.vm])),
    content: SizedBox(
      width: 460,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) Text('${context.t('Error')}: $_error'),
                if (_items.isEmpty)
                  Text(context.t('No backups for this machine.'))
                else
                  ListView(
                    shrinkWrap: true,
                    children: [
                      for (final b in _items)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.archive),
                          title: Text(
                            '${b['file'] ?? b['name'] ?? '?'}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          subtitle: b['size'] != null
                              ? Text('${b['size']}')
                              : null,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => widget.backend.verifyBackup(
                                          widget.vm,
                                          '${b['file'] ?? b['name']}',
                                        ),
                                      ),
                                child: Text(context.t('Verify')),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(
                                        () => widget.backend.restoreBackup(
                                          widget.vm,
                                          '${b['file'] ?? b['name']}',
                                        ),
                                      ),
                                child: Text(context.t('Restore')),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
    ),
    actions: [
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() => widget.backend.createBackup(widget.vm)),
        icon: const Icon(Icons.add),
        label: Text(context.t('Create backup')),
      ),
      TextButton.icon(
        onPressed: _busy
            ? null
            : () => _run(() => widget.backend.pruneBackups(widget.vm)),
        icon: const Icon(Icons.delete_sweep),
        label: Text(context.t('Prune old')),
      ),
      PopupMenuButton<String>(
        enabled: !_busy,
        icon: const Icon(Icons.more_vert),
        tooltip: context.t('Incremental backups'),
        onSelected: (verb) => _run(() async {
          final r = await runVmActionOrLegacy(widget.backend, verb, [
            '--vm',
            widget.confPath,
            '--$verb',
          ]);
          if (!context.mounted) return;
          showProcessOutputDialog(context, [r]);
        }),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'backup-incr',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.add_task),
              title: Text(context.t('Create incremental')),
              subtitle: Text(context.t('Requires a running VM')),
            ),
          ),
          PopupMenuItem(
            value: 'backup-incr-list',
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.list_alt),
              title: Text(context.t('List increments')),
            ),
          ),
        ],
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('Close')),
      ),
    ],
  );
}

/// Hot-plug dialog (`--hotplug-usb` / `--hotplug-disk` /
/// `--disk-compact`) — only meaningful while the VM runs.
class _HotplugDialog extends StatefulWidget {
  const _HotplugDialog({
    required this.backend,
    required this.vm,
    required this.confPath,
  });
  final VirtualizationBackend backend;
  final String vm;
  final String confPath;

  @override
  State<_HotplugDialog> createState() => _HotplugDialogState();
}

class _HotplugDialogState extends State<_HotplugDialog> {
  final _usbCtrl = TextEditingController();
  final _diskCtrl = TextEditingController();
  final _unplugCtrl = TextEditingController();
  bool _busy = false;
  bool _persist = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild so the action buttons enable/disable as fields change —
    // without a listener they stay disabled forever.
    _usbCtrl.addListener(() => setState(() {}));
    _diskCtrl.addListener(() => setState(() {}));
    _unplugCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usbCtrl.dispose();
    _diskCtrl.dispose();
    _unplugCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('Hotplug — {0}', args: [widget.vm])),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${context.t('Error')}: $_error'),
            ),
          TextField(
            controller: _usbCtrl,
            decoration: InputDecoration(
              labelText: context.t('USB device (id or path)'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _diskCtrl,
            decoration: InputDecoration(
              labelText: context.t('Disk image path'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _unplugCtrl,
            decoration: InputDecoration(
              labelText: context.t('Detach device id'),
              isDense: true,
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('Persist to config')),
            subtitle: Text(
              context.t(
                'Records the attached device in the VM configuration (--persist).',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _persist,
            onChanged: (v) => setState(() => _persist = v ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy || _unplugCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.hotunplug(
                  widget.confPath,
                  _unplugCtrl.text.trim(),
                ),
              ),
        child: Text(context.t('Detach')),
      ),
      TextButton(
        onPressed: _busy || _usbCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.hotplugUsb(
                  widget.confPath,
                  _usbCtrl.text.trim(),
                  persist: _persist,
                ),
              ),
        child: Text(context.t('Attach USB')),
      ),
      TextButton(
        onPressed: _busy || _diskCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.hotplugDisk(
                  widget.confPath,
                  _diskCtrl.text.trim(),
                  persist: _persist,
                ),
              ),
        child: Text(context.t('Attach disk')),
      ),
      TextButton(
        onPressed: _busy
            ? null
            : () => _run(() => widget.backend.diskCompact(widget.confPath)),
        child: Text(context.t('Compact disk')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('Close')),
      ),
    ],
  );
}

/// Move (`--move <dir>`) or rename (`--rename <name>`) the VM — the
/// backend performs the filesystem surgery safely.
class _MoveRenameDialog extends StatefulWidget {
  const _MoveRenameDialog({
    required this.backend,
    required this.vm,
    required this.confPath,
    required this.onChanged,
  });
  final VirtualizationBackend backend;
  final String vm;
  final String confPath;
  final VoidCallback onChanged;

  @override
  State<_MoveRenameDialog> createState() => _MoveRenameDialogState();
}

class _MoveRenameDialogState extends State<_MoveRenameDialog> {
  final _dirCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dirCtrl.addListener(() => setState(() {}));
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('Move / Rename — {0}', args: [widget.vm])),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${context.t('Error')}: $_error'),
            ),
          TextField(
            controller: _dirCtrl,
            decoration: InputDecoration(
              labelText: context.t('Move to directory'),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: context.t('Rename to'),
              isDense: true,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy || _dirCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.moveVm(
                  widget.confPath,
                  _dirCtrl.text.trim(),
                ),
              ),
        child: Text(context.t('Move')),
      ),
      TextButton(
        onPressed: _busy || _nameCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.renameVm(
                  widget.confPath,
                  _nameCtrl.text.trim(),
                ),
              ),
        child: Text(context.t('Rename')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('Close')),
      ),
    ],
  );
}

/// QEMU Guest Agent console (`quickemu guest …`): liveness, guest OS
/// facts, in-guest command execution, file transfer, filesystem
/// freeze and graceful power actions. Verbs that predate the backend
/// surface as "unsupported" rather than errors.
class _GuestAgentDialog extends StatefulWidget {
  const _GuestAgentDialog({
    required this.backend,
    required this.vm,
    required this.confPath,
  });
  final VirtualizationBackend backend;
  final String vm;
  final String confPath;

  @override
  State<_GuestAgentDialog> createState() => _GuestAgentDialogState();
}

class _GuestAgentDialogState extends State<_GuestAgentDialog> {
  final _cmdCtrl = TextEditingController();
  final _localCtrl = TextEditingController();
  final _remoteCtrl = TextEditingController();
  bool _push = true;
  bool _busy = false;
  String? _output;

  @override
  void initState() {
    super.initState();
    _cmdCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _localCtrl.dispose();
    _remoteCtrl.dispose();
    super.dispose();
  }

  String _unsupported() => context.t(
    'Unsupported — this Quickemu does not implement the guest verbs.',
  );

  /// Runs a read verb and renders the returned map (or the
  /// unsupported/null result) into the output area.
  Future<void> _report(Future<Map<String, dynamic>?> Function() call) async {
    setState(() {
      _busy = true;
      _output = null;
    });
    try {
      final data = await call();
      if (!mounted) return;
      setState(
        () => _output = data == null
            ? _unsupported()
            : data.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
      );
    } on AppFailure catch (e) {
      if (mounted) setState(() => _output = e.userMessage);
    } catch (e) {
      if (mounted) setState(() => _output = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exec() async {
    setState(() {
      _busy = true;
      _output = null;
    });
    try {
      final data = await widget.backend.guestExec(widget.confPath, [
        _cmdCtrl.text.trim(),
      ]);
      if (!mounted) return;
      if (data == null) {
        setState(() => _output = _unsupported());
        return;
      }
      final buf = StringBuffer('exit ${data['exitCode']}\n');
      if ('${data['stdout']}'.isNotEmpty) buf.write('${data['stdout']}');
      if ('${data['stderr']}'.isNotEmpty) buf.write('${data['stderr']}');
      if (data['truncated'] == true) buf.write('…\n(output truncated)');
      setState(() => _output = buf.toString().trim());
    } on AppFailure catch (e) {
      if (mounted) setState(() => _output = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _power(String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Guest {0}', args: [action])),
        content: Text(
          context.t(
            'Ask the guest to {0} via the agent (ACPI fallback when absent)?',
            args: [action],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('Confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _output = null;
    });
    try {
      final r = await widget.backend.guestPower(widget.confPath, action);
      if (!mounted) return;
      setState(
        () => _output = r.exitCode == 0
            ? '${r.stdout}'.trim()
            : '${context.t('Error')}: ${r.stderr}${r.stdout}'.trim(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('Guest agent — {0}', args: [widget.vm])),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _report(
                          () => widget.backend.guestPing(widget.confPath),
                        ),
                  child: Text(context.t('Ping')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _report(
                          () => widget.backend.guestInfo(widget.confPath),
                        ),
                  child: Text(context.t('Info')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _report(
                          () => widget.backend.guestFsFreeze(
                            widget.confPath,
                            'status',
                          ),
                        ),
                  child: Text(context.t('Freeze status')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _report(
                          () => widget.backend.guestFsFreeze(
                            widget.confPath,
                            'freeze',
                          ),
                        ),
                  child: Text(context.t('Freeze')),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _report(
                          () => widget.backend.guestFsFreeze(
                            widget.confPath,
                            'thaw',
                          ),
                        ),
                  child: Text(context.t('Thaw')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cmdCtrl,
              decoration: InputDecoration(
                labelText: context.t('Command to run in the guest'),
                isDense: true,
              ),
              onSubmitted: (_) =>
                  _cmdCtrl.text.trim().isNotEmpty ? _exec() : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: Text(context.t('Push (to guest)')),
                  selected: _push,
                  onSelected: (_) => setState(() => _push = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(context.t('Pull (from guest)')),
                  selected: !_push,
                  onSelected: (_) => setState(() => _push = false),
                ),
              ],
            ),
            TextField(
              controller: _localCtrl,
              decoration: InputDecoration(
                labelText: context.t('Local path'),
                isDense: true,
              ),
            ),
            TextField(
              controller: _remoteCtrl,
              decoration: InputDecoration(
                labelText: context.t('Guest path'),
                isDense: true,
              ),
            ),
            if (_output != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _output!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed:
            _busy ||
                _localCtrl.text.trim().isEmpty ||
                _remoteCtrl.text.trim().isEmpty
            ? null
            : () => _report(
                () => widget.backend.guestTransfer(
                  widget.confPath,
                  push: _push,
                  localPath: _localCtrl.text.trim(),
                  guestPath: _remoteCtrl.text.trim(),
                ),
              ),
        child: Text(context.t('Transfer')),
      ),
      TextButton(
        onPressed: _busy || _cmdCtrl.text.trim().isEmpty ? null : _exec,
        child: Text(context.t('Run')),
      ),
      TextButton(
        onPressed: _busy ? null : () => _power('shutdown'),
        child: Text(context.t('Shutdown')),
      ),
      TextButton(
        onPressed: _busy ? null : () => _power('reboot'),
        child: Text(context.t('Reboot')),
      ),
      TextButton(
        onPressed: _busy ? null : () => _power('halt'),
        child: Text(context.t('Halt')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.t('Close')),
      ),
    ],
  );
}
