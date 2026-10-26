import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:formz/formz.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/app/router/app_router.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/presentation/version_selection.dart';
import 'package:quickgui/features/create/application/import_image.dart';
import 'package:quickgui/features/downloads/providers/download_tasks_provider.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/domain/vm_profile.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';

/// Warn (but do not block) when free space is below ~16 GB.
const int _lowSpaceBytes = 16 * 1024 * 1024 * 1024;

/// Guided five-step creation flow:
/// origin → system → resources → integration → review.
/// The final step runs the same pre-flight checks as the inline Create
/// page, then hands the work to the activity centre.
class CreateWizardPage extends ConsumerStatefulWidget {
  const CreateWizardPage({super.key});

  @override
  ConsumerState<CreateWizardPage> createState() => _CreateWizardPageState();
}

class _CreateWizardPageState extends ConsumerState<CreateWizardPage> {
  int _step = 0;
  bool _import = false;
  bool _importDone = false;
  bool _checking = false;

  OperatingSystem? _os;
  Version? _version;
  Option? _option;
  late VmProfile _profile = vmProfiles.first;
  var _ram = const SizeInput.pure('4G', true);
  var _cores = const CpuCoresInput.pure('4');
  var _disk = const SizeInput.pure('64G', true);
  String _viewer = '';
  bool _startAfter = true;

  bool _stepValid(int step) => switch (step) {
    0 => true,
    1 => _import || _version != null,
    2 => Formz.validate([_ram, _cores, _disk]),
    3 => true,
    4 => true,
    _ => false,
  };

  Map<String, String> get _confOverrides => {
    if (_ram.value.trim().isNotEmpty) 'ram': _ram.value.trim().toUpperCase(),
    if (_cores.value.trim().isNotEmpty) 'cpu_cores': _cores.value.trim(),
    if (_disk.value.trim().isNotEmpty)
      'disk_size': _disk.value.trim().toUpperCase(),
    if (_viewer.isNotEmpty) 'viewer': _viewer,
    ..._profile.extraConf,
  };

  Future<void> _pickOs() async {
    final selection = await Navigator.of(context).push<OperatingSystem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const OperatingSystemSelection(),
      ),
    );
    if (selection == null) return;
    setState(() {
      _os = selection;
      _profile = recommendedProfileFor(selection.code);
      _ram = SizeInput.pure(_profile.ram.isEmpty ? '4G' : _profile.ram, true);
      _cores = CpuCoresInput.pure(_profile.cpuCores);
      _disk = SizeInput.pure(
        _profile.diskSize.isEmpty ? '64G' : _profile.diskSize,
        true,
      );
      if (selection.versions.length == 1 &&
          selection.versions.first.options.length == 1) {
        _version = selection.versions.first;
        _option = selection.versions.first.options.first;
      } else {
        _version = null;
        _option = null;
      }
    });
  }

  Future<void> _pickVersion() async {
    if (_os == null) return;
    final selection = await Navigator.of(context)
        .push<Tuple2<Version, Option?>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => VersionSelection(operatingSystem: _os!),
          ),
        );
    if (selection == null) return;
    setState(() {
      _version = selection.item1;
      _option = selection.item2;
    });
  }

  Future<void> _finish() async {
    if (_import) {
      _importDone = true;
      await importImageWithPicker(context, ref);
      return;
    }
    final dir =
        await ref
            .read(preferencesRepositoryProvider)
            .getAs<String>(prefWorkingDirectory) ??
        Directory.current.path;
    if (!await ref.read(hostProbeProvider).canWriteToDirectory(dir)) {
      if (!mounted) return;
      await _error('Could not write to the working directory.');
      return;
    }
    final free = await ref.read(hostProbeProvider).freeSpaceBytes(dir);
    if (!mounted) return;
    if (free != null && free < _lowSpaceBytes) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Low disk space')),
          content: Text(
            context.t(
              'Only {0} is free in the working directory.',
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
      if (!mounted) return;
    }
    setState(() => _checking = true);
    final check = await ref.read(backendProvider).runQuickget([
      '--check',
      _os!.code,
      _version!.version,
      if (_option != null && _option!.option.isNotEmpty) _option!.option,
    ]);
    if (mounted) setState(() => _checking = false);
    if (!mounted) return;
    if (check.exitCode != 0) {
      await _error('The selected image is currently unavailable.');
      return;
    }
    ref
        .read(downloadTasksProvider)
        .start(
          os: _os!.code,
          release: _version!.version,
          edition: _option?.option ?? '',
          configuration: _confOverrides,
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

  Future<void> _error(String message) => showDialog<void>(
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

  @override
  Widget build(BuildContext context) {
    final steps = [
      _originStep(),
      _systemStep(),
      _resourcesStep(),
      _integrationStep(),
      _reviewStep(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Create a virtual machine'))),
      body: Stepper(
        currentStep: _step,
        onStepContinue: () {
          if (_step == steps.length - 1) {
            _finish();
          } else if (_stepValid(_step)) {
            setState(() => _step++);
          }
        },
        onStepCancel: _step == 0 ? null : () => setState(() => _step--),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              FilledButton(
                onPressed: _checking || !_stepValid(_step)
                    ? null
                    : details.onStepContinue,
                child: Text(
                  _step == steps.length - 1
                      ? context.t('Create')
                      : context.t('Continue'),
                ),
              ),
              const SizedBox(width: 8),
              if (details.onStepCancel != null)
                TextButton(
                  onPressed: details.onStepCancel,
                  child: Text(context.t('Back')),
                ),
            ],
          ),
        ),
        steps: steps,
      ),
    );
  }

  Step _originStep() => Step(
    title: Text(context.t('Origin')),
    content: RadioGroup<bool>(
      groupValue: _import,
      onChanged: (v) => setState(() => _import = v ?? false),
      child: Column(
        children: [
          RadioListTile<bool>(
            title: Text(context.t('Download with quickget')),
            subtitle: Text(context.t('Pick an image from the catalogue')),
            value: false,
          ),
          RadioListTile<bool>(
            title: Text(context.t('Import a disk image')),
            subtitle: Text(context.t('ISO, qcow2, vdi, vmdk, vhdx or raw')),
            value: true,
          ),
        ],
      ),
    ),
  );

  Step _systemStep() => Step(
    title: Text(context.t('System')),
    content: _import
        ? Text(
            _importDone
                ? context.t('Image imported — continue to review.')
                : context.t('You will pick the disk image at the end.'),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.computer),
                title: Text(context.t('Operating system')),
                subtitle: Text(_os?.name ?? context.t('Select...')),
                onTap: _pickOs,
              ),
              ListTile(
                leading: const Icon(Icons.tag),
                title: Text(context.t('Version')),
                subtitle: Text(
                  _version == null
                      ? context.t('Select...')
                      : '${_version!.version}'
                            '${(_option?.option ?? '').isNotEmpty ? ' (${_option!.option})' : ''}',
                ),
                onTap: _pickVersion,
              ),
            ],
          ),
  );

  Step _resourcesStep() => Step(
    title: Text(context.t('Resources')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _profile.id,
          decoration: InputDecoration(labelText: context.t('Profile')),
          items: [
            for (final p in vmProfiles)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (id) {
            if (id == null) return;
            final p = vmProfiles.firstWhere((e) => e.id == id);
            setState(() {
              _profile = p;
              if (p.id != 'custom') {
                _ram = SizeInput.pure(p.ram.isEmpty ? '4G' : p.ram, true);
                _cores = CpuCoresInput.pure(p.cpuCores);
                _disk = SizeInput.pure(
                  p.diskSize.isEmpty ? '64G' : p.diskSize,
                  true,
                );
              }
            });
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('w-ram-${_profile.id}'),
          initialValue: _ram.value,
          onChanged: (v) => setState(() => _ram = SizeInput.dirty(v, true)),
          decoration: InputDecoration(
            labelText: context.t('RAM'),
            errorText: context.sizeError(_ram.displayError),
          ),
        ),
        TextFormField(
          key: ValueKey('w-cores-${_profile.id}'),
          initialValue: _cores.value,
          onChanged: (v) => setState(() => _cores = CpuCoresInput.dirty(v)),
          decoration: InputDecoration(
            labelText: context.t('CPU cores'),
            errorText: context.cpuCoresError(_cores.displayError),
          ),
        ),
        TextFormField(
          key: ValueKey('w-disk-${_profile.id}'),
          initialValue: _disk.value,
          onChanged: (v) => setState(() => _disk = SizeInput.dirty(v, true)),
          decoration: InputDecoration(
            labelText: context.t('Disk size'),
            errorText: context.sizeError(_disk.displayError),
          ),
        ),
      ],
    ),
  );

  Step _integrationStep() => Step(
    title: Text(context.t('Integration')),
    content: Column(
      children: [
        SwitchListTile(
          title: Text(context.t('Start the machine after creation')),
          value: _startAfter,
          onChanged: (v) => setState(() => _startAfter = v),
        ),
        ListTile(
          title: Text(context.t('Display viewer')),
          trailing: DropdownButton<String>(
            value: _viewer,
            items: [
              DropdownMenuItem(value: '', child: Text(context.t('Automatic'))),
              const DropdownMenuItem(value: 'spicy', child: Text('spicy')),
              const DropdownMenuItem(
                value: 'remote-viewer',
                child: Text('remote-viewer'),
              ),
              const DropdownMenuItem(value: 'none', child: Text('none')),
            ],
            onChanged: (v) => setState(() => _viewer = v ?? ''),
          ),
        ),
      ],
    ),
  );

  Step _reviewStep() => Step(
    title: Text(context.t('Review')),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_import)
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(context.t('Import a disk image')),
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.download),
            title: Text(
              '${_os?.name ?? ''} ${_version?.version ?? ''}'
              '${(_option?.option ?? '').isNotEmpty ? ' (${_option!.option})' : ''}',
            ),
            subtitle: Text(_profile.name),
          ),
          for (final e in _confOverrides.entries)
            Text('  ${e.key} = ${e.value}'),
        ],
      ],
    ),
  );
}
