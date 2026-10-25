import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Edits one or more `key="value"` entries of a VM .conf file.
/// [title] names the purpose of the dialog (e.g. 'Resources') so the
/// user sees a semantic heading instead of the raw .conf filename.
///
/// [keys] maps conf keys to human labels; [options] optionally maps a
/// key to the list of allowed values, rendered as a dropdown that keeps
/// unknown current values selectable.
Future<void> showConfEditDialog(
  BuildContext context, {
  required String confPath,
  required String vmName,
  required Map<String, String> keys,
  required String title,
  Map<String, List<String>>? options,
}) async {
  final file = File(confPath);
  final lines = file.existsSync() ? await file.readAsLines() : <String>[];
  final controllers = <String, TextEditingController>{};
  for (final key in keys.keys) {
    final re = RegExp('^$key="(.*)"');
    var current = '';
    for (final l in lines) {
      final m = re.firstMatch(l);
      if (m != null) current = m.group(1)!;
    }
    controllers[key] = TextEditingController(text: current);
  }
  if (!context.mounted) return;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$title — $vmName'),
      content: SizedBox(
        width: double.maxFinite,
        // Scrollable: the 16-field "Settings (all)" dialog must stay
        // usable at the minimum window height (~800px).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: keys.entries.map((e) {
              final opts = options?[e.key];
              final current = controllers[e.key]!.text;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: opts == null
                    ? TextField(
                        controller: controllers[e.key],
                        decoration: InputDecoration(labelText: e.value),
                      )
                    : DropdownButtonFormField<String>(
                        // Keep the current value as an extra item when it
                        // is not one of the known options — picking
                        // opts.first would silently rewrite the .conf on OK.
                        initialValue: current.isEmpty ? null : current,
                        decoration: InputDecoration(labelText: e.value),
                        items: {...opts, if (current.isNotEmpty) current}
                            .map(
                              (o) => DropdownMenuItem(value: o, child: Text(o)),
                            )
                            .toList(),
                        onChanged: (v) => controllers[e.key]!.text = v ?? '',
                      ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.t('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t('OK')),
        ),
      ],
    ),
  );
  if (result != true) return;
  for (final key in keys.keys) {
    final value = controllers[key]!.text;
    final re = RegExp('^$key="');
    var replaced = false;
    for (var i = 0; i < lines.length; i++) {
      if (re.hasMatch(lines[i])) {
        lines[i] = '$key="$value"';
        replaced = true;
        break;
      }
    }
    if (!replaced) lines.add('$key="$value"');
  }
  await file.writeAsString('${lines.join('\n')}\n');
}
