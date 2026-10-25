import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/downloads/providers/download_tasks_provider.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/app/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/presentation/version_selection.dart';
import 'package:quickgui/features/create/presentation/downloader_page_button.dart';
import 'package:formz/formz.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/domain/vm_profile.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

/// Warn (but do not block) when free space in the working directory is
/// below this many bytes (~16 GB — a Windows/macOS image plus disk).
const int _lowSpaceBytes = 16 * 1024 * 1024 * 1024;

/// The three-step download control: pick an OS, a version, then start
/// the download after pre-flight checks and optional customisation.
class DownloadControls extends ConsumerStatefulWidget {
  const DownloadControls({super.key});

  @override
  ConsumerState<DownloadControls> createState() => _DownloadControlsState();
}

class _DownloadControlsState extends ConsumerState<DownloadControls> {
  OperatingSystem? _selectedOperatingSystem;
  Version? _selectedVersion;
  Option? _selectedOption;
  bool _checking = false;

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
          text: versionButtonLabel,
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
          busy: _checking,
          onPressed: (_selectedVersion == null)
              ? null
              : () => _startDownload(context),
        ),
      ],
    );
  }

  /// Pre-flight checks, then the customisation dialog, then the
  /// download task page.
  Future<void> _startDownload(BuildContext context) async {
    final workingDirectory = await ref
        .read(preferencesRepositoryProvider)
        .getAs<String>(prefWorkingDirectory);
    final dir = workingDirectory ?? Directory.current.path;
    final writable = await ref.read(hostProbeProvider).canWriteToDirectory(dir);
    if (!context.mounted) return;
    if (!writable) {
      await _showError(
        context,
        context.t(
          'Could not write to the working directory. Please check the permissions.',
        ),
      );
      return;
    }
    // Warn when the host CPU does not meet the requirements
    // of the selected macOS release.
    if (_selectedOperatingSystem?.code == 'macos') {
      final missing = await ref
          .read(hostProbeProvider)
          .missingMacosRequirements(_selectedVersion!.version);
      if (missing.isNotEmpty) {
        if (!context.mounted) return;
        await _showError(
          context,
          context.t(
            'macOS {0} requires a CPU with {1} support.',
            args: [
              _selectedVersion!.version,
              missing
                  .map((f) => f.toUpperCase().replaceAll('_', ' '))
                  .join(' and '),
            ],
          ),
        );
        return;
      }
    }
    // Windows guests need a TPM emulator (swtpm) when the
    // generated config enables TPM/Secure Boot.
    if ((_selectedOperatingSystem?.code ?? '').startsWith('windows')) {
      if (!await ref.read(hostProbeProvider).hasTool('swtpm')) {
        if (!context.mounted) return;
        await _showError(
          context,
          context.t(
            'swtpm was not found in your PATH. Windows guests require a TPM 2.0 emulator. Please install swtpm and try again.',
          ),
        );
        return;
      }
    }
    // Free-space check: warn below ~16 GB so a 20 GB download does not
    // fail halfway through.
    final free = await ref.read(hostProbeProvider).freeSpaceBytes(dir);
    if (!context.mounted) return;
    if (free != null && free < _lowSpaceBytes) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Low disk space')),
          content: Text(
            context.t(
              'Only {0} is free in the working directory. Large guests may fail to download or run out of disk space.',
              args: [formatBytes(free)],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.t('Continue anyway')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!context.mounted) return;
    }
    // Verify the image is still downloadable before
    // starting the download page. Show progress on the
    // button — the check does a network round-trip.
    setState(() => _checking = true);
    final check = await ref.read(backendProvider).runQuickget([
      '--check',
      _selectedOperatingSystem!.code,
      _selectedVersion!.version,
      if (_selectedOption != null && _selectedOption!.option.isNotEmpty)
        _selectedOption!.option,
    ]);
    if (mounted) setState(() => _checking = false);
    if (!context.mounted) return;
    if (check.exitCode != 0) {
      await _showError(
        context,
        context.t('The selected image is currently unavailable.'),
      );
      return;
    }
    final custom = await _customizeDialog(context, dir);
    if (!context.mounted || custom == null) return;
    // Non-blocking: the download runs in the activity centre so the user
    // can keep working (progress, cancel, per-VM history all live there).
    ref
        .read(downloadTasksProvider)
        .start(
          os: _selectedOperatingSystem!.code,
          release: _selectedVersion!.version,
          edition: _selectedOption?.option ?? '',
          configuration: custom,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.t('Download started — track it in Activity')),
      ),
    );
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/activity');
    } else {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(appRoute<void>(const ActivityPage()));
    }
  }

  Future<void> _showError(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Error')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('OK')),
          ),
        ],
      ),
    );
  }

  /// Optional pre-download customisation: a profile preset plus RAM /
  /// CPU / disk overrides written to the generated .conf afterwards.
  Future<Map<String, String>?> _customizeDialog(
    BuildContext context,
    String workingDirectory,
  ) {
    // Prefill with the recommended resources for the OS family.
    final recommended = recommendedProfileFor(
      _selectedOperatingSystem?.code ?? '',
    );
    var ram = SizeInput.pure(
      recommended.ram.isEmpty ? '4G' : recommended.ram,
      true,
    );
    var cores = CpuCoresInput.pure(recommended.cpuCores);
    var disk = SizeInput.pure(
      recommended.diskSize.isEmpty ? '64G' : recommended.diskSize,
      true,
    );
    var profile = recommended;
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final valid = Formz.validate([ram, cores, disk]);
          void applyProfile(VmProfile p) {
            profile = p;
            if (p.id != 'custom') {
              ram = SizeInput.pure(p.ram.isEmpty ? '4G' : p.ram, true);
              cores = CpuCoresInput.pure(p.cpuCores);
              disk = SizeInput.pure(
                p.diskSize.isEmpty ? '64G' : p.diskSize,
                true,
              );
            }
          }

          return AlertDialog(
            title: Text(context.t('Customise VM (optional)')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recap the pending download so the user confirms what
                // they selected before customising resources.
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '${_selectedOperatingSystem!.name} ${_selectedVersion!.version}${(_selectedOption?.option ?? '').isNotEmpty ? ' (${_selectedOption!.option})' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.t('Destination: {0}', args: [workingDirectory]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: profile.id,
                    decoration: InputDecoration(
                      labelText: context.t('Profile'),
                    ),
                    items: [
                      for (final p in vmProfiles)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      setState(
                        () => applyProfile(
                          vmProfiles.firstWhere((p) => p.id == id),
                        ),
                      );
                    },
                  ),
                ),
                if (profile.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      profile.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                TextFormField(
                  key: ValueKey('ram-${profile.id}'),
                  initialValue: ram.value,
                  onChanged: (v) =>
                      setState(() => ram = SizeInput.dirty(v, true)),
                  decoration: InputDecoration(
                    labelText: context.t('RAM'),
                    errorText: context.sizeError(ram.displayError),
                  ),
                ),
                TextFormField(
                  key: ValueKey('cores-${profile.id}'),
                  initialValue: cores.value,
                  onChanged: (v) =>
                      setState(() => cores = CpuCoresInput.dirty(v)),
                  decoration: InputDecoration(
                    labelText: context.t('CPU cores'),
                    errorText: context.cpuCoresError(cores.displayError),
                  ),
                ),
                TextFormField(
                  key: ValueKey('disk-${profile.id}'),
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
                        ...profile.extraConf,
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
