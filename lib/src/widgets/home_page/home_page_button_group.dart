import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/src/globals.dart';
import 'package:quickgui/src/mixins/preferences_mixin.dart';
import 'package:tuple/tuple.dart';

import '../../model/operating_system.dart';
import '../../model/option.dart';
import '../../model/version.dart';
import '../../pages/downloader.dart';
import '../../pages/operating_system_selection.dart';
import '../../pages/version_selection.dart';
import 'downloader_page_button.dart';

class HomePageButtonGroup extends StatefulWidget {
  const HomePageButtonGroup({super.key});

  @override
  State<HomePageButtonGroup> createState() => _HomePageButtonGroupState();
}

class _HomePageButtonGroupState extends State<HomePageButtonGroup>
    with PreferencesMixin {
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
                  final workingDirectory = await getPreference<String>(
                    prefWorkingDirectory,
                  );
                  final tmpFile = File("$workingDirectory/modecheck.tmp");
                  if (tmpFile.existsSync()) {
                    tmpFile.deleteSync();
                  }
                  try {
                    tmpFile.createSync();
                  } catch (e) {
                    // Do nothing
                  }
                  if (tmpFile.existsSync()) {
                    tmpFile.deleteSync();

                    if (!context.mounted) return;
                    // Warn when the host CPU does not meet the requirements
                    // of the selected macOS release.
                    if (_selectedOperatingSystem?.code == 'macos') {
                      final missing = await missingMacosRequirements(
                        _selectedVersion!.version,
                      );
                      if (missing.isNotEmpty) {
                        if (!context.mounted) return;
                        showDialog(
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
                      if (!await commandAvailable('swtpm')) {
                        if (!context.mounted) return;
                        showDialog(
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
                    final check = await backend.runQuickget([
                      '--check',
                      _selectedOperatingSystem!.code,
                      _selectedVersion!.version,
                      if (_selectedOption != null &&
                          _selectedOption!.option.isNotEmpty)
                        _selectedOption!.option,
                    ]);
                    if (!context.mounted) return;
                    if (check.exitCode != 0) {
                      showDialog(
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
                      MaterialPageRoute(
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
                    showDialog(
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
    showDialog(
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
    showDialog(
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
    final ram = TextEditingController(text: '4G');
    final cores = TextEditingController();
    final disk = TextEditingController(text: '64G');
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Customise VM (optional)')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ram,
              decoration: InputDecoration(labelText: context.t('RAM')),
            ),
            TextField(
              controller: cores,
              decoration: InputDecoration(labelText: context.t('CPU cores')),
            ),
            TextField(
              controller: disk,
              decoration: InputDecoration(labelText: context.t('Disk size')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop({
              if (ram.text.trim().isNotEmpty) 'ram': ram.text.trim(),
              if (cores.text.trim().isNotEmpty) 'cpu_cores': cores.text.trim(),
              if (disk.text.trim().isNotEmpty) 'disk_size': disk.text.trim(),
            }),
            child: Text(context.t('Download')),
          ),
        ],
      ),
    );
  }
}
