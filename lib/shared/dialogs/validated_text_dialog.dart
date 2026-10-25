import 'package:flutter/material.dart';
import 'package:formz/formz.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Single-field dialog backed by a Formz input: shows the validation
/// message once the user edits, and disables confirm while invalid.
/// Returns the trimmed value, or null when cancelled.
Future<String?> showValidatedTextDialog<E>({
  required BuildContext context,
  required String title,
  required String label,
  required String confirmLabel,
  required String initialValue,
  required FormzInput<String, E> Function(String value) dirty,
  required String? Function(BuildContext context, E? error) message,
  Widget? description,
}) {
  final controller = TextEditingController(text: initialValue);
  var input = dirty(initialValue);
  var touched = false;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          if (input.isValid) Navigator.of(context).pop(controller.text.trim());
        }

        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (description != null) ...[
                description,
                const SizedBox(height: 16),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (v) => setState(() {
                  touched = true;
                  input = dirty(v);
                }),
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: label,
                  errorText: touched ? message(context, input.error) : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              onPressed: input.isValid ? submit : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
}
