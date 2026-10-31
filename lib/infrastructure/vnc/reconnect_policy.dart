import 'dart:math' as math;

/// Exponential-backoff schedule for RFB reconnection attempts.
///
/// Kept separate from the console page so the cadence is unit-testable
/// without a widget tree: delay(n) = base * 2^attempt, capped at [cap],
/// until [maxAttempts] is exhausted — then the caller falls back to
/// screendump polling instead of retrying forever.
class ReconnectPolicy {
  const ReconnectPolicy({
    this.base = const Duration(seconds: 1),
    this.cap = const Duration(seconds: 15),
    this.maxAttempts = 10,
  });

  /// First retry delay; doubles every attempt.
  final Duration base;

  /// Longest delay between attempts — prevents the backoff from
  /// growing unbounded while a VM reboots.
  final Duration cap;

  /// Attempts after which the caller should stop retrying. Avoids the
  /// infinite retry loop the acceptance criteria forbids.
  final int maxAttempts;

  /// Delay before attempt [attempt] (0-based): 1s, 2s, 4s, …, capped.
  Duration delayFor(int attempt) {
    if (attempt < 0) return Duration.zero;
    final ms = base.inMilliseconds * math.pow(2, attempt);
    return Duration(milliseconds: math.min(ms.toInt(), cap.inMilliseconds));
  }

  /// Whether another attempt may be scheduled after [attemptsDone].
  bool canRetry(int attemptsDone) => attemptsDone < maxAttempts;
}

/// Distinguishes *why* the console is waiting so the UI can say
/// "VM starting" vs "connection lost" (QG-006).
enum VncConnectionState {
  connecting,
  connected,

  /// First connection never succeeded — the guest's display server is
  /// probably still coming up after boot.
  starting,

  /// An established connection dropped; retrying.
  reconnecting,

  /// Retries exhausted or cancelled — caller fell back to screendump.
  failed,
}
