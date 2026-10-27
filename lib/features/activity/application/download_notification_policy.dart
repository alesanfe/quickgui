import 'package:quickgui/features/activity/domain/app_operation.dart';

/// Decides which finished download operations still need a desktop
/// notification. History entries each appear exactly once, so dedupe is
/// by operation id (falling back to target@completedAt for records
/// written before ids existed). The seen-set is bounded so long
/// sessions cannot grow it without limit.
class DownloadNotificationPolicy {
  final Set<String> _notifiedOps = {};

  /// Download entries in [history] not yet notified — marked as seen.
  List<OperationHistoryEntry> pending(List<OperationHistoryEntry> history) {
    final pending = <OperationHistoryEntry>[];
    for (final entry in history) {
      if (entry.kind != OperationKind.download) continue;
      final key = entry.id ?? '${entry.target}@${entry.completedAt}';
      if (_notifiedOps.add(key)) pending.add(entry);
    }
    if (_notifiedOps.length > 200) {
      _notifiedOps.clear();
    }
    return pending;
  }
}
