import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/create/presentation/download_controls.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/shared/dialogs/validated_text_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/widgets/logo.dart';

/// Extensions imported directly (used as the VM image as-is).
const _passthroughExtensions = {'iso', 'img', 'qcow2'};

/// Extensions converted to qcow2 with qemu-img before import.
const _convertibleExtensions = {'vdi', 'vmdk', 'vhdx', 'raw'};

/// "Create" section: pick an OS/version from the quickget catalogue or
/// import an existing disk image (drag & drop or file picker).
class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  String _currentPath = Directory.current.path;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferencesRepositoryProvider);
    prefs.getAs<String>(prefWorkingDirectory).then((pref) async {
      final writable = await ref
          .read(hostProbeProvider)
          .canWriteToDirectory(Directory.current.path);
      if (!mounted) return;
      if (pref != null && pref.isNotEmpty && Directory(pref).existsSync()) {
        setState(() {
          Directory.current = pref;
          _currentPath = pref;
        });
      } else if (!writable) {
        // e.g. when launched from a read-only AppImage mount point.
        final home = ref.read(hostProbeProvider).fallbackWorkingDirectory;
        setState(() {
          Directory.current = home;
          _currentPath = home;
        });
        prefs.set(prefWorkingDirectory, home);
      }
    });
  }

  Future<void> _importImage() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: context.t('Select a disk image to import'),
      type: FileType.custom,
      allowedExtensions: [..._passthroughExtensions, ..._convertibleExtensions],
    );
    final imagePath = files.isNotEmpty ? files.single.path : null;
    if (imagePath == null || imagePath.isEmpty || !mounted) {
      return;
    }
    await _importImageFile(imagePath);
  }

  Future<void> _importImageFile(String imagePath) async {
    if (!mounted) {
      return;
    }
    final ext = p.extension(imagePath).replaceAll('.', '').toLowerCase();
    final convertible =
        !_passthroughExtensions.contains(ext) &&
        _convertibleExtensions.contains(ext);

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
    if (vmName == null || vmName.isEmpty || !mounted) {
      return;
    }

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
      if (!mounted) return;
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
    if (!mounted) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Create a virtual machine'))),
      body: DropTarget(
        onDragDone: (detail) {
          for (final file in detail.files) {
            if (file.path.isNotEmpty) {
              _importImageFile(file.path);
              break;
            }
          }
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Logo(height: 160),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${context.t('Directory where the machines are stored')}:",
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final folder = await FilePicker.getDirectoryPath(
                          dialogTitle: context.t('Pick a folder'),
                        );
                        if (folder != null && folder.isNotEmpty) {
                          setState(() {
                            Directory.current = folder;
                            _currentPath = folder;
                          });
                          ref
                              .read(preferencesRepositoryProvider)
                              .set(
                                prefWorkingDirectory,
                                Directory.current.path,
                              );
                        }
                      },
                      child: Text(_currentPath),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        context.t(
                          'Pick an operating system and a version, or drop a disk image anywhere on this page.',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const DownloadControls(),
                  ],
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.upload_file),
                label: Text(context.t('Import a disk image')),
                onPressed: _importImage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
