import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/core/persistence/preferences_repository.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/downloads/presentation/downloader.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/presentation/version_selection.dart';
import 'package:quickgui/features/home/presentation/downloader_page_button.dart';
import 'package:formz/formz.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

class HomePageButtonGroup extends ConsumerStatefulWidget {
  const HomePageButtonGroup({super.key});

  @override
  ConsumerState<HomePageButtonGroup> createState() =>
      _HomePageButtonGroupState();
}

class _HomePageButtonGroupState extends ConsumerState<HomePageButtonGroup> {
  OperatingSystem? _selectedOperatingSystem;
  Version? _selectedVersion;
  Option? _selectedOption;

  @override
  Widget build(BuildContext context) {
    var versionButtonLabel =
        _selectedVersion?.version ?? context.t('Select...');
    if (_selectedOption?.option.isNotEmpty ?? false) {
      versionButtonLabel = "$versionButtonLabel (${_selectedOption!.option})";
    }
    return Row(
      children: [
        DownloaderPageButton(
          label: context.t("Operating system"),
          text: _selectedOperatingSystem?.name ?? context.t('Select...'),
          onPressed: () {
            Navigator.of(context)
                .push<OperatingSystem>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (context) => const OperatingSystemSelection(),
                  ),
                )
                .then((selection) {
                  if (selection != null) {
                    setState(() {
                      _selectedOperatingSystem = selection;
                      if (selection.versions.length == 1 &&
                          selection.versions.first.options.length == 1) {
                        _selectedVersion = selection.versions.first;
                        _selectedOption =
                            selection.versions.first.options.first;
                      } else {
                        _selectedVersion = null;
                        _selectedOption = null;
                      }
                    });
                  }
                });
          },
        ),
        DownloaderPageButton(
          label: context.t('Version'),
          text: versionButtonLabel, //_selectedVersion?.version ?? 'Select...',
          onPressed: (_selectedOperatingSystem != null)
              ? () {
                  Navigator.of(context)
                      .push<Tuple2<Version, Option?>>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (context) => VersionSelection(
                            operatingSystem: _selectedOperatingSystem!,
                          ),
                        ),
                      )
                      .then((selection) {
                        if (selection != null) {
                          setState(() {
                            _selectedVersion = selection.item1;
                            _selectedOption = selection.item2;
                          });
                        }
                      });
                }
              : null,
        ),
        DownloaderPageButton(
          label: context.t('Download'),
          text: context.t('Download'),
          onPressed: (_selectedVersion == null)
              ? null
              : () async {
                  final workingDirectory = await ref
                      .read(preferencesRepositoryProvider)
                      .getAs<String>(prefWorkingDirectory);
                  final writable = await ref
                      .read(hostProbeProvider)
                      .canWriteToDirectory(
                        workingDirectory ?? Directory.current.path,
                      );
                  if (!context.mounted) return;
                  if (writable) {
                    // Warn when the host CPU does not meet the requirements
                    // of the selected macOS release.
                    if (_selectedOperatingSystem?.code == 'macos') {
                      final missing = await ref
                          .read(hostProbeProvider)
                          .missingMacosRequirements(_selectedVersion!.version);
                      if (missing.isNotEmpty) {
                        if (!context.mounted) return;
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(context.t('Error')),
                            content: Text(
                              context.t(
                                'macOS {0} requires a CPU with {1} support.',
                                args: [
                                  _selectedVersion!.version,
                                  missing
                                      .map(
                                        (f) => f.toUpperCase().replaceAll(
                                          '_',
                                          ' ',
                                        ),
                                      )
                                      .join(' and '),
                                ],
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
                        return;
                      }
                    }
                    // Windows guests need a TPM emulator (swtpm) when the
                    // generated config enables TPM/Secure Boot.
                    if ((_selectedOperatingSystem?.code ?? '').startsWith(
                      'windows',
                    )) {
                      if (!await ref.read(hostProbeProvider).hasTool('swtpm')) {
                        if (!context.mounted) return;
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(context.t('Error')),
                            content: Text(
                              context.t(
                                'swtpm was not found in your PATH. Windows guests require a TPM 2.0 emulator. Please install swtpm and try again.',
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
                        return;
                      }
                    }
                    // Verify the image is still downloadable before
                    // starting the download page.
                    final check = await ref.read(backendProvider).runQuickget([
                      '--check',
                      _selectedOperatingSystem!.code,
                      _selectedVersion!.version,
                      if (_selectedOption != null &&
                          _selectedOption!.option.isNotEmpty)
                        _selectedOption!.option,
                    ]);
                    if (!context.mounted) return;
                    if (check.exitCode != 0) {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(context.t('Error')),
                          content: Text(
                            context.t(
                              'The selected image is currently unavailable.',
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
                      return;
                    }
                    final custom = await _customizeDialog(context);
                    if (!context.mounted || custom == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => Downloader(
                          operatingSystem: _selectedOperatingSystem!,
                          version: _selectedVersion!,
                          customConf: custom,
                          option: _selectedOption,
                        ),
                      ),
                    );
                  } else {
                    if (!context.mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.t('Error')),
                        content: Text(
                          context.t(
                            'Could not write to the working directory. Please check the permissions.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: Text(context.t('OK')),
                          ),
                        ],
                      ),
                    );
                  }
                },
        ),
      ],
    );
  }

  void showLoadingIndicator({String text = ''}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
          backgroundColor: Colors.black87,
          content: SizedBox(
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    context.t('Downloading...'),
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                const CircularProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Target : ${Directory.current.absolute.path}',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void hideLoadingIndicator() {
    Navigator.of(context).pop();
  }

  void showDoneDialog({
    required String operatingSystem,
    required String version,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
          backgroundColor: Colors.black87,
          content: SizedBox(
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    context.t('Done !'),
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: Colors.white),
                  ),
                ),
                Text(
                  context.t(
                    'Now run {0} to start the VM',
                    args: ["quickemu --vm $operatingSystem-$version"],
                  ),
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: Colors.white),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Dismiss',
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>?> _customizeDialog(BuildContext context) {
    var ram = const SizeInput.pure('4G', true);
    var cores = const CpuCoresInput.pure();
    var disk = const SizeInput.pure('64G', true);
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final valid = Formz.validate([ram, cores, disk]);
          return AlertDialog(
            title: Text(context.t('Customise VM (optional)')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: ram.value,
                  onChanged: (v) =>
                      setState(() => ram = SizeInput.dirty(v, true)),
                  decoration: InputDecoration(
                    labelText: context.t('RAM'),
                    errorText: context.sizeError(ram.displayError),
                  ),
                ),
                TextFormField(
                  initialValue: cores.value,
                  onChanged: (v) =>
                      setState(() => cores = CpuCoresInput.dirty(v)),
                  decoration: InputDecoration(
                    labelText: context.t('CPU cores'),
                    errorText: context.cpuCoresError(cores.displayError),
                  ),
                ),
                TextFormField(
                  initialValue: disk.value,
                  onChanged: (v) =>
                      setState(() => disk = SizeInput.dirty(v, true)),
                  decoration: InputDecoration(
                    labelText: context.t('Disk size'),
                    errorText: context.sizeError(disk.displayError),
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
                onPressed: valid
                    ? () => Navigator.of(context).pop({
                        if (ram.value.trim().isNotEmpty)
                          'ram': ram.value.trim().toUpperCase(),
                        if (cores.value.trim().isNotEmpty)
                          'cpu_cores': cores.value.trim(),
                        if (disk.value.trim().isNotEmpty)
                          'disk_size': disk.value.trim().toUpperCase(),
                      })
                    : null,
                child: Text(context.t('Download')),
              ),
            ],
          );
        },
      ),
    );
  }
}
