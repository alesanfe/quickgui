import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';

import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';

/// '45 s', '3 min' — short readable duration for history rows.
String formatOperationDuration(BuildContext context, Duration d) {
  if (d.inSeconds < 2) return context.t('1 s');
  if (d.inMinutes < 1) return context.t('{0} s', args: ['${d.inSeconds}']);
  if (d.inHours < 1) {
    return context.t('{0} min', args: ['${d.inMinutes}']);
  }
  return context.t(
    '{0} h {1} min',
    args: ['${d.inHours}', '${d.inMinutes % 60}'],
  );
}

/// '2 h ago' — secondary relative timestamp (H-08).
String formatOperationAgo(BuildContext context, DateTime when) {
  final d = DateTime.now().difference(when);
  if (d.inMinutes < 1) return context.t('just now');
  if (d.inHours < 1) {
    return context.t('{0} min ago', args: ['${d.inMinutes}']);
  }
  if (d.inDays < 1) return context.t('{0} h ago', args: ['${d.inHours}']);
  return context.t('{0} d ago', args: ['${d.inDays}']);
}

/// Public tile rendering a finished [OperationHistoryEntry], used by the
/// activity centre and the per-VM activity tab.
class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({required this.entry, super.key});

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
    final s = entry.completedAt.toLocal().toString();
    final when = s.length >= 16 ? s.substring(0, 16) : s;
    // H-08: absolute time primary, duration and relative time as
    // secondary context — every row carries machine, operation, result.
    final duration = formatOperationDuration(
      context,
      entry.completedAt.difference(entry.startedAt),
    );
    final ago = formatOperationAgo(context, entry.completedAt);
    final canOpen =
        GoRouter.maybeOf(context) != null && entry.target.isNotEmpty;
    return ListTile(
      dense: true,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '${operationKindLabel(context, entry.kind)} — ${entry.target}',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$when · ${context.t('Duration')}: $duration · $statusLabel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    entry.message.isEmpty ? statusLabel : entry.message,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (canOpen)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(
                    '/machines/${Uri.encodeComponent(entry.target)}',
                  );
                },
                child: Text(context.t('Open machine')),
              ),
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${entry.completedAt.toIso8601String()} ${entry.kind.name} ${entry.status.name}\n${entry.message}',
                ),
              ),
              child: Text(context.t('Copy report')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.t('Close')),
            ),
          ],
        ),
      ),
      leading: Icon(operationKindIcon(entry.kind)),
      title: Text(
        '${operationKindLabel(context, entry.kind)} — ${entry.target}',
      ),
      subtitle: Text(
        '$when ($ago) · $duration'
        '${entry.message.isNotEmpty ? ' — ${entry.message}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(icon, color: color, semanticLabel: statusLabel),
    );
  }
}
