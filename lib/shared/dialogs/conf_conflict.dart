import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/infrastructure/storage/conf_document.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';

/// Decision taken in the external-modification conflict dialog.
enum ConfConflictAction {
  /// Discard local edits and reload the file from disk.
  reload,

  /// Overwrite the disk version with the local edits anyway.
  overwrite,

  /// Persist the local edits to a `<conf>.quickgui-localcopy` file and
  /// keep editing (nothing is overwritten).
  saveCopy,

  /// Apply the per-key resolution and save the merged document.
  merge,

  /// Abort the save and keep editing.
  cancel,
}

/// Dialog result — [merged] carries the resolved document content when
/// [action] is [ConfConflictAction.merge].
class ConfConflictResult {
  const ConfConflictResult(this.action, [this.merged]);

  final ConfConflictAction action;
  final String? merged;
}

/// Parses `key="value"` lines into a map (last occurrence wins — matching
/// the `break`-free semantics bash `source` would apply).
Map<String, String> parseConfPairs(String raw) =>
    ConfDocument.parse(raw).toMap();

/// Shows the external-modification conflict dialog. [original] is the
/// content loaded when editing started, [local] the pending edits and
/// [disk] the current on-disk content. Returns null when dismissed.
///
/// Keys that changed on only one side merge automatically; keys changed
/// on both sides need an explicit per-key choice (or the bulk
/// "use all local/disk" shortcuts). The merged document keeps the disk
/// file as its base — comments, unknown keys and unparsed lines are
/// preserved — then applies the resolved values via
/// [ConfDocument.applyEdits].
Future<ConfConflictResult?> showConfConflictDialog(
  BuildContext context, {
  required String confPath,
  required String original,
  required String local,
  required String disk,
}) {
  return showDialog<ConfConflictResult>(
    context: context,
    builder: (context) => _ConflictDialog(
      confPath: confPath,
      original: original,
      local: local,
      disk: disk,
    ),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.confPath,
    required this.original,
    required this.local,
    required this.disk,
  });

  final String confPath;
  final String original;
  final String local;
  final String disk;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  late final Map<String, String> _orig = parseConfPairs(widget.original);
  late final Map<String, String> _local = parseConfPairs(widget.local);
  late final Map<String, String> _disk = parseConfPairs(widget.disk);

  /// Explicit choice for genuinely conflicting keys (true = keep local).
  final Map<String, bool> _choices = {};

  late final List<String> _keys = (<String>{
    ..._orig.keys,
    ..._local.keys,
    ..._disk.keys,
  }).toList()..sort();

  /// True when the key changed on both sides with different values.
  bool _isConflict(String key) =>
      _local[key] != _disk[key] &&
      _local[key] != _orig[key] &&
      _disk[key] != _orig[key];

  int get _unresolved =>
      _keys.where((k) => _isConflict(k) && !_choices.containsKey(k)).length;

  String _mergedContent() => mergeConfDocuments(
    widget.local,
    widget.disk,
    original: widget.original,
    choices: _choices,
  );

  void _resolveAll(bool useLocal) => setState(() {
    for (final k in _keys.where(_isConflict)) {
      _choices[k] = useLocal;
    }
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unresolved = _unresolved;
    return AlertDialog(
      title: Text(context.t('Configuration changed outside Quickgui')),
      actionsOverflowDirection: VerticalDirection.down,
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(
                'The file {0} was modified by Quickemu, another editor or an external operation since it was opened.',
                args: [widget.confPath],
              ),
            ),
            if (unresolved > 0) ...[
              const SizedBox(height: 8),
              Text(
                context.t(
                  '{0} key(s) need a decision before merging.',
                  args: ['$unresolved'],
                ),
                style: TextStyle(color: scheme.error),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                context.t('All changes can be merged.'),
                style: TextStyle(color: scheme.tertiary),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => _resolveAll(true),
                  child: Text(context.t('Use all local')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _resolveAll(false),
                  child: Text(context.t('Use all on-disk')),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DataTable(
                        columnSpacing: 24,
                        columns: [
                          DataColumn(label: Text(context.t('Key'))),
                          DataColumn(label: Text(context.t('Original'))),
                          DataColumn(label: Text(context.t('Your edit'))),
                          DataColumn(label: Text(context.t('On disk'))),
                        ],
                        rows: [
                          for (final key in _keys)
                            DataRow(
                              cells: [
                                DataCell(Text(key)),
                                DataCell(Text(_orig[key] ?? '—')),
                                DataCell(
                                  Text(
                                    _local[key] ?? '—',
                                    style: _local[key] != _orig[key]
                                        ? TextStyle(color: scheme.primary)
                                        : null,
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    _disk[key] ?? '—',
                                    style: _disk[key] != _orig[key]
                                        ? TextStyle(color: scheme.error)
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (_keys.any(_isConflict)) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.t('Resolve conflicts'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        for (final key in _keys.where(_isConflict))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text('$key: '),
                                _choiceCell(key, scheme),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const ConfConflictResult(ConfConflictAction.saveCopy),
          ),
          child: Text(context.t('Save a copy')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const ConfConflictResult(ConfConflictAction.reload),
          ),
          child: Text(context.t('Reload from disk')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const ConfConflictResult(ConfConflictAction.overwrite),
          ),
          child: Text(context.t('Overwrite anyway')),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(
            context,
            const ConfConflictResult(ConfConflictAction.cancel),
          ),
          child: Text(context.t('Keep editing')),
        ),
        FilledButton(
          onPressed: unresolved > 0
              ? null
              : () => Navigator.pop(
                  context,
                  ConfConflictResult(
                    ConfConflictAction.merge,
                    _mergedContent(),
                  ),
                ),
          child: Text(context.t('Merge and save')),
        ),
      ],
    );
  }

  Widget _choiceCell(String key, ColorScheme scheme) {
    final useLocal = _choices[key];
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(context.t('Yours')),
          selected: useLocal == true,
          onSelected: (_) => setState(() => _choices[key] = true),
        ),
        ChoiceChip(
          label: Text(context.t('Disk')),
          selected: useLocal == false,
          onSelected: (_) => setState(() => _choices[key] = false),
        ),
      ],
    );
  }
}

/// Lets the user pick where to save a copy of the edited configuration.
///
/// The picker suggests `<name>.conf.local` next to the VM so the copy is
/// not picked up as a machine by the `*.conf` scanner. Existing targets
/// need an explicit overwrite confirmation; the write is atomic and the
/// previous file is kept as `.bak`. Returns the written path, or null
/// when the user cancelled.
Future<String?> pickAndSaveConfCopy(
  BuildContext context,
  String confPath,
  String content,
) async {
  final base = confPath.split(RegExp(r'[/\\]')).last;
  final uri = await FilePicker.saveFile(
    dialogTitle: context.t('Save a copy of {0}', args: [base]),
    fileName: '$base.local',
    bytes: utf8.encode(content),
  );
  final path = uri?.toFilePath();
  if (path == null || path.isEmpty || !context.mounted) return null;
  if (File(path).existsSync() &&
      File(path).readAsStringSync() != content) {
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Overwrite {0}?', args: [path])),
        content: Text(
          context.t(
            'The file exists and will be replaced. A .bak copy is kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('Overwrite')),
          ),
        ],
      ),
    );
    if (overwrite != true) return null;
  }
  await VmConfigFileStore.writeAtomic(path, content);
  return path;
}
