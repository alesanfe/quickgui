import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';

/// Activity centre: tabbed view of in-flight operations plus the
/// persisted history, filterable by kind and retryability.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

enum _StatusTab { running, succeeded, failed, cancelled, all }

class _ActivityPageState extends ConsumerState<ActivityPage> {
  _StatusTab _tab = _StatusTab.all;
  OperationKind? _kindFilter;
  bool _retryableOnly = false;

  bool _matchesTab(OperationHistoryEntry e) => switch (_tab) {
    _StatusTab.succeeded => e.status == OperationStatus.succeeded,
    _StatusTab.failed => e.status == OperationStatus.failed,
    _StatusTab.cancelled =>
      e.status == OperationStatus.cancelled ||
          e.status == OperationStatus.interrupted,
    _StatusTab.running => false,
    _StatusTab.all => true,
  };

  bool _matchesFilters(OperationHistoryEntry e) =>
      (_kindFilter == null || e.kind == _kindFilter) &&
      (!_retryableOnly || e.retryable);

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityProvider);
    final all = activity.history;
    final counts = <OperationStatus, int>{
      for (final s in OperationStatus.values)
        s: all.where((e) => e.status == s).length,
    };
    final interrupted = counts[OperationStatus.interrupted] ?? 0;
    final cancelledCount =
        (counts[OperationStatus.cancelled] ?? 0) + interrupted;
    final kinds = all.map((e) => e.kind).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    final filtered = [
      for (final e in all)
        if (_matchesTab(e) && _matchesFilters(e)) e,
    ];
    final visibleActive = [
      for (final op in activity.active)
        if (_kindFilter == null || op.kind == _kindFilter) op,
    ];

    final tabs = [
      (context.t('In progress'), activity.active.length),
      (context.t('Completed'), counts[OperationStatus.succeeded] ?? 0),
      (context.t('Failed'), counts[OperationStatus.failed] ?? 0),
      (context.t('Cancelled'), cancelledCount),
      (context.t('All'), all.length),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Activity')),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              tooltip: context.t('Clear history'),
              icon: const Icon(Icons.clear_all),
              onPressed: () =>
                  ref.read(activityProvider.notifier).clearHistory(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < tabs.length; i++)
                FilterChip(
                  selected: _tab == _StatusTab.values[i],
                  label: Text(
                    tabs[i].$2 > 0
                        ? '${tabs[i].$1} (${tabs[i].$2})'
                        : tabs[i].$1,
                  ),
                  onSelected: (_) =>
                      setState(() => _tab = _StatusTab.values[i]),
                ),
              const VerticalDivider(),
              if (kinds.length > 1)
                PopupMenuButton<OperationKind?>(
                  tooltip: context.t('Filter by type'),
                  onSelected: (k) => setState(() => _kindFilter = k),
                  itemBuilder: (context) => [
                    PopupMenuItem(child: Text(context.t('All types'))),
                    for (final k in kinds)
                      PopupMenuItem(
                        value: k,
                        child: Text(operationKindLabel(context, k)),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(
                      _kindFilter == null
                          ? context.t('Type')
                          : operationKindLabel(context, _kindFilter!),
                    ),
                  ),
                ),
              FilterChip(
                selected: _retryableOnly,
                label: Text(context.t('Retryable only')),
                onSelected: (v) => setState(() => _retryableOnly = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == _StatusTab.running || _tab == _StatusTab.all) ...[
            if (visibleActive.isNotEmpty)
              _SectionHeader(context.t('In progress')),
            for (final op in visibleActive) OperationTile(op: op),
            if (visibleActive.isNotEmpty) const SizedBox(height: 16),
          ],
          if (filtered.isNotEmpty || visibleActive.isNotEmpty)
            _SectionHeader(context.t('History')),
          if (filtered.isEmpty && visibleActive.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  _tab == _StatusTab.all && _kindFilter == null
                      ? context.t(
                          'No activity yet. Downloads and machine '
                          'operations will show up here.',
                        )
                      : context.t('No operations match the current filters.'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final e in filtered) _HistoryTile(entry: e),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Icon per operation kind.
IconData operationKindIcon(OperationKind kind) => switch (kind) {
  OperationKind.download => Icons.download,
  OperationKind.start => Icons.play_arrow,
  OperationKind.stop => Icons.stop,
  OperationKind.clone => Icons.content_copy,
  OperationKind.export => Icons.archive,
  OperationKind.verify => Icons.verified,
  OperationKind.resize => Icons.expand,
  OperationKind.snapshot => Icons.photo_camera,
  OperationKind.delete => Icons.delete,
  OperationKind.import => Icons.upload_file,
  OperationKind.convert => Icons.transform,
  OperationKind.restore => Icons.restore,
  OperationKind.command => Icons.terminal,
};

/// Title per operation kind.
String operationKindLabel(BuildContext context, OperationKind kind) =>
    switch (kind) {
      OperationKind.download => context.t('Download'),
      OperationKind.start => context.t('Start'),
      OperationKind.stop => context.t('Stop'),
      OperationKind.clone => context.t('Clone'),
      OperationKind.export => context.t('Export'),
      OperationKind.verify => context.t('Verify image'),
      OperationKind.resize => context.t('Resize disk'),
      OperationKind.snapshot => context.t('Snapshots'),
      OperationKind.delete => context.t('Delete'),
      OperationKind.import => context.t('Import'),
      OperationKind.convert => context.t('Convert'),
      OperationKind.restore => context.t('Restore'),
      OperationKind.command => context.t('Command'),
    };

class OperationTile extends ConsumerWidget {
  const OperationTile({required this.op, super.key});
  final AppOperation op;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = switch (op.state) {
      OperationRunning(:final progress?) => progress,
      OperationPaused(:final progress?) => progress,
      _ => null,
    };
    final subtitle = switch (op.state) {
      OperationRunning(:final progress?) => '${(progress * 100).toInt()}%',
      OperationRunning() => context.t('Running'),
      OperationQueued() => context.t('Queued'),
      OperationPaused() => context.t('Paused'),
      OperationCancelling() => context.t('Cancelling'),
      OperationValidating() => context.t('Validating'),
      OperationWaitingForConfirmation() => context.t(
        'Waiting for confirmation',
      ),
      _ => context.t('Running'),
    };
    return Card(
      child: ListTile(
        onTap: op.output.isEmpty
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(op.target),
                  content: SizedBox(
                    width: 720,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        op.output,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
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
              ),
        leading: Icon(operationKindIcon(op.kind)),
        title: Text('${operationKindLabel(context, op.kind)} — ${op.target}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            if (op.output.isNotEmpty)
              Text(
                op.output.trim().split('\n').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress),
          ],
        ),
        trailing: op.onCancel != null && !op.isTerminal
            ? IconButton(
                tooltip: context.t('Cancel'),
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => ref.read(activityProvider.notifier).cancel(op),
              )
            : null,
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final OperationHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, statusLabel) = switch (entry.status) {
      OperationStatus.succeeded => (
        Icons.check_circle_outline,
        Colors.green,
        context.t('Completed'),
      ),
      OperationStatus.failed => (
        Icons.error_outline,
        scheme.error,
        entry.retryable ? context.t('Failed (retryable)') : context.t('Failed'),
      ),
      OperationStatus.cancelled => (
        Icons.cancel_outlined,
        scheme.onSurfaceVariant,
        context.t('Cancelled'),
      ),
      OperationStatus.interrupted => (
        Icons.help_outline,
        scheme.tertiary,
        context.t('Interrupted'),
      ),
    };
    return ListTile(
      dense: true,
      leading: Icon(operationKindIcon(entry.kind)),
      title: Text(
        '${operationKindLabel(context, entry.kind)} — ${entry.target}',
      ),
      subtitle: Text(
        '${_formatTime(entry.completedAt)}'
        '${entry.failureCode != null ? ' — ${entry.failureCode}' : ''}'
        '${entry.message.isNotEmpty ? ' — ${entry.message}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.retryable &&
              entry.retrySpec != null &&
              entry.retrySpec!.regeneratesPlan)
            Tooltip(
              message: context.t(
                'Needs a fresh plan — re-run from the VM actions',
              ),
              child: Icon(Icons.refresh, color: scheme.onSurfaceVariant),
            ),
          if (entry.canRetry)
            IconButton(
              tooltip: context.t('Retry'),
              icon: const Icon(Icons.replay),
              onPressed: () => _retry(context, ref),
            ),
          Icon(icon, color: color, semanticLabel: statusLabel),
        ],
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final spec = entry.retrySpec;
    if (spec == null) return;
    if (spec.requiresConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Retry {0}?', args: [entry.target])),
          content: Text(
            context.t('This operation may be destructive. Run it again?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Retry')),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await ref.read(activityProvider.notifier).retry(entry);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

String _formatTime(DateTime dt) {
  final s = dt.toLocal().toString();
  return s.length >= 16 ? s.substring(0, 16) : s;
}
