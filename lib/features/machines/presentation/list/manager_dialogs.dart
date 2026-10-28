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
    required this.onChanged,
  });
  final VirtualizationBackend backend;
  final String vm;
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
                          trailing: TextButton(
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
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild so the action buttons enable/disable as fields change —
    // without a listener they stay disabled forever.
    _usbCtrl.addListener(() => setState(() {}));
    _diskCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _usbCtrl.dispose();
    _diskCtrl.dispose();
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
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy || _usbCtrl.text.trim().isEmpty
            ? null
            : () => _run(
                () => widget.backend.hotplugUsb(
                  widget.confPath,
                  _usbCtrl.text.trim(),
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
