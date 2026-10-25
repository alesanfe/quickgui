import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/delete_vm.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Safe delete flow: previews the backend's delete plan (or the file
/// list as a fallback), then offers "delete disk only" vs "delete the
/// whole VM". Returns true when something was deleted.
Future<bool> showDeleteVmDialog(
  BuildContext context, {
  required VirtualizationBackend backend,
  required String vm,
  required String confPath,
}) async {
  // Preview what will be deleted via the backend's safe delete plan.
  final planResult = await DeleteVm(backend).plan(vm);
  var planText = switch (planResult) {
    Ok<List<String>>(value: final v) when v.isNotEmpty => v.join('\n'),
    _ => '',
  };
  if (planText.isEmpty) {
    // Backends without a delete plan still need to show exactly what is
    // about to be removed: the .conf plus every file in the VM folder.
    final paths = <String>[
      confPath,
      if (Directory(vm).existsSync())
        ...Directory(vm).listSync(recursive: true).map((e) => e.path),
    ]..sort();
    planText = paths.join('\n');
  }
  if (!context.mounted) return false;
  final result = await showDialog<String?>(
    context: context,
    builder: (BuildContext context) {
      final error = Theme.of(context).colorScheme.error;
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: error),
            const SizedBox(width: 8),
            Flexible(child: Text(context.t('Delete {0}', args: [vm]))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(
                'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?',
                args: [vm],
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  planText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text(context.t('Cancel')),
            onPressed: () => Navigator.pop(context, 'cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: error),
            onPressed: () => Navigator.pop(context, 'disk'),
            child: Text(context.t('Delete disk image')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, 'vm'),
            child: Text(context.t('Delete whole VM')),
          ),
        ],
      );
    },
  );
  if (result == null || result == 'cancel') return false;
  final args = ['--vm', '$vm.conf', '--delete-$result'];
  try {
    await backend.runVmJson('delete-$result', args);
  } on AppFailure catch (e) {
    if (!isBackendEnvelopeMissing(e)) rethrow;
    await backend.runAction(args);
  }
  return true;
}
