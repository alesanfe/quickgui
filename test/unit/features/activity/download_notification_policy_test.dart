import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/activity/application/download_notification_policy.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';

OperationHistoryEntry _entry({
  String? id,
  OperationKind kind = OperationKind.download,
  OperationStatus status = OperationStatus.succeeded,
  String target = 'ubuntu-24.04',
}) => OperationHistoryEntry(
  id: id,
  kind: kind,
  target: target,
  startedAt: DateTime(2026),
  completedAt: DateTime(2026, 1, 1, 1),
  status: status,
);

void main() {
  test('only download operations produce notifications', () {
    final policy = DownloadNotificationPolicy();
    final pending = policy.pending([
      _entry(id: 'd1'),
      _entry(id: 's1', kind: OperationKind.snapshot),
      _entry(id: 'd2', kind: OperationKind.export),
    ]);
    expect(pending.map((e) => e.id), ['d1']);
  });

  test('each finished op notifies exactly once across calls', () {
    final policy = DownloadNotificationPolicy();
    final entry = _entry(id: 'd1');
    expect(policy.pending([entry]), [entry]);
    expect(policy.pending([entry]), isEmpty);
  });

  test('succeeded, cancelled and failed downloads all notify', () {
    final policy = DownloadNotificationPolicy();
    final pending = policy.pending([
      _entry(id: 'ok'),
      _entry(id: 'cx', status: OperationStatus.cancelled),
      _entry(id: 'ko', status: OperationStatus.failed),
      _entry(id: 'int', status: OperationStatus.interrupted),
    ]);
    expect(pending.map((e) => e.id), ['ok', 'cx', 'ko', 'int']);
  });

  test('entries without id dedupe on target@completedAt', () {
    final policy = DownloadNotificationPolicy();
    final a = _entry();
    final b = _entry(target: 'fedora-41');
    expect(policy.pending([a, b, a]), hasLength(2));
  });
}
