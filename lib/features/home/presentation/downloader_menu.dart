import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/core/persistence/preferences_repository.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/home/presentation/home_page_button_group.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/presentation/shared/validated_text_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

class DownloaderMenu extends ConsumerStatefulWidget {
  const DownloaderMenu({super.key});

  @override
  ConsumerState<DownloaderMenu> createState() => _DownloaderMenuState();
}

class _DownloaderMenuState extends ConsumerState<DownloaderMenu> {
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
      allowedExtensions: ['iso', 'img', 'qcow2'],
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

    final vmName = await showValidatedTextDialog<VmNameError>(
      context: context,
      title: context.t('Import a disk image'),
      label: context.t('Virtual machine name'),
      confirmLabel: context.t('Import'),
      initialValue: p.basenameWithoutExtension(imagePath),
      dirty: VmNameInput.dirty,
      message: (context, e) => context.vmNameError(e),
      description: Text(
        context.t(
          'The file will be moved into a new virtual machine folder inside the working directory.',
        ),
      ),
    );
    if (vmName == null || vmName.isEmpty || !mounted) {
      return;
    }

    final proc = await ref.read(backendProvider).runQuickget([
      '--create-config',
      vmName,
      imagePath,
    ]);
    if (!mounted) {
      return;
    }
    final output = '${proc.stdout}${proc.stderr}'.trim();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          proc.exitCode == 0
              ? context.t('Virtual machine imported')
              : context.t('Error'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              output.isEmpty ? '${proc.exitCode}' : output,
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
    return Expanded(
      child: DropTarget(
        onDragDone: (detail) {
          for (final file in detail.files) {
            if (file.path.isNotEmpty) {
              _importImageFile(file.path);
              break;
            }
          }
        },
        child: ColoredBox(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${context.t('Directory where the machines are stored')}:",
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surface,
                        ),
                        onPressed: () async {
                          final folder = await FilePicker.getDirectoryPath(
                            dialogTitle: "Pick a folder",
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
                const Divider(thickness: 2),
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: HomePageButtonGroup(),
                          ),
                        ],
                      ),
                    ),
                  ],
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
      ),
    );
  }
}
