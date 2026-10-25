import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/errors/app_failure.dart';

/// Common error surface: explains what happened, what was affected,
/// whether anything changed partially, and what the user can do next —
/// with technical details kept behind an expandable section.
class AppFailureView extends StatelessWidget {
  const AppFailureView({
    required this.failure,
    this.onRetry,
    this.compact = false,
    super.key,
  });

  final AppFailure failure;

  /// Shown when [AppFailure.retryable] — retries the failed operation.
  final VoidCallback? onRetry;

  /// Inline variant for forms/tiles (no card, smaller paddings).
  final bool compact;

  IconData get _icon => switch (failure.kind) {
    AppFailureKind.cancelled => Icons.cancel_outlined,
    AppFailureKind.spaceLow => Icons.storage_outlined,
    AppFailureKind.permission => Icons.lock_outline,
    AppFailureKind.dependencyMissing => Icons.extension_off_outlined,
    AppFailureKind.connection => Icons.link_off_outlined,
    AppFailureKind.timeout => Icons.schedule_outlined,
    AppFailureKind.externalModification => Icons.compare_arrows_outlined,
    AppFailureKind.virtualizationUnavailable => Icons.memory_outlined,
    _ => Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final affected = failure.vm ?? failure.operation;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, color: scheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(failure.userMessage, style: textTheme.bodyMedium),
                  if (affected != null)
                    Text(
                      context.t('Affected: {0}', args: [affected]),
                      style: textTheme.bodySmall,
                    ),
                  if (failure.partialChanges)
                    Text(
                      context.t(
                        'Some changes were applied before the failure.',
                      ),
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  if (failure.suggestion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        failure.suggestion!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            if (failure.retryable && onRetry != null)
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.t('Retry')),
              ),
            TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(text: failure.toReportLine()),
              ),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text(context.t('Copy error report')),
            ),
          ],
        ),
        if (failure.technical != null)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                context.t('Technical details'),
                style: textTheme.bodySmall,
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    failure.technical!,
                    style: textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (compact) {
      return Padding(padding: const EdgeInsets.all(8), child: content);
    }
    return Card(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}
