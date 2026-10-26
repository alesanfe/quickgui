import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/dialogs/validated_text_dialog.dart';
import 'package:quickgui/shared/models/operation_state.dart';

/// Extensions imported directly (used as the VM image as-is).
const passthroughExtensions = {'iso', 'img', 'qcow2'};

/// Extensions converted to qcow2 with qemu-img before import.
const convertibleExtensions = {'vdi', 'vmdk', 'vhdx', 'raw'};

/// Picks a disk image and runs the import flow (shared by Create and
/// the wizard's "import" origin).
Future<void> importImageWithPicker(BuildContext context, WidgetRef ref) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: context.t('Select a disk image to import'),
    type: FileType.custom,
    allowedExtensions: [...passthroughExtensions, ...convertibleExtensions],
  );
  final imagePath = files.isNotEmpty ? files.single.path : null;
  if (imagePath == null || imagePath.isEmpty || !context.mounted) {
    return;
  }
  await importImageFile(context, ref, imagePath);
}

/// Imports [imagePath]: asks for a VM name, converts to qcow2 when the
/// format needs it, then creates the VM via `quickget --create-config`.
/// All long work is tracked in the activity centre.
Future<void> importImageFile(
  BuildContext context,
  WidgetRef ref,
  String imagePath,
) async {
  if (!context.mounted) return;
  final ext = p.extension(imagePath).replaceAll('.', '').toLowerCase();
  final convertible =
      !passthroughExtensions.contains(ext) &&
      convertibleExtensions.contains(ext);

  final vmName = await showValidatedTextDialog<VmNameError>(
    context: context,
    title: context.t('Import a disk image'),
    label: context.t('Virtual machine name'),
    confirmLabel: context.t('Import'),
    initialValue: p.basenameWithoutExtension(imagePath),
    dirty: VmNameInput.dirty,
    message: (context, e) => context.vmNameError(e),
    description: Text(
      convertible
          ? context.t(
              'The image will be converted to qcow2, then moved into a new virtual machine folder inside the working directory.',
            )
          : context.t(
              'The file will be moved into a new virtual machine folder inside the working directory.',
            ),
    ),
  );
  if (vmName == null || vmName.isEmpty || !context.mounted) return;

  var effectivePath = imagePath;
  if (convertible) {
    // qemu-img conversion is tracked in the activity centre: it can
    // take minutes for large images.
    final output = p.join(Directory.current.path, '$vmName.qcow2');
    final op = ref
        .read(activityProvider.notifier)
        .start(OperationKind.convert, vmName);
    final conv = await ref
        .read(backendProvider)
        .convertDiskImage(imagePath, output);
    if (!context.mounted) return;
    ref
        .read(activityProvider.notifier)
        .update(
          op,
          conv.exitCode == 0
              ? const OperationState.succeeded(null)
              : OperationState.failed(
                  code: 'convert.exit_${conv.exitCode}',
                  message: '${conv.stdout}${conv.stderr}'.trim(),
                ),
        );
    if (conv.exitCode != 0) {
      _showImportResult(context, conv.exitCode, conv.stdout, conv.stderr);
      return;
    }
    effectivePath = output;
  }

  final op = ref
      .read(activityProvider.notifier)
      .start(OperationKind.import, vmName);
  final proc = await ref.read(backendProvider).runQuickget([
    '--create-config',
    vmName,
    effectivePath,
  ]);
  if (!context.mounted) return;
  ref
      .read(activityProvider.notifier)
      .update(
        op,
        proc.exitCode == 0
            ? const OperationState.succeeded(null)
            : OperationState.failed(
                code: 'import.exit_${proc.exitCode}',
                message: '${proc.stdout}${proc.stderr}'.trim(),
              ),
      );
  _showImportResult(context, proc.exitCode, proc.stdout, proc.stderr);
}

void _showImportResult(
  BuildContext context,
  int exitCode,
  dynamic stdout,
  dynamic stderr,
) {
  final output = '$stdout$stderr'.trim();
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        exitCode == 0
            ? context.t('Virtual machine imported')
            : context.t('Error'),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            output.isEmpty ? '$exitCode' : output,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('OK')),
        ),
      ],
    ),
  );
}
