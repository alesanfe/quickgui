import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/features/machines/presentation/details/vm_connection_view.dart';
import 'package:quickgui/features/machines/presentation/details/vm_settings_page.dart';
import 'package:quickgui/features/machines/presentation/shared/stop_vm_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';

import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/activity/presentation/operation_tile.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_snapshots_view.dart';

/// Full-screen page for a single VM: overview (conf values), snapshots
/// and per-VM activity history. Reached via `/machines/:name`.
class VmPage extends ConsumerStatefulWidget {
  const VmPage({required this.vmName, super.key});

  final String vmName;

  @override
  ConsumerState<VmPage> createState() => _VmPageState();
}

class _VmPageState extends ConsumerState<VmPage> {
  String get _confPath => '${widget.vmName}.conf';
  Map<String, dynamic> _status = const {};
  List<Map<String, dynamic>> _ops = const [];
  bool _busy = false;
  String _logFilter = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final backend = ref.read(backendProvider);
      final status = await backend.inspectVirtualMachine(widget.vmName);
      final ops = await backend.listOperations(widget.vmName);
      if (mounted) {
        setState(() {
          _status = status;
          _ops = ops;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = {'state': 'unknown', 'error': '$error'});
      }
    }
  }

  Future<void> _run(List<String> arguments, {bool confirm = false}) async {
    if (_busy) return;
    if (confirm) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Confirm machine action')),
          content: Text(
            context.t('This action can discard unsaved guest state. Continue?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Continue')),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final backend = ref.read(trackedBackendProvider);
      final args = ['--vm', _confPath, ...arguments];
      // Logical command name for the structured contract: the first
      // quickemu flag after --vm (e.g. --reset -> 'reset').
      final command = arguments
          .firstWhere((a) => a.startsWith('--'), orElse: () => 'command')
          .replaceFirst(RegExp('^--'), '');
      final result = await runVmActionOrLegacy(backend, command, args);
      if (mounted &&
          (result.exitCode != 0 ||
              '${result.stdout}${result.stderr}'.trim().isNotEmpty)) {
        showProcessOutputDialog(context, [result]);
      }
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The real backend emits `allowedOps` in `vm.status` — when present,
  /// it is the authoritative gate for each action; when absent (legacy
  /// backend) the current state-based gate decides.
  bool _allowed(String op) {
    final ops = _status['allowedOps'];
    return ops is! List || ops.map((e) => '$e').contains(op);
  }

  Widget _actions() {
    final state = '${_status['state'] ?? 'unknown'}';
    final active = state == 'running' || state == 'paused';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            avatar: Icon(
              active ? Icons.play_circle : Icons.stop_circle_outlined,
              size: 18,
            ),
            label: Text(state),
          ),
          FilledButton.icon(
            onPressed: _busy || active || !_allowed('start')
                ? null
                : () => _run([]),
            icon: const Icon(Icons.play_arrow),
            label: Text(context.t('Start')),
          ),
          OutlinedButton.icon(
            onPressed: _busy || !active || !_allowed('stop')
                ? null
                : () async {
                    await showStopVmDialog(
                      context,
                      backend: ref.read(trackedBackendProvider),
                      vm: widget.vmName,
                      confPath: _confPath,
                    );
                    await _refresh();
                  },
            icon: const Icon(Icons.stop),
            label: Text(context.t('Shut down')),
          ),
          OutlinedButton(
            onPressed: _busy || !active || !_allowed('pause')
                ? null
                : () =>
                      _run([if (state == 'paused') '--resume' else '--pause']),
            child: Text(
              state == 'paused' ? context.t('Resume') : context.t('Pause'),
            ),
          ),
          OutlinedButton(
            onPressed: _busy || !active || !_allowed('reset')
                ? null
                : () => _run(['--monitor-cmd', 'system_reset'], confirm: true),
            child: Text(context.t('Reset')),
          ),
          IconButton(
            tooltip: context.t('Screenshot'),
            onPressed: _busy || !active || !_allowed('screenshot')
                ? null
                : () => _run(['--screenshot']),
            icon: const Icon(Icons.screenshot_monitor),
          ),
          IconButton(
            tooltip: context.t('Send Ctrl+Alt+Del'),
            onPressed: _busy || !active || !_allowed('send-keys')
                ? null
                : () => _run(['--send-keys', 'ctrl-alt-delete']),
            icon: const Icon(Icons.keyboard),
          ),
          IconButton(
            tooltip: context.t('Refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (_busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  static const _keys = [
    'guest_os',
    'ram',
    'cpu_cores',
    'disk_size',
    'boot',
    'network',
    'bridge',
    'macaddr',
    'secureboot',
    'tpm',
    'display',
    'viewer',
    'sound',
    'public_dir',
    'usb_devices',
    'port_forwards',
    'iso',
    'img',
    'fixed_iso',
    'floppy',
    'disk',
  ];

  @override
  Widget build(BuildContext context) {
    final exists =
        p.basename(widget.vmName) == widget.vmName &&
        !widget.vmName.contains(r'\') &&
        File(_confPath).existsSync();
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.vmName),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: context.t('Back'),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/machines');
              }
            },
          ),
          actions: [
            IconButton(
              tooltip: context.t('VM settings'),
              icon: const Icon(Icons.settings),
              onPressed: () => context.push(
                '/machines/${Uri.encodeComponent(widget.vmName)}/settings',
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.t('Overview')),
              Tab(text: context.t('Console')),
              Tab(text: context.t('Hardware')),
              Tab(text: context.t('Disks')),
              Tab(text: context.t('Network')),
              Tab(text: context.t('Snapshots')),
              Tab(text: context.t('Operations')),
              Tab(text: context.t('Logs')),
            ],
          ),
        ),
        body: !exists
            ? Center(
                child: Text(
                  context.t(
                    'Virtual machine not found: {0}',
                    args: [widget.vmName],
                  ),
                ),
              )
            : Column(
                children: [
                  _actions(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildOverview(),
                        VmConnectionView(
                          vm: widget.vmName,
                          confPath: _confPath,
                        ),
                        VmSettingsPage(vmName: widget.vmName),
                        _buildDisks(),
                        VmSettingsPage(
                          vmName: widget.vmName,
                          section: context.t('Network'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: VmSnapshotsView(
                            vm: widget.vmName,
                            confPath: _confPath,
                          ),
                        ),
                        _buildOps(),
                        _buildActivity(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildOverview() {
    final store = ref.read(vmConfigStoreProvider);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final key in _keys)
          Builder(
            builder: (context) {
              final value = store.read(_confPath, key);
              if (value == null || value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(
                        key,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: SelectableText(value)),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDisks() {
    final store = ref.read(vmConfigStoreProvider);
    final disk = store.read(_confPath, 'disk_img');
    final file = disk == null || disk.isEmpty ? null : File(disk);
    final stopped = _status['state'] == 'stopped';
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          context.t('Storage'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.storage),
            title: Text(disk ?? context.t('No disk configured')),
            subtitle: Text(
              file != null && file.existsSync()
                  ? context.t(
                      'Image file size: {0}. Virtual capacity is configured separately.',
                      args: [formatBytes(file.lengthSync())],
                    )
                  : context.t(
                      'The disk has not been created yet or is unavailable.',
                    ),
            ),
          ),
        ),
        for (final key in ['iso', 'fixed_iso', 'img', 'floppy'])
          if (store.read(_confPath, key) case final value?)
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: Text(key),
              subtitle: SelectableText(value),
            ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: stopped && !_busy ? _resize : null,
              icon: const Icon(Icons.expand),
              label: Text(context.t('Expand disk')),
            ),
            OutlinedButton.icon(
              onPressed: stopped && !_busy
                  ? () => _run(['--disk-compact'], confirm: true)
                  : null,
              icon: const Icon(Icons.compress),
              label: Text(context.t('Compact disk')),
            ),
            OutlinedButton.icon(
              onPressed: () => _run(['--doctor']),
              icon: const Icon(Icons.health_and_safety),
              label: Text(context.t('Check VM')),
            ),
            OutlinedButton.icon(
              onPressed: stopped && !_busy ? _export : null,
              icon: const Icon(Icons.archive_outlined),
              label: Text(context.t('Export / full backup')),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(trackedBackendProvider).openVmFolder(widget.vmName),
              icon: const Icon(Icons.folder_open),
              label: Text(context.t('Open VM folder')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          context.t(
            'Disk maintenance and a consistent full backup require a stopped machine. Snapshots are not independent backups.',
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            title: Text(context.t('Configure storage and removable media')),
            subtitle: Text(
              context.t(
                'Attach ISO and recovery images in Hardware → Boot. Additional disk topologies depend on the installed Quickemu version.',
              ),
            ),
            trailing: const Icon(Icons.info_outline),
          ),
        ),
      ],
    );
  }

  Future<void> _resize() async {
    final controller = TextEditingController();
    final size = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Expand disk')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.t('New capacity (for example 128G)'),
            helperText: context.t(
              'Use a value larger than the existing capacity. Back up important data first.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim().toUpperCase();
              if (RegExp(r'^[1-9]\d*[MGT]$').hasMatch(value)) {
                Navigator.pop(context, value);
              }
            },
            child: Text(context.t('Continue')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (size != null && mounted) {
      await _run(['--disk-resize', size], confirm: true);
    }
  }

  Future<void> _export() async {
    final archive = File('${widget.vmName}.tar.gz');
    if (archive.existsSync()) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Replace existing archive?')),
          content: Text(archive.path),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Replace')),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }
    try {
      final result = await ref
          .read(trackedBackendProvider)
          .exportVm(widget.vmName);
      if (mounted) showProcessOutputDialog(context, [result]);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  /// Backend async-operation registry for this VM (`--op-list`) —
  /// distinct from local Activity: these ops live in quickemu itself
  /// and can still be running after the app restarted.
  Widget _buildOps() {
    if (_ops.isEmpty) {
      return Center(
        child: Text(context.t('No backend operations for this machine.')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final op in _ops)
          Card(
            child: ListTile(
              leading: Icon(switch ('${op['state']}') {
                'completed' || 'succeeded' => Icons.check_circle,
                'failed' => Icons.error_outline,
                'cancelled' => Icons.cancel_outlined,
                _ => Icons.autorenew,
              }),
              title: Text('${op['type'] ?? op['operationId']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${op['state']} · ${op['operationId']}'),
                  if (op['progress'] is num && op['progress'] != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: ((op['progress'] as num) / 100).clamp(0.0, 1.0),
                      ),
                    ),
                ],
              ),
              trailing: op['state'] == 'running' || op['state'] == 'queued'
                  ? IconButton(
                      tooltip: context.t('Cancel operation'),
                      icon: const Icon(Icons.stop_circle_outlined),
                      onPressed: () => _cancelOp('${op['operationId']}'),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _cancelOp(String operationId) async {
    try {
      await ref
          .read(backendProvider)
          .cancelOperation(widget.vmName, operationId);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Widget _buildActivity() {
    final ops = ref.watch(activityForProvider(widget.vmName));
    if (ops.isEmpty) {
      return Center(
        child: Text(context.t('No activity recorded for this machine.')),
      );
    }
    final filtered = ops
        .where(
          (entry) => '${entry.kind.name} ${entry.message} ${entry.status.name}'
              .toLowerCase()
              .contains(_logFilter.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.t('Search logs'),
                  ),
                  onChanged: (value) => setState(() => _logFilter = value),
                ),
              ),
              IconButton(
                tooltip: context.t('Copy report'),
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text: filtered
                        .map(
                          (entry) =>
                              '${entry.completedAt.toIso8601String()} ${entry.kind.name} ${entry.status.name}\n${entry.message}',
                        )
                        .join('\n\n'),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: filtered.length,
            itemBuilder: (context, i) => HistoryEntryTile(entry: filtered[i]),
          ),
        ),
      ],
    );
  }
}
