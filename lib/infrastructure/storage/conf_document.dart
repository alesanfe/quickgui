import 'package:quickgui/features/machines/domain/vm_config_value.dart';

/// A single physical line of a `.conf` file.
///
/// Every line is preserved verbatim — `raw` — so a document can be
/// edited surgically and re-serialised without losing comments, blank
/// lines, unknown syntax or options written by a newer quickemu.
enum ConfLineKind { entry, comment, blank, unparsed }

class ConfLine {
  const ConfLine({
    required this.number,
    required this.raw,
    required this.kind,
    this.key,
    this.value,
    this.warning,
  });

  /// 1-based line number in the source document.
  final int number;
  final String raw;
  final ConfLineKind kind;

  /// Normalised key for [ConfLineKind.entry] lines.
  final String? key;

  /// Decoded value for [ConfLineKind.entry] lines (escapes undone).
  final String? value;

  /// Non-fatal diagnostic attached to this line (unquoted value,
  /// trailing content, duplicate key...). Lines that cannot be parsed
  /// at all are [ConfLineKind.unparsed] instead of being discarded.
  final String? warning;
}

/// Parsed view of a `key="value"` quickemu conf file.
///
/// Grammar accepted (matching what bash `source` tolerates):
///   key="value"        — canonical form
///   key="va l\"ue"     — escaped chars inside quotes
///   key=("a" "b")      — array form, kept verbatim as value
///   key=value          — unquoted, tolerated with a warning
///   key=               — empty value
///   # comment          — preserved
///   blank line         — preserved
/// Anything else is an [ConfLineKind.unparsed] line: preserved in the
/// document and surfaced through [unparsed] so callers never silently
/// drop syntax they do not understand.
class ConfDocument {
  ConfDocument._(this.lines, this.duplicateKeys);

  /// All physical lines in order.
  final List<ConfLine> lines;

  /// Keys that appear on more than one entry line. Bash `source` would
  /// apply last-wins; we keep every line verbatim and flag the key so
  /// callers can warn instead of silently overwriting user intent.
  final List<String> duplicateKeys;

  /// Lines that matched none of the accepted forms.
  List<ConfLine> get unparsed => [
    for (final l in lines)
      if (l.kind == ConfLineKind.unparsed) l,
  ];

  /// Lines carrying a non-fatal [ConfLine.warning].
  List<ConfLine> get warnings => [
    for (final l in lines)
      if (l.warning != null) l,
  ];

  static final _entryRe = RegExp(r'^\s*([A-Za-z_][\w-]*)\s*=(.*)$');
  static final _keyRe = RegExp(r'^[A-Za-z_][\w-]*$');

  factory ConfDocument.parse(String raw) {
    final lines = <ConfLine>[];
    final seen = <String, int>{};
    final duplicates = <String>[];
    final split = raw.split('\n');
    // A trailing newline produces an empty final element that is not a
    // real line; drop exactly one.
    final count = split.isNotEmpty && split.last.isEmpty
        ? split.length - 1
        : split.length;
    for (var i = 0; i < count; i++) {
      final number = i + 1;
      final line = split[i].replaceAll('\r', '');
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        lines.add(
          ConfLine(number: number, raw: line, kind: ConfLineKind.blank),
        );
        continue;
      }
      if (trimmed.startsWith('#')) {
        lines.add(
          ConfLine(number: number, raw: line, kind: ConfLineKind.comment),
        );
        continue;
      }
      final m = _entryRe.firstMatch(line);
      if (m == null) {
        lines.add(
          ConfLine(
            number: number,
            raw: line,
            kind: ConfLineKind.unparsed,
            warning: 'not a key=value line',
          ),
        );
        continue;
      }
      final key = m.group(1)!;
      final rawValue = m.group(2)!.trim();
      final decoded = _decodeValue(rawValue);
      if (decoded == null) {
        lines.add(
          ConfLine(
            number: number,
            raw: line,
            kind: ConfLineKind.unparsed,
            key: key,
            warning: 'malformed value',
          ),
        );
        continue;
      }
      String? warning;
      if (seen.containsKey(key)) {
        if (!duplicates.contains(key)) duplicates.add(key);
        warning = 'duplicate key (first seen on line ${seen[key]})';
      } else {
        seen[key] = number;
      }
      if (!rawValue.startsWith('"') && !rawValue.startsWith('(')) {
        warning = warning == null
            ? 'unquoted value'
            : '$warning; unquoted value';
      }
      lines.add(
        ConfLine(
          number: number,
          raw: line,
          kind: ConfLineKind.entry,
          key: key,
          value: decoded.value,
          warning: warning ?? decoded.warning,
        ),
      );
    }
    return ConfDocument._(lines, duplicates);
  }

  /// Decoded `key → value` map, last occurrence wins — matching the
  /// `break`-free semantics bash `source` applies to duplicated keys.
  Map<String, String> toMap() {
    final out = <String, String>{};
    for (final l in lines) {
      if (l.kind == ConfLineKind.entry && l.key != null) {
        out[l.key!] = l.value ?? '';
      }
    }
    return out;
  }

  /// Returns a new document with [edits] applied surgically: existing
  /// entry lines are rewritten in place (last occurrence wins), new
  /// keys are appended at the end, and every other line — comments,
  /// blanks, unknown or unparsed syntax — is preserved untouched.
  ConfDocument applyEdits(Map<String, String> edits) {
    if (edits.isEmpty) return this;
    final remaining = Map<String, String>.of(edits);
    // Identify the last entry line of each edited key.
    final lastOf = <String, int>{};
    for (var i = 0; i < lines.length; i++) {
      final k = lines[i].key;
      if (k != null && remaining.containsKey(k)) lastOf[k] = i;
    }
    final newLines = <ConfLine>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.kind == ConfLineKind.entry && l.key != null && lastOf[l.key] == i) {
        final v = edits[l.key]!;
        final stored = decodeVmValue(encodeVmValue(v));
        newLines.add(
          ConfLine(
            number: l.number,
            raw: '${l.key}="${encodeVmValue(v)}"',
            kind: ConfLineKind.entry,
            key: l.key,
            value: stored,
          ),
        );
        remaining.remove(l.key);
      } else {
        newLines.add(l);
      }
    }
    var n = lines.length;
    for (final e in remaining.entries) {
      n++;
      newLines.add(
        ConfLine(
          number: n,
          raw: '${e.key}="${encodeVmValue(e.value)}"',
          kind: ConfLineKind.entry,
          key: e.key,
          value: decodeVmValue(encodeVmValue(e.value)),
        ),
      );
    }
    return ConfDocument._(newLines, duplicateKeys);
  }

  /// Serialises every line back in order. Round-trip is byte-stable for
  /// documents that were not edited.
  String serialize() {
    final b = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      b.write(lines[i].raw);
      b.write('\n');
    }
    return b.toString();
  }

  /// True when [key] is a syntactically valid conf key.
  static bool isValidKey(String key) => _keyRe.hasMatch(key);
}

/// Three-way conf merge classification.
enum ConfMergePick { same, local, disk, conflict }

/// Compares one key across original/local/disk values.
ConfMergePick classifyConfKey(String? original, String? local, String? disk) {
  if (local == disk) return ConfMergePick.same;
  if (disk == original) return ConfMergePick.local; // only local changed
  if (local == original) return ConfMergePick.disk; // only disk changed
  return ConfMergePick.conflict;
}

/// Keys that changed on both sides with different values — the ones
/// that genuinely need a user decision.
List<String> confConflictKeys(String original, String local, String disk) {
  final o = ConfDocument.parse(original).toMap();
  final l = ConfDocument.parse(local).toMap();
  final d = ConfDocument.parse(disk).toMap();
  final keys = <String>{...o.keys, ...l.keys, ...d.keys};
  return [
    for (final k in keys)
      if (classifyConfKey(o[k], l[k], d[k]) == ConfMergePick.conflict) k,
  ]..sort();
}

/// Merges [local] edits into [disk] after an external modification.
///
/// [choices] resolves each conflicting key: true keeps the local value,
/// false keeps the disk value. Non-conflicting keys merge automatically
/// (local-only changes win, disk-only changes are kept). Keys absent
/// from [choices] that are in conflict keep the disk value — callers
/// that require an explicit decision must check [confConflictKeys]
/// first. Unknown lines, comments and unparsed syntax in [disk] are
/// preserved via [ConfDocument.applyEdits].
String mergeConfDocuments(
  String local,
  String disk, {
  String? original,
  Map<String, bool> choices = const {},
}) {
  final o = ConfDocument.parse(original ?? '').toMap();
  final l = ConfDocument.parse(local).toMap();
  final doc = ConfDocument.parse(disk);
  final d = doc.toMap();
  final keys = <String>{...o.keys, ...l.keys, ...d.keys};
  final edits = <String, String>{};
  for (final k in keys) {
    final pick = switch (classifyConfKey(o[k], l[k], d[k])) {
      ConfMergePick.conflict =>
        choices[k] == true ? ConfMergePick.local : ConfMergePick.disk,
      final p => p,
    };
    if (pick == ConfMergePick.local && d[k] != l[k]) edits[k] = l[k]!;
  }
  return doc.applyEdits(edits).serialize();
}

class _Decoded {
  const _Decoded(this.value, [this.warning]);
  final String value;
  final String? warning;
}

/// Validates and decodes a raw value token. Returns null when the
/// value is malformed (unclosed quote, stray trailing content).
_Decoded? _decodeValue(String raw) {
  if (raw.isEmpty) return const _Decoded('');
  if (raw.startsWith('(')) {
    // Array form: must be balanced parens and fully consumed. The
    // inner encoding is kept verbatim — elements stay bash-quoted.
    if (raw.length < 2 || !raw.endsWith(')')) return null;
    return _Decoded(raw);
  }
  if (!raw.startsWith('"')) {
    // Bare value: accepted (legacy files) with a warning when it
    // contains characters bash would reinterpret.
    final risky = RegExp(r'[\s"`$\\#;|&<>]').hasMatch(raw);
    return _Decoded(decodeVmValue(raw), risky ? 'unquoted value' : null);
  }
  // Quoted: scan for the closing unescaped quote, then require only
  // trailing whitespace.
  final b = StringBuffer();
  var i = 1;
  var closed = false;
  while (i < raw.length) {
    final c = raw[i];
    if (c == r'\') {
      if (i + 1 >= raw.length) return null; // dangling escape
      final n = raw[i + 1];
      b.write((n == '"' || n == r'\' || n == r'$' || n == '`') ? n : '$c$n');
      i += 2;
      continue;
    }
    if (c == '"') {
      closed = true;
      i++;
      break;
    }
    b.write(c);
    i++;
  }
  if (!closed) return null;
  if (raw.substring(i).trim().isNotEmpty) return null;
  return _Decoded(b.toString());
}
