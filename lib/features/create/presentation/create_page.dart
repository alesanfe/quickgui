import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/shared/providers/working_directory_provider.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/core/errors/app_failure.dart';
import 'package:quickgui/features/create/application/import_image.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/create/presentation/create_wizard_page.dart';
import 'package:quickgui/features/create/presentation/download_controls.dart';
import 'package:quickgui/shared/widgets/logo.dart';

/// Classifies a dropped file path for [CreatePage]: 'conf' registers an
/// existing VM, 'archive' goes to `quickemu --import`, 'image' enters
/// the disk-image import flow (validated downstream), 'unsupported'
/// shows feedback and does nothing.
String dropKindFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.conf')) return 'conf';
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) return 'archive';
  const imageExts = {
    '.iso',
    '.img',
    '.qcow2',
    '.vdi',
    '.vmdk',
    '.vhdx',
    '.raw',
  };
  final dot = lower.lastIndexOf('.');
  if (dot >= 0 && imageExts.contains(lower.substring(dot))) return 'image';
  return 'unsupported';
}

/// "Create" section: pick an OS/version from the quickget catalogue or
/// import an existing disk image (drag & drop or file picker).
class CreatePage extends ConsumerStatefulWidget {
  const CreatePage({super.key});

  @override
  ConsumerState<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends ConsumerState<CreatePage> {
  @override
  void initState() {
    super.initState();
    final prefs = ref.read(preferencesRepositoryProvider);
    prefs.getAs<String>(prefWorkingDirectory).then((pref) async {
      final writable = await ref
          .read(hostProbeProvider)
          .canWriteToDirectory(ref.read(workingDirectoryProvider));
      if (!mounted) return;
      if (pref != null && pref.isNotEmpty && Directory(pref).existsSync()) {
        ref.read(workingDirectoryProvider.notifier).apply(pref);
      } else if (!writable) {
        // e.g. when launched from a read-only AppImage mount point.
        final home = ref.read(hostProbeProvider).fallbackWorkingDirectory;
        await ref.read(workingDirectoryProvider.notifier).set(home);
      }
    });
  }

  Future<void> _importImage() => importImageWithPicker(context, ref);

  bool _dragging = false;

  /// Routes a dropped file by extension: disk images go through the
  /// import flow, exported .tar.gz archives through `quickemu --import`,
  /// and .conf files are registered by copying them into the working dir.
  Future<void> _handleDrop(String path) async {
    switch (dropKindFor(path)) {
      case 'conf':
        final name = path.split(Platform.pathSeparator).last;
        try {
          await File(path).copy(
            '${ref.read(workingDirectoryProvider)}${Platform.pathSeparator}$name',
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t('Added {0}', args: [name]))),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      case 'archive':
        final okMessage = context.t('Virtual machine imported');
        String message;
        try {
          await ref.read(backendProvider).runVmJson('import', [
            '--import',
            path,
          ]);
          message = okMessage;
        } on AppFailure catch (e) {
          message = e.userMessage;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      case 'image':
        if (!mounted) return;
        await importImageFile(context, ref, path);
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t('Unsupported file type for drop: {0}', args: [path]),
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Create a virtual machine'))),
      body: DropTarget(
        onDragDone: (detail) {
          for (final file in detail.files) {
            if (file.path.isNotEmpty) {
              _handleDrop(file.path);
              break;
            }
          }
        },
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            border: _dragging
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Logo(height: 160),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        // Wraps to a second line at large text scales
                        // instead of truncating mid-sentence (VISTA-027).
                        child: Text(
                          "${context.t('Directory where the machines are stored')}:",
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Tooltip(
                          message: ref.watch(workingDirectoryProvider),
                          child: OutlinedButton(
                            // Neutral styling — accent-colored path text
                            // reads as an error at first glance.
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface,
                            ),
                            onPressed: () async {
                              final folder = await FilePicker.getDirectoryPath(
                                dialogTitle: context.t('Pick a folder'),
                              );
                              if (folder != null && folder.isNotEmpty) {
                                await ref
                                    .read(workingDirectoryProvider.notifier)
                                    .set(folder);
                              }
                            },
                            child: Text(
                              ref.watch(workingDirectoryProvider),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    // Bounded width keeps the three-step picker usable
                    // on wide windows instead of stretching edge to edge.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
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
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: Text(context.t('Import a disk image')),
                      onPressed: _importImage,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(context.t('Guided creation')),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (context) => const CreateWizardPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
