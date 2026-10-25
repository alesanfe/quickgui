import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';

/// Activity centre: in-flight operations with progress and cancel,
/// followed by the persisted history of finished ones.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Activity')),
        actions: [
          if (activity.history.isNotEmpty)
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
          if (activity.active.isNotEmpty) ...[
            _SectionHeader(context.t('In progress')),
            for (final op in activity.active) OperationTile(op: op),
            const SizedBox(height: 16),
          ],
          _SectionHeader(context.t('History')),
          if (activity.history.isEmpty && activity.active.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  context.t(
                    'No activity yet. Downloads and machine operations will show up here.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final e in activity.history) _HistoryTile(entry: e),
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
      OperationKind.command => context.t('Command'),
    };

class OperationTile extends ConsumerWidget {
  const OperationTile({required this.op, super.key});
  final AppOperation op;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = switch (op.state) {
      OperationRunning(:final progress?) => progress,
      _ => null,
    };
    final subtitle = switch (op.state) {
      OperationRunning(:final progress?) => '${(progress * 100).toInt()}%',
      OperationRunning() => context.t('Running'),
      OperationCancelling() => context.t('Cancelling'),
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

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});
  final OperationHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
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
        context.t('Failed'),
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
        '${_formatTime(entry.completedAt)}${entry.message.isNotEmpty ? ' — ${entry.message}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(icon, color: color, semanticLabel: statusLabel),
    );
  }
}

String _formatTime(DateTime dt) {
  final s = dt.toLocal().toString();
  return s.length >= 16 ? s.substring(0, 16) : s;
}
