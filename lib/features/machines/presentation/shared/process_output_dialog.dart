import 'package:quickgui/features/machines/application/ports/proc.dart';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Maps well-known failure patterns in backend output to a short,
/// actionable hint shown under the raw command output.
String? actionableErrorHint(BuildContext context, String output) {
  final lower = output.toLowerCase();
  if (lower.contains('/dev/kvm') &&
      (lower.contains('permission denied') || lower.contains('denied'))) {
    return context.t(
      'KVM is not accessible. Add your user to the kvm group or check /dev/kvm permissions.',
    );
  }
  if (lower.contains('no space left')) {
    return context.t(
      'The disk is full. Free space in the working directory or move the VMs to a larger disk.',
    );
  }
  if (lower.contains('swtpm')) {
    return context.t(
      'swtpm is not installed. Windows guests need a TPM 2.0 emulator.',
    );
  }
  if (lower.contains('address already in use') ||
      lower.contains('port') && lower.contains('in use')) {
    return context.t(
      'A required port is already in use. Stop the conflicting VM or change the port forwards.',
    );
  }
  if (lower.contains('could not open') && lower.contains('.img')) {
    return context.t(
      'The disk image is missing or corrupted. Verify the image or download it again.',
    );
  }
  if (lower.contains('spice') && lower.contains('not found')) {
    return context.t(
      'The SPICE viewer was not found. Install spicy or pick another display viewer in Settings.',
    );
  }
  return null;
}

/// Shows the merged stdout/stderr of backend invocations, plus an
/// actionable hint when the output matches a known failure pattern.
void showProcessOutputDialog(BuildContext context, List<ProcResult> results) {
  final output = results
      .map((r) => '${r.stdout}${r.stderr}')
      .where((s) => s.trim().isNotEmpty)
      .join('\n')
      .trim();
  if (output.isEmpty) {
    return;
  }
  final hint = actionableErrorHint(context, output);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.t('Command output')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(hint)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              SelectableText(
                output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Dismiss')),
        ),
      ],
    ),
  );
}
