import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';

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
              child: SelectableText(
                entry.message.isEmpty ? statusLabel : entry.message,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
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
        '$when${entry.message.isNotEmpty ? ' — ${entry.message}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(icon, color: color, semanticLabel: statusLabel),
    );
  }
}
