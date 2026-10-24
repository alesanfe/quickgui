import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;

import '../../globals.dart';
import '../../mixins/preferences_mixin.dart';
import '../home_page/home_page_button_group.dart';

class DownloaderMenu extends StatefulWidget {
  const DownloaderMenu({super.key});

  @override
  State<DownloaderMenu> createState() => _DownloaderMenuState();
}

class _DownloaderMenuState extends State<DownloaderMenu> with PreferencesMixin {
  String _currentPath = Directory.current.path;

  @override
  void initState() {
    super.initState();
    getPreference<String>(prefWorkingDirectory).then((pref) {
      if (pref != null && pref.isNotEmpty && Directory(pref).existsSync()) {
        setState(() {
          Directory.current = pref;
          _currentPath = pref;
        });
      } else if (!isWritableDirectory(Directory.current.path)) {
        // e.g. when launched from a read-only AppImage mount point.
        final home = fallbackWorkingDirectory();
        setState(() {
          Directory.current = home;
          _currentPath = home;
        });
        savePreference(prefWorkingDirectory, home);
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

    final nameController = TextEditingController(
      text: p.basenameWithoutExtension(imagePath),
    );
    final vmName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Import a disk image')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(
                'The file will be moved into a new virtual machine folder inside the working directory.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.t('Virtual machine name'),
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
            onPressed: () =>
                Navigator.of(context).pop(nameController.text.trim()),
            child: Text(context.t('Import')),
          ),
        ],
      ),
    );
    if (vmName == null || vmName.isEmpty || !mounted) {
      return;
    }

    final proc = await runHost('quickget', [
      '--create-config',
      vmName,
      imagePath,
    ]);
    if (!mounted) {
      return;
    }
    final output = '${proc.stdout}${proc.stderr}'.trim();
    showDialog(
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
        child: Container(
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
                          var folder = await FilePicker.getDirectoryPath(
                            dialogTitle: "Pick a folder",
                          );
                          if (folder != null && folder.isNotEmpty) {
                            setState(() {
                              Directory.current = folder;
                              _currentPath = folder;
                            });
                            savePreference(
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
                        mainAxisAlignment: MainAxisAlignment.start,
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
