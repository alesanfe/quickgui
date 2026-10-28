import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Keyboard-shortcuts reference (WCAG 2.2 operable): every accelerator in
/// the app is discoverable here from Settings and the F1 key.
class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const ShortcutsDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      (context.t('Ctrl+1…6'), context.t('Switch between the six sections')),
      (context.t('Ctrl+F'), context.t('Filter the machines list')),
      (context.t('Ctrl+N'), context.t('Create a new virtual machine')),
      (context.t('Ctrl+R'), context.t('Refresh the machines list')),
      (context.t('Esc'), context.t('Cancel multi-select / close dialogs')),
      (context.t('F1'), context.t('Open this shortcuts reference')),
    ];
    return AlertDialog(
      title: Text(context.t('Keyboard shortcuts')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (keys, action) in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Chip(
                        label: Text(
                          keys,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(action)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Close')),
        ),
      ],
    );
  }
}
