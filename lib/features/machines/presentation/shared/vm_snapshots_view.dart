import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';
import 'package:quickgui/shared/widgets/disabled_reason.dart';
import 'package:quickgui/shared/widgets/scroll_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';

/// 'YYYY-MM-DD HH:MM' from the contract's unix timestamp; '' when
/// the backend did not provide one.
String formatSnapshotDate(dynamic date) {
  if (date is! num) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch((date * 1000).round())
      .toLocal();
  final s = dt.toString();
  return s.length >= 16 ? s.substring(0, 16) : s;
}

/// Snapshot management panel: lists existing snapshots with date and
/// on-disk size, and exposes create/apply/delete/info. Used as a tab in
/// the VM page and wrapped in a dialog by [showSnapshotsDialog].
class VmSnapshotsView extends ConsumerStatefulWidget {
  const VmSnapshotsView({required this.vm, required this.confPath, super.key});

  final String vm;
  final String confPath;

  @override
  ConsumerState<VmSnapshotsView> createState() => _VmSnapshotsViewState();
}

class _VmSnapshotsViewState extends ConsumerState<VmSnapshotsView> {
  VirtualizationBackend get _backend => ref.read(trackedBackendProvider);
  List<Map<String, dynamic>>? _snapshots;
  List<Map<String, dynamic>> _tree = const [];
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshots = await _backend.listSnapshots(widget.confPath);
      final tree = await _backend.snapshotTree(widget.confPath);
      if (!mounted) return;
      setState(() {
        _snapshots = snapshots;
        _tree = tree;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  final _tagController = TextEditingController();
  final _descController = TextEditingController();
  bool _withMemory = false;
  bool _quiesce = false;

  @override
  void dispose() {
    _tagController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _run(
    String action, [
    String tag = '',
    List<String>? extra,
  ]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final results = await ref.read(activityProvider.notifier).run(
        OperationKind.snapshot,
        widget.vm,
        (op) {
          final args = [
            '--vm',
            widget.confPath,
            '--snapshot',
            action,
            if (tag.isNotEmpty) tag,
            ...?extra,
          ];
          return runVmActionOrLegacy(_backend, 'snapshot-$action', args);
        },
      );
      if (!mounted) return;
      showProcessOutputDialog(context, [results]);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `--snapshot-policy <verb>` — retention engine status / manual
  /// run. `units` would install systemd timers, so it stays out.
  Future<void> _policy(String verb) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await runVmActionOrLegacy(_backend, 'snapshot-policy', [
        '--vm',
        widget.confPath,
        '--snapshot-policy',
        verb,
      ]);
      if (!mounted) return;
      showProcessOutputDialog(context, [r]);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Extra flags for `snapshot create` — `--memory` takes a live
  /// vmstate snapshot, `--quiesce` freezes the guest fs first and
  /// `--snapshot-desc` registers a description alongside it.
  List<String> get _createExtra => [
    if (_withMemory) '--memory',
    if (_withMemory && _quiesce) '--quiesce',
    if (_withMemory && _descController.text.trim().isNotEmpty) ...[
      '--snapshot-desc',
      _descController.text.trim(),
    ],
  ];

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _backend.verifySnapshots(widget.confPath);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Snapshots verified'))));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRun(String action, String tag) async {
    // Applying a snapshot replaces the current disk state and deleting
    // removes it permanently — both need an explicit confirmation.
    if (action == 'apply' || action == 'delete') {
      final isDelete = action == 'delete';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            isDelete
                ? context.t('Delete snapshot {0}', args: [tag])
                : context.t('Apply snapshot {0}', args: [tag]),
          ),
          content: Text(
            isDelete
                ? context.t(
                    'The snapshot {0} of {1} will be permanently deleted. This cannot be undone.',
                    args: [tag, widget.vm],
                  )
                : context.t(
                    'The current state of {0} will be replaced by the snapshot {1}. This cannot be undone.',
                    args: [widget.vm, tag],
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
    await _run(action, tag);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('${context.t('Error')}: $_error'));
    }
    final snapshots = _snapshots;
    final tag = _tagController.text.trim();
    return Column(
      // mainAxisSize.min lets the dialog shrink to content when the
      // snapshot list is empty; when rows exist the Expanded below
      // still claims the bounded height.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tree.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('Snapshot tree'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final node in _tree)
                  Padding(
                    padding: EdgeInsets.only(
                      left: 12.0 * (node['depth'] as int? ?? 0),
                      top: 2,
                    ),
                    child: Text(
                      '${node['depth'] != null && (node['depth'] as int) > 0 ? '└─ ' : ''}${node['name'] ?? node['tag'] ?? node}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Divider(),
              ],
            ),
          ),
        // Global create section (QGUI-SNAP-001): the tag field and
        // its options belong to "create a new snapshot" — per-snapshot
        // actions live on each list card instead.
        Text(
          context.t('New snapshot'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _tagController,
            decoration: InputDecoration(
              labelText: context.t('Snapshot tag'),
              hintText: context.t('Name for the new snapshot'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.t('Include memory')),
                subtitle: Text(context.t('Captures the running state')),
                value: _withMemory,
                onChanged: (v) => setState(() => _withMemory = v ?? false),
              ),
            ),
            Expanded(
              // Quiesce explained inline rather than left ambiguous
              // (QGUI-SNAP-004): the dependency on Include memory and
              // the guest-agent requirement are visible text.
              child: CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(context.t('Quiesce filesystem')),
                subtitle: Text(
                  _withMemory
                      ? context.t(
                          'Pauses guest writes for a consistent snapshot (needs qemu-guest-agent)',
                        )
                      : context.t('Enable Include memory first'),
                ),
                value: _quiesce,
                onChanged: _withMemory
                    ? (v) => setState(() => _quiesce = v ?? false)
                    : null,
              ),
            ),
          ],
        ),
        if (_withMemory)
          TextField(
            controller: _descController,
            decoration: InputDecoration(
              labelText: context.t('Description'),
              isDense: true,
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: tag.isEmpty
                // Disabled with a reason, not a bare disabled button
                // (QGUI-UX-002).
                ? DisabledReason(
                    reason: context.t('Enter a snapshot tag first'),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      onPressed: null,
                      label: Text(context.t('Create snapshot')),
                    ),
                  )
                : FilledButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    onPressed: _busy
                        ? null
                        : () => _run('create', tag, _createExtra),
                    label: Text(context.t('Create snapshot')),
                  ),
          ),
        ),
        // Global actions on the list header; uncommon ones live under
        // More so a single primary action stays obvious (SNAP-002/003).
        Row(
          children: [
            Expanded(
              child: Text(
                context.t('Existing snapshots'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: context.t('Refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _load,
            ),
            PopupMenuButton<String>(
              tooltip: context.t('More snapshot actions'),
              icon: const Icon(Icons.more_vert),
              enabled: !_busy,
              onSelected: (v) => switch (v) {
                'info' => _run('info'),
                'verify' => _verify(),
                'policy-status' => _policy('status'),
                'policy-run' => _policy('run'),
                _ => null,
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'info',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline),
                    title: Text(context.t('Snapshot backend info')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'verify',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.verified_outlined),
                    title: Text(context.t('Verify all snapshots')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'policy-status',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.policy_outlined),
                    title: Text(context.t('Snapshot policy status')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'policy-run',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.playlist_play),
                    title: Text(context.t('Run retention policy now')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (snapshots == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (snapshots.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                context.t(
                  'No snapshots yet. Snapshots capture the disk state so you can roll back later.',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              children: [
                for (final s in snapshots)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text('${s['name']}'),
                      subtitle: Text(
                        [
                          formatSnapshotDate(s['date']),
                          if (s['vm-state-size'] is num &&
                              (s['vm-state-size'] as num) > 0)
                            formatBytes((s['vm-state-size'] as num).toInt()),
                        ].where((e) => e.isNotEmpty).join(' · '),
                      ),
                      // Per-snapshot actions live on the row — no more
                      // "type the tag, then press Apply" (QGUI-SNAP-001).
                      trailing: _busy
                          ? null
                          : Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _confirmAndRun('apply', '${s['name']}'),
                                  child: Text(context.t('Apply')),
                                ),
                                IconButton(
                                  tooltip: context.t('Delete snapshot'),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  onPressed: () =>
                                      _confirmAndRun('delete', '${s['name']}'),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Legacy dialog wrapper used from the machine row menu — the shared
/// [QDialog] shell keeps header and Close always visible (QGUI-UX-003).
Future<void> showSnapshotsDialog(
  BuildContext context, {
  required String vm,
  required String confPath,
}) {
  return QDialog.show<void>(
    context,
    title: context.t('Snapshots {0}', args: [vm]),
    width: 720,
    // The view scrolls internally via its own Expanded ListView; bound
    // its height so the dialog shell stays stable.
    child: SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.6).clamp(260.0, 560.0),
      child: VmSnapshotsView(vm: vm, confPath: confPath),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.t('Close')),
      ),
    ],
  );
}
