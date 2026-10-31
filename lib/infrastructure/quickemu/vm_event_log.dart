import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One entry from the backend's per-VM event journal
/// (`<vm>.events.jsonl`, written by quickemu via `qeEvent`).
class VmEvent {
  const VmEvent({
    required this.seq,
    required this.type,
    required this.vm,
    this.pid,
    this.ts,
    this.data = const {},
  });

  /// Monotonic sequence — used as the resume cursor (QG-023).
  final int seq;
  final String type;
  final String vm;
  final int? pid;
  final DateTime? ts;
  final Map<String, dynamic> data;

  /// Lifecycle events that change the library-visible VM state.
  static const stateChanging = {
    'vm.started',
    'vm.stopped',
    'vm.paused',
    'vm.resumed',
    'vm.crashed',
    'vm.deleted',
  };

  bool get changesState => stateChanging.contains(type);

  static VmEvent? tryParse(String line) {
    if (!line.contains('"seq"')) return null;
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, dynamic>) return null;
      final seq = json['seq'];
      if (seq is! int) return null;
      final data = json['data'];
      return VmEvent(
        seq: seq,
        type: '${json['event'] ?? ''}',
        vm: '${json['vm'] ?? ''}',
        pid: json['pid'] is int ? json['pid'] as int : null,
        ts: DateTime.tryParse('${json['ts'] ?? ''}'),
        data: data is Map<String, dynamic> ? data : const {},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Emitted when the journal was truncated or rotated under us and the
/// cursor can no longer prove continuity — consumers should do a full
/// state resync instead of trusting the cursor (QG-023).
class VmEventGap implements VmEvent {
  const VmEventGap(this.reason);
  final String reason;
  @override
  int get seq => -1;
  @override
  String get type => 'vm.log-gap';
  @override
  String get vm => '';
  @override
  int? get pid => null;
  @override
  DateTime? get ts => null;
  @override
  Map<String, dynamic> get data => const {};
  @override
  bool get changesState => true;
}

/// Reads and tails a VM event journal directly — no backend process
/// spawn per poll (QG-022). Existing lines are replayed once (those
/// with `seq > sinceSeq`), then file modifications stream new ones.
class VmEventLog {
  VmEventLog(this.filePath);

  /// `<vmdir>/<vm>.events.jsonl`.
  final String filePath;

  /// Events since [sinceSeq], then live-appended ones. Completes when
  /// the listener is cancelled; journal errors surface as [VmEventGap]
  /// rather than killing the stream.
  Stream<VmEvent> watch({int sinceSeq = 0}) {
    late StreamController<VmEvent> controller;
    StreamSubscription<FileSystemEvent>? sub;
    var offset = 0;
    var lastSeq = sinceSeq;
    var replayed = false;
    var busy = false;
    var pending = false;

    Future<void> drainOnce() async {
      try {
        final file = File(filePath);
        final len = await file.length().then((v) => v, onError: (_) => 0);
        if (len < offset) {
          // Truncated/rotated under our byte cursor — continuity is
          // lost: resync from the top and flag it.
          offset = 0;
          if (!controller.isClosed) {
            controller.add(const VmEventGap('journal truncated'));
          }
        }
        final raf = await file.open();
        try {
          await raf.setPosition(offset);
          final chunk = await raf.read(len - offset);
          offset = len;
          // Only whole lines: a partial tail line is re-read once its
          // newline lands.
          final text = utf8.decode(chunk, allowMalformed: true);
          final lastNl = text.lastIndexOf('\n');
          if (lastNl < 0) {
            offset = len - chunk.length;
          } else {
            // Byte-accurate cursor: count utf8 bytes per consumed line
            // so the unterminated tail is re-read next drain.
            var consumed = 0;
            final complete = text.substring(0, lastNl).split('\n');
            for (final line in complete) {
              consumed += utf8.encode(line).length + 1;
            }
            offset = len - chunk.length + consumed;
            for (final line in complete) {
              final e = VmEvent.tryParse(line);
              if (e == null || e.seq <= lastSeq) continue;
              // Gaps only matter on the live tail — a journal that
              // already contains holes replays them silently.
              if (replayed && e.seq > lastSeq + 1) {
                controller.add(
                  VmEventGap('missed seqs ${lastSeq + 1}..${e.seq - 1}'),
                );
              }
              lastSeq = e.seq;
              controller.add(e);
            }
          }
        } finally {
          await raf.close();
        }
        replayed = true;
      } catch (_) {
        // Unreadable journal (perm, transient lock): keep listening.
      }
    }

    Future<void> drain() async {
      // A watch event arriving mid-drain must not be dropped: mark it
      // and re-run so appended lines are not lost until the next
      // unrelated dir change.
      if (busy) {
        pending = true;
        return;
      }
      busy = true;
      try {
        do {
          pending = false;
          await drainOnce();
        } while (pending);
      } finally {
        busy = false;
      }
    }

    controller = StreamController<VmEvent>(
      onListen: () {
        unawaited(drain());
        try {
          // Any change inside the VM dir re-drains — comparing e.path
          // is brittle across separators/casing, and drain() is a
          // no-op when the journal size did not change.
          sub = File(filePath).parent
              .watch(events: FileSystemEvent.modify | FileSystemEvent.create)
              .listen((_) => unawaited(drain()), onError: (_) {});
        } catch (_) {
          // Journal dir missing (VM never launched): replay-only stream.
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Event types that count as health issues — crashes plus any
  /// `*.failed` operation result the backend records (heuristic:
  /// failure verbs all share the `.failed` suffix in the journal).
  static bool _isIssue(String type) =>
      type == 'vm.crashed' || type.endsWith('.failed') || type == 'vm.stale';

  /// One-shot count of issue events newer than [window] — the health
  /// card reads this without keeping a journal tail alive (QG-041).
  /// Events without a parseable `ts` still count: a seq-ordered
  /// journal entry with no timestamp is more likely recent than not.
  Future<int> recentIssueCount(Duration window, {DateTime? now}) async {
    try {
      return _countIssuesInText(
        await File(filePath).readAsString(),
        window,
        now,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Synchronous variant for contexts where async file I/O cannot be
  /// awaited (e.g. fake-async test zones).
  int recentIssueCountSync(Duration window, {DateTime? now}) {
    try {
      return _countIssuesInText(File(filePath).readAsStringSync(), window, now);
    } catch (_) {
      return 0;
    }
  }

  int _countIssuesInText(String text, Duration window, DateTime? now) {
    final cutoff = (now ?? DateTime.now()).subtract(window);
    var count = 0;
    for (final line in text.split('\n')) {
      final e = VmEvent.tryParse(line);
      if (e == null || !_isIssue(e.type)) continue;
      final ts = e.ts;
      if (ts != null && ts.isBefore(cutoff)) continue;
      count++;
    }
    return count;
  }

  /// The current last sequence in the journal — the resume cursor a
  /// consumer persists so a restart loses no events (QG-023).
  Future<int> lastSeq() async {
    try {
      final text = await File(filePath).readAsString();
      var last = 0;
      for (final line in text.split('\n')) {
        final e = VmEvent.tryParse(line);
        if (e != null && e.seq > last) last = e.seq;
      }
      return last;
    } catch (_) {
      return 0;
    }
  }
}
