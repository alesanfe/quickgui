import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/notifications/domain/vm_event_notification.dart';
import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';

VmEvent ev(
  String type, {
  String vm = 'vm1',
  Map<String, dynamic> data = const {},
}) => VmEvent(seq: 1, type: type, vm: vm, data: data);

void main() {
  const settings = NotificationSettings();
  const policy = VmEventNotificationPolicy.new;
  const t0 = 1_700_000_000_000;

  group('kindFor maps journal event types', () {
    test('lifecycle events', () {
      expect(
        VmEventNotificationPolicy.kindFor(ev('vm.started')),
        NotificationEventKind.vmStarted,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('vm.stopped')),
        NotificationEventKind.vmStopped,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('vm.crashed')),
        NotificationEventKind.vmCrashed,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('vm.paused')),
        NotificationEventKind.vmPausedResumed,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('vm.deleted')),
        NotificationEventKind.vmDeleted,
      );
    });

    test('operation events split by outcome', () {
      expect(
        VmEventNotificationPolicy.kindFor(ev('op.completed')),
        NotificationEventKind.opCompleted,
      );
      expect(
        VmEventNotificationPolicy.kindFor(
          ev('op.completed', data: {'state': 'failed'}),
        ),
        NotificationEventKind.opFailed,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('op.failed')),
        NotificationEventKind.opFailed,
      );
    });

    test('snapshot, backup, qga and disk prefixes', () {
      expect(
        VmEventNotificationPolicy.kindFor(ev('snapshot.created')),
        NotificationEventKind.snapshot,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('backup.failed')),
        NotificationEventKind.backup,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('qga.disconnected')),
        NotificationEventKind.qga,
      );
      expect(
        VmEventNotificationPolicy.kindFor(ev('host.disk_low')),
        NotificationEventKind.lowDisk,
      );
    });

    test('gaps and unknown types are not user-visible', () {
      expect(
        VmEventNotificationPolicy.kindFor(const VmEventGap('truncated')),
        isNull,
      );
      expect(VmEventNotificationPolicy.kindFor(ev('internal.tick')), isNull);
    });
  });

  group('decide honours settings', () {
    test('master switch off suppresses everything', () {
      final p = policy();
      expect(
        p.decide(ev('vm.started'), settings.copyWith(enabled: false), t0),
        isNull,
      );
    });

    test('per-kind toggle off suppresses that kind only', () {
      final p = policy();
      final s = settings.copyWith(
        kindToggles: {NotificationEventKind.vmStarted: false},
      );
      expect(p.decide(ev('vm.started'), s, t0), isNull);
      expect(p.decide(ev('vm.stopped'), s, t0 + 1), isNotNull);
    });

    test('muted VM never notifies', () {
      final p = policy();
      final s = settings.copyWith(mutedVms: {'vm1'});
      expect(p.decide(ev('vm.started'), s, t0), isNull);
      expect(p.decide(ev('vm.started', vm: 'vm2'), s, t0 + 1), isNotNull);
    });

    test('silence window suppresses until it expires', () {
      final p = policy();
      final s = settings.copyWith(mutedUntilMs: t0 + 60_000);
      expect(p.decide(ev('vm.started'), s, t0), isNull);
      expect(p.decide(ev('vm.started'), s, t0 + 60_001), isNotNull);
    });
  });

  group('grouping', () {
    test('identical events inside the window collapse with a count', () {
      final p = policy();
      expect(p.decide(ev('vm.started'), settings, t0), isNotNull);
      // Second one inside 60s is suppressed.
      expect(p.decide(ev('vm.started'), settings, t0 + 10_000), isNull);
      // After the window the repeat count is folded into the body.
      final n = p.decide(ev('vm.started'), settings, t0 + 61_000);
      expect(n, isNotNull);
      expect(n!.bodyArgs.single, 'vm1 (×2)');
    });

    test('different kinds do not share the group window', () {
      final p = policy();
      expect(p.decide(ev('vm.started'), settings, t0), isNotNull);
      expect(p.decide(ev('vm.stopped'), settings, t0 + 1_000), isNotNull);
    });
  });

  group('notification content', () {
    test('crashes are urgent and point at Activity', () {
      final n = policy().decide(ev('vm.crashed'), settings, t0);
      expect(n!.urgent, isTrue);
      expect(n.bodyKey, contains('stopped unexpectedly'));
    });

    test('routine lifecycle events are not urgent', () {
      final n = policy().decide(ev('vm.started'), settings, t0);
      expect(n!.urgent, isFalse);
    });

    test('low disk notifications carry no vm arg', () {
      final n = policy().decide(ev('host.disk_low'), settings, t0);
      expect(n!.bodyArgs, isEmpty);
      expect(n.urgent, isTrue);
    });
  });

  group('NotificationSettings serialisation', () {
    test('round-trips toggles, mutes and the silence window', () {
      const original = NotificationSettings(
        enabled: false,
        kindToggles: {NotificationEventKind.qga: false},
        mutedVms: {'a', 'b'},
        mutedUntilMs: t0,
      );
      final restored = NotificationSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.enabled, isFalse);
      expect(restored.kindEnabled(NotificationEventKind.qga), isFalse);
      expect(restored.kindEnabled(NotificationEventKind.vmStarted), isTrue);
      expect(restored.mutedVms, {'a', 'b'});
      expect(restored.mutedUntilMs, t0);
    });

    test('defaults survive a corrupt document', () {
      final s = NotificationSettings.fromJson(const {
        'enabled': 'yes',
        'kinds': 'nope',
        'mutedVms': 42,
        'mutedUntilMs': 'soon',
      });
      expect(s.enabled, isTrue);
      expect(s.kindToggles, isEmpty);
      expect(s.mutedVms, isEmpty);
      expect(s.mutedUntilMs, 0);
    });
  });
}
