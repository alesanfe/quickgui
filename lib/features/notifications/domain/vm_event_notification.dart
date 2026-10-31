import 'package:quickgui/infrastructure/quickemu/vm_event_log.dart';

/// Kinds of backend events the user can toggle individually (QG-081).
/// Kept coarse — the journal carries many fine-grained event names that
/// collapse onto these switches.
enum NotificationEventKind {
  vmStarted,
  vmStopped,
  vmCrashed,
  vmPausedResumed,
  vmDeleted,
  opCompleted,
  opFailed,
  snapshot,
  backup,
  qga,
  lowDisk,
}

/// Persisted under `prefVmNotifications` as JSON — global switch,
/// per-kind toggles, per-VM mutes and a temporary silence window.
class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.kindToggles = const {},
    this.mutedVms = const {},
    this.mutedUntilMs = 0,
  });

  /// Master switch for VM-event notifications (download notifications
  /// keep their own `prefNotifyOnComplete`).
  final bool enabled;

  /// Per-kind overrides — absent means enabled.
  final Map<NotificationEventKind, bool> kindToggles;

  /// VMs whose events never notify.
  final Set<String> mutedVms;

  /// Epoch ms until which everything is silenced ("do not disturb").
  final int mutedUntilMs;

  bool kindEnabled(NotificationEventKind kind) => kindToggles[kind] ?? true;

  bool mutedNow(int nowMs) => nowMs < mutedUntilMs;

  NotificationSettings copyWith({
    bool? enabled,
    Map<NotificationEventKind, bool>? kindToggles,
    Set<String>? mutedVms,
    int? mutedUntilMs,
  }) => NotificationSettings(
    enabled: enabled ?? this.enabled,
    kindToggles: kindToggles ?? this.kindToggles,
    mutedVms: mutedVms ?? this.mutedVms,
    mutedUntilMs: mutedUntilMs ?? this.mutedUntilMs,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'kinds': {for (final e in kindToggles.entries) e.key.name: e.value},
    'mutedVms': mutedVms.toList(),
    'mutedUntilMs': mutedUntilMs,
  };

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    final kinds = <NotificationEventKind, bool>{};
    final rawKinds = json['kinds'];
    if (rawKinds is Map) {
      for (final kind in NotificationEventKind.values) {
        final v = rawKinds[kind.name];
        if (v is bool) kinds[kind] = v;
      }
    }
    final rawMuted = json['mutedVms'];
    return NotificationSettings(
      enabled: json['enabled'] is! bool || json['enabled'] as bool,
      kindToggles: kinds,
      mutedVms: rawMuted is List ? {for (final v in rawMuted) '$v'} : const {},
      mutedUntilMs: json['mutedUntilMs'] is int
          ? json['mutedUntilMs'] as int
          : 0,
    );
  }
}

/// A notification ready for the desktop service — the UI translates
/// [titleKey]/[bodyKey] via gettext with [bodyArgs].
class VmNotification {
  const VmNotification({
    required this.kind,
    required this.vm,
    required this.titleKey,
    required this.bodyKey,
    this.bodyArgs = const [],
    this.urgent = false,
  });

  final NotificationEventKind kind;
  final String vm;
  final String titleKey;
  final String bodyKey;
  final List<String> bodyArgs;

  /// Crashes and failures interrupt — they get a longer timeout.
  final bool urgent;
}

/// Decides whether a journal event should surface as a desktop
/// notification (QG-080). Pure and clock-injected for tests; honours
/// the global switch, per-kind toggles, per-VM mutes, the silence
/// window, and groups repeated identical events instead of spamming.
class VmEventNotificationPolicy {
  /// Identical (vm, kind) events inside this window are suppressed and
  /// counted — the next allowed notification reports "×n".
  static const groupWindow = Duration(seconds: 60);

  final _lastSentAt = <String, int>{};
  final _suppressed = <String, int>{};

  /// Maps a journal event to a notification kind, or null when the
  /// event is not user-visible (progress ticks, internal bookkeeping).
  static NotificationEventKind? kindFor(VmEvent event) {
    final type = event.type;
    if (type == 'vm.started') return NotificationEventKind.vmStarted;
    if (type == 'vm.stopped') return NotificationEventKind.vmStopped;
    if (type == 'vm.crashed') return NotificationEventKind.vmCrashed;
    if (type == 'vm.paused' || type == 'vm.resumed') {
      return NotificationEventKind.vmPausedResumed;
    }
    if (type == 'vm.deleted') return NotificationEventKind.vmDeleted;
    if (type.startsWith('op.')) {
      final failed =
          type.contains('fail') ||
          event.data['state'] == 'failed' ||
          event.data['ok'] == false;
      return failed
          ? NotificationEventKind.opFailed
          : NotificationEventKind.opCompleted;
    }
    if (type.startsWith('snapshot.')) return NotificationEventKind.snapshot;
    if (type.startsWith('backup.')) return NotificationEventKind.backup;
    if (type.startsWith('qga.') || type.startsWith('guest.agent')) {
      return NotificationEventKind.qga;
    }
    if (type.startsWith('host.disk') || type.startsWith('disk.low')) {
      return NotificationEventKind.lowDisk;
    }
    return null;
  }

  /// Returns the notification to show, or null when the event is
  /// filtered out. [nowMs] is epoch milliseconds.
  VmNotification? decide(
    VmEvent event,
    NotificationSettings settings,
    int nowMs,
  ) {
    if (event is VmEventGap) return null;
    final kind = kindFor(event);
    if (kind == null) return null;
    if (!settings.enabled ||
        settings.mutedNow(nowMs) ||
        settings.mutedVms.contains(event.vm) ||
        !settings.kindEnabled(kind)) {
      return null;
    }
    final key = '${event.vm}|${kind.name}';
    final last = _lastSentAt[key] ?? -1 << 62;
    if (nowMs - last < groupWindow.inMilliseconds) {
      _suppressed[key] = (_suppressed[key] ?? 0) + 1;
      return null;
    }
    _lastSentAt[key] = nowMs;
    final repeat = (_suppressed.remove(key) ?? 0) + 1;
    if (_lastSentAt.length > 512) _lastSentAt.clear();
    return _build(event, kind, repeat);
  }

  VmNotification _build(VmEvent event, NotificationEventKind kind, int repeat) {
    final urgent =
        kind == NotificationEventKind.vmCrashed ||
        kind == NotificationEventKind.opFailed ||
        kind == NotificationEventKind.backup ||
        kind == NotificationEventKind.lowDisk;
    final titleKey = switch (kind) {
      NotificationEventKind.vmStarted => 'Machine started',
      NotificationEventKind.vmStopped => 'Machine stopped',
      NotificationEventKind.vmCrashed => 'Machine crashed',
      NotificationEventKind.vmPausedResumed =>
        event.type == 'vm.paused' ? 'Machine paused' : 'Machine resumed',
      NotificationEventKind.vmDeleted => 'Machine deleted',
      NotificationEventKind.opCompleted => 'Operation finished',
      NotificationEventKind.opFailed => 'Operation failed',
      NotificationEventKind.snapshot => 'Snapshot finished',
      NotificationEventKind.backup => 'Backup problem',
      NotificationEventKind.qga => 'Guest agent lost',
      NotificationEventKind.lowDisk => 'Low disk space',
    };
    // '{0}' = vm name (suffixed with "×n" when events were grouped).
    final bodyKey = switch (kind) {
      NotificationEventKind.vmCrashed =>
        '{0} stopped unexpectedly. Open Activity for details.',
      NotificationEventKind.lowDisk => 'The host is running low on disk space.',
      _ => '{0}',
    };
    final vmLabel = repeat > 1 ? '${event.vm} (×$repeat)' : event.vm;
    final bodyArgs = kind == NotificationEventKind.lowDisk
        ? const <String>[]
        : [vmLabel];
    return VmNotification(
      kind: kind,
      vm: event.vm,
      titleKey: titleKey,
      bodyKey: bodyKey,
      bodyArgs: bodyArgs,
      urgent: urgent,
    );
  }
}
