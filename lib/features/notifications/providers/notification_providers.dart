import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/features/notifications/domain/vm_event_notification.dart';
import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// VM-event notification preferences (QG-081), persisted as a single
/// JSON document under [prefVmNotifications].
class NotificationSettingsController extends Notifier<NotificationSettings> {
  @override
  NotificationSettings build() {
    unawaited(_load());
    return const NotificationSettings();
  }

  Future<void> _load() async {
    final raw = await ref
        .read(preferencesRepositoryProvider)
        .getAs<String>(prefVmNotifications);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        state = NotificationSettings.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt preference: defaults apply.
    }
  }

  Future<void> _save(NotificationSettings next) async {
    state = next;
    await ref
        .read(preferencesRepositoryProvider)
        .set(prefVmNotifications, jsonEncode(next.toJson()));
  }

  Future<void> setEnabled(bool enabled) =>
      _save(state.copyWith(enabled: enabled));

  Future<void> setKind(NotificationEventKind kind, bool enabled) =>
      _save(state.copyWith(kindToggles: {...state.kindToggles, kind: enabled}));

  Future<void> setVmMuted(String vm, bool muted) => _save(
    state.copyWith(
      mutedVms: muted
          ? {...state.mutedVms, vm}
          : state.mutedVms.difference({vm}),
    ),
  );

  /// Silence every notification for [duration] ("do not disturb").
  Future<void> muteFor(Duration duration) => _save(
    state.copyWith(
      mutedUntilMs:
          DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds,
    ),
  );

  Future<void> unmute() => _save(state.copyWith(mutedUntilMs: 0));
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsController, NotificationSettings>(
      NotificationSettingsController.new,
    );

/// The policy instance shared by the app shell — keeps suppression
/// state across rebuilds.
final vmNotificationPolicyProvider = Provider<VmEventNotificationPolicy>(
  (ref) => VmEventNotificationPolicy(),
);

/// Merged stream of every known VM's backend event journal (QG-080) —
/// the single fan-in point where the shell listens for events worth a
/// desktop notification. VMs appearing later join the merge on the
/// next library refresh.
final vmEventsProvider = StreamProvider<VmEvent>((ref) async* {
  final machines = await ref.watch(vmLibraryProvider.future);
  if (machines.isEmpty) return;
  final probe = ref.watch(hostProbeProvider);
  final directory = await probe.workingDirectory();
  final root = directory.isEmpty ? Directory.current.path : directory;

  final controller = StreamController<VmEvent>();
  final subs = <StreamSubscription<VmEvent>>[
    for (final m in machines)
      VmEventLog(p.join(root, m.name, '${m.name}.events.jsonl'))
          .watch()
          .listen(controller.add, onError: (_) {}),
  ];
  ref.onDispose(() {
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
    unawaited(controller.close());
  });
  await for (final event in controller.stream) {
    yield event;
  }
});
