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

  /// Abort the save and keep editing.
  cancel,
}

/// Parses `key="value"` lines into a map (last occurrence wins — matching
/// the `break`-free semantics bash `source` would apply).
Map<String, String> parseConfPairs(String raw) =>
    ConfDocument.parse(raw).toMap();

/// Shows the external-modification conflict dialog. [original] is the
/// content loaded when editing started, [local] the pending edits and
/// [disk] the current on-disk content. Returns null when the dialog is
/// dismissed without a choice.
Future<ConfConflictAction?> showConfConflictDialog(
  BuildContext context, {
  required String confPath,
  required String original,
  required String local,
  required String disk,
}) {
  final origMap = parseConfPairs(original);
  final localMap = parseConfPairs(local);
  final diskMap = parseConfPairs(disk);
  final keys = <String>{
    ...origMap.keys,
    ...localMap.keys,
    ...diskMap.keys,
  }.toList()..sort();
  final scheme = Theme.of(context).colorScheme;
  return showDialog<ConfConflictAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('Configuration changed outside Quickgui')),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(
                'The file {0} was modified by Quickemu, another editor or an external operation since it was opened.',
                args: [confPath],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(context.t('Key'))),
                    DataColumn(label: Text(context.t('Original'))),
                    DataColumn(label: Text(context.t('Your edit'))),
                    DataColumn(label: Text(context.t('On disk'))),
                  ],
                  rows: [
                    for (final key in keys)
                      DataRow(
                        cells: [
                          DataCell(Text(key)),
                          DataCell(Text(origMap[key] ?? '—')),
                          DataCell(
                            Text(
                              localMap[key] ?? '—',
                              style: localMap[key] != origMap[key]
                                  ? TextStyle(color: scheme.primary)
                                  : null,
                            ),
                          ),
                          DataCell(
                            Text(
                              diskMap[key] ?? '—',
                              style: diskMap[key] != origMap[key]
                                  ? TextStyle(color: scheme.error)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ConfConflictAction.saveCopy),
          child: Text(context.t('Save a copy')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ConfConflictAction.reload),
          child: Text(context.t('Reload from disk')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ConfConflictAction.overwrite),
          child: Text(context.t('Overwrite anyway')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ConfConflictAction.cancel),
          child: Text(context.t('Keep editing')),
        ),
      ],
    ),
  );
}

/// Writes the local edit buffer to `<confPath>.quickgui-localcopy` so the
/// user keeps their work without overwriting the externally-changed file.
String writeLocalCopy(String confPath, String content) {
  final copy = '$confPath.quickgui-localcopy';
  VmConfigFileStore.unawaitedWrite(copy, content);
  return copy;
}
