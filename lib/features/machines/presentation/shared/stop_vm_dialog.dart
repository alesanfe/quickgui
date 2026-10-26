import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:version/version.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';
import 'package:quickgui/features/machines/application/stop_vm.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';

/// How the stop dialog ended: cancelled, graceful ACPI shutdown, or a
/// forced kill.
enum VmStopChoice { cancelled, shutdown, killed }

/// Asks whether to shut the guest down gracefully (ACPI powerdown via
/// the QEMU monitor) or force-stop it (discarding unsaved state), then
/// issues the corresponding backend command.
///
/// Returns the action taken so the caller can update its state caches.
Future<VmStopChoice> showStopVmDialog(
  BuildContext context, {
  required VirtualizationBackend backend,
  required String vm,
  required String confPath,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      final error = Theme.of(context).colorScheme.error;
      return AlertDialog(
        title: Text(context.t('Stop {0}', args: [vm])),
        content: Text(
          context.t(
            'Shut down {0} gracefully, or force it to stop? Forcing discards unsaved changes in the guest.',
            args: [vm],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: error),
            onPressed: () => Navigator.pop(context, 'kill'),
            child: Text(context.t('Force stop')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'shutdown'),
            child: Text(context.t('Shut down')),
          ),
        ],
      );
    },
  );
  if (choice == 'shutdown') {
    // ACPI powerdown via the QEMU monitor socket; the
    // VM keeps running until the guest OS finishes.
    final args = ['--vm', confPath, '--monitor-cmd', 'system_powerdown'];
    final r = await runVmActionOrLegacy(backend, 'monitor-cmd', args);
    if (context.mounted) showProcessOutputDialog(context, [r]);
    return VmStopChoice.shutdown;
  }
  if (choice == 'kill') {
    // If Quickemu is newer than 4.9.6, use the new --kill option
    // which is macOS compatible.
    final quickemuVersion = Version.parse(await backend.version());
    if (quickemuVersion >= Version(4, 9, 6)) {
      await StopVm(backend)(vm);
    } else {
      unawaited(backend.killVmProcess(vm));
    }
    return VmStopChoice.killed;
  }
  return VmStopChoice.cancelled;
}
