/// One recorded legacy-fallback use.
class LegacyTelemetryEntry {
  const LegacyTelemetryEntry({
    required this.command,
    required this.reason,
    required this.at,
    this.backendVersion = '',
  });

  /// Structured command that could not get an envelope (e.g. 'start').
  final String command;

  /// Envelope-absence code that triggered the fallback.
  final String reason;

  /// When the fallback happened.
  final DateTime at;

  /// Detected backend version when known.
  final String backendVersion;

  Map<String, dynamic> toJson() => {
    'command': command,
    'reason': reason,
    'at': at.toIso8601String(),
    if (backendVersion.isNotEmpty) 'backendVersion': backendVersion,
  };
}

/// Local-only telemetry for legacy-backend fallbacks. Nothing leaves
/// the machine — the diagnostics screen surfaces the counters so users
/// know when Quickemu predates the structured contract.
class LegacyTelemetry {
  LegacyTelemetry._();

  static const _limit = 50;
  static final List<LegacyTelemetryEntry> _entries = [];

  /// Bounded fallback log, newest first.
  static List<LegacyTelemetryEntry> get entries => List.unmodifiable(_entries);

  /// Number of legacy fallbacks seen since app start.
  static int get count => _entries.length;

  /// Commands that fell back, deduplicated.
  static Set<String> get commands => {for (final e in _entries) e.command};

  /// Last fallback use, or null when none.
  static LegacyTelemetryEntry? get last =>
      _entries.isEmpty ? null : _entries.first;

  static void record(
    String command,
    String reason, {
    String backendVersion = '',
  }) {
    _entries.insert(
      0,
      LegacyTelemetryEntry(
        command: command,
        reason: reason,
        at: DateTime.now(),
        backendVersion: backendVersion,
      ),
    );
    if (_entries.length > _limit) _entries.removeLast();
  }

  /// Exportable, already-redacted summary for diagnostics reports.
  static List<Map<String, dynamic>> toJson() => [
    for (final e in _entries) e.toJson(),
  ];

  /// Test hook — clears the recorded entries.
  static void reset() => _entries.clear();
}
