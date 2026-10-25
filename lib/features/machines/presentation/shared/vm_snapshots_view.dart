import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';
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
  VirtualizationBackend get _backend => ref.read(backendProvider);
  List<Map<String, dynamic>>? _snapshots;
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
      if (!mounted) return;
      setState(() {
        _snapshots = snapshots;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  final _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _run(String action, [String tag = '']) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final results = await ref
          .read(activityProvider.notifier)
          .run(
            OperationKind.snapshot,
            widget.vm,
            () => _backend.runAction([
              '--vm',
              widget.confPath,
              '--snapshot',
              action,
              if (tag.isNotEmpty) tag,
            ]),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _tagController,
            decoration: InputDecoration(
              labelText: context.t('Snapshot tag'),
              hintText: context.t('Tag for the new or existing snapshot'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () => _run('info'),
                child: Text(context.t('Info')),
              ),
              TextButton(
                onPressed: tag.isEmpty ? null : () => _run('create', tag),
                child: Text(context.t('Create')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () => _confirmAndRun('apply', tag),
                child: Text(context.t('Apply')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () => _confirmAndRun('delete', tag),
                child: Text(context.t('Delete')),
              ),
              const Spacer(),
              IconButton(
                tooltip: context.t('Refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
        ),
        Text(
          context.t('Existing snapshots'),
          style: Theme.of(context).textTheme.titleSmall,
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
                      // Tapping a snapshot fills the tag field so the
                      // action row applies to it.
                      onTap: () =>
                          setState(() => _tagController.text = '${s['name']}'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Legacy dialog wrapper used from the machine row menu.
Future<void> showSnapshotsDialog(
  BuildContext context, {
  required String vm,
  required String confPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('Snapshots {0}', args: [vm])),
      content: SizedBox(
        width: 560,
        height: 420,
        child: VmSnapshotsView(vm: vm, confPath: confPath),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
      ],
    ),
  );
}
