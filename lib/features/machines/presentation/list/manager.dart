import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as path;
import 'package:quickgui/shared/providers/preferences_providers.dart';
import 'package:quickgui/features/diagnostics/application/ports/host_probe.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/presentation/shared/new_vm_tag.dart';
import 'package:version/version.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/machines/application/delete_vm.dart';
import 'package:quickgui/features/machines/application/inspect_vm.dart';
import 'package:quickgui/features/machines/application/list_vms.dart';
import 'package:quickgui/features/machines/application/start_vm.dart';
import 'package:quickgui/features/machines/application/stop_vm.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/domain/vminfo.dart';
import 'package:quickgui/features/machines/presentation/details/vm_config_editor.dart';
import 'package:quickgui/features/machines/presentation/details/vm_details_pane.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/shared/dialogs/validated_text_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

/// VM manager page.
/// Displays a list of available VMs, running state and connection info,
/// with buttons to start and stop VMs.
class Manager extends ConsumerStatefulWidget {
  const Manager({super.key});

  @override
  ConsumerState<Manager> createState() => _ManagerState();
}

class _ManagerState extends ConsumerState<Manager> with WidgetsBindingObserver {
  VirtualizationBackend get _backend => ref.read(backendProvider);
  HostProbe get _probe => ref.read(hostProbeProvider);
  PreferencesRepository get _prefs => ref.read(preferencesRepositoryProvider);

  List<String> _currentVms = [];
  String _vmFilter = '';
  String _vmSort = 'name';
  Map<String, String> _vmConfFiles = {};
  Map<String, VmInfo> _activeVms = {};
  Map<String, String> _vmStates = {};
  String? _selectedVm;
  // Conf values for the details pane, cached in _getVms so no file IO
  // happens inside build().
  final Map<String, Map<String, String?>> _vmDetails = {};
  static const _detailKeys = [
    'guest_os',
    'ram',
    'cpu_cores',
    'disk_size',
    'boot',
    'network',
    'display',
    'viewer',
  ];
  bool _spicy = false;
  bool _hasKvm = true;
  Map<String, dynamic>? _backendCaps;
  final List<String> _sshVms = [];
  String? _terminalEmulator;
  Timer? refreshTimer;
  List<String> _newVmNames = <String>[];

  @override
  void initState() {
    super.initState();
    _getTerminalEmulator();
    _detectSpice();
    _setNewVmName();
    _prefs.getAs<String>(prefWorkingDirectory).then((pref) async {
      if (!mounted) return;
      final writable = await _probe.canWriteToDirectory(Directory.current.path);
      if (!mounted) return;
      setState(() {
        if (pref != null && Directory(pref).existsSync()) {
          Directory.current = pref;
        } else if (!writable) {
          Directory.current = _probe.fallbackWorkingDirectory;
        }
      });
      Future.delayed(
        Duration.zero,
        _getVms,
      ); // Reload VM list when we enter the page.
    });
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) {
      _getVms();
    }); // Reload VM list every 5 seconds.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the periodic VM scan while the window is not visible.
    if (state == AppLifecycleState.resumed) {
      _getVms();
      refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (Timer t) {
        _getVms();
      });
    } else {
      refreshTimer?.cancel();
      refreshTimer = null;
    }
  }

  Future<void> _setNewVmName() async {
    _newVmNames =
        await _prefs.getAs<List<String>>(prefNewlyInstalledVms) ?? <String>[];
    // Delete prefNewlyInstalledVms to only display once
    _prefs.set(prefNewlyInstalledVms, <String>[]);
  }

  void _getTerminalEmulator() async {
    final terminal = await _probe.terminalEmulator();
    if (terminal != null && mounted) {
      setState(() {
        _terminalEmulator = terminal;
      });
    }
  }

  void _detectSpice() async {
    final spicy = await _probe.hasTool('spicy');
    final kvm = await _probe.hasKvm();
    if (!mounted) return;
    setState(() {
      _spicy = spicy;
      _hasKvm = kvm;
    });
  }

  /// Edits one or more `key="value"` entries of a VM .conf file.
  /// [title] names the purpose of the dialog (e.g. 'Resources') so the
  /// user sees a semantic heading instead of the raw .conf filename.
  Future<void> _editVmConfValues(
    String currentVm,
    Map<String, String> keys, {
    required String title,
    Map<String, List<String>>? options,
  }) async {
    final confPath = _vmConfFiles[currentVm] ?? '$currentVm.conf';
    final file = File(confPath);
    final lines = file.existsSync() ? await file.readAsLines() : <String>[];
    final controllers = <String, TextEditingController>{};
    for (final key in keys.keys) {
      final re = RegExp('^$key="(.*)"');
      var current = '';
      for (final l in lines) {
        final m = re.firstMatch(l);
        if (m != null) current = m.group(1)!;
      }
      controllers[key] = TextEditingController(text: current);
    }
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title — $currentVm'),
        content: SizedBox(
          width: double.maxFinite,
          // Scrollable: the 16-field "Settings (all)" dialog must stay
          // usable at the minimum window height (~800px).
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: keys.entries.map((e) {
                final opts = options?[e.key];
                final current = controllers[e.key]!.text;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: opts == null
                      ? TextField(
                          controller: controllers[e.key],
                          decoration: InputDecoration(labelText: e.value),
                        )
                      : DropdownButtonFormField<String>(
                          // Keep the current value as an extra item when it
                          // is not one of the known options — picking
                          // opts.first would silently rewrite the .conf on OK.
                          initialValue: current.isEmpty ? null : current,
                          decoration: InputDecoration(labelText: e.value),
                          items: {...opts, if (current.isNotEmpty) current}
                              .map(
                                (o) =>
                                    DropdownMenuItem(value: o, child: Text(o)),
                              )
                              .toList(),
                          onChanged: (v) => controllers[e.key]!.text = v ?? '',
                        ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('OK')),
          ),
        ],
      ),
    );
    if (result != true) return;
    for (final key in keys.keys) {
      final value = controllers[key]!.text;
      final re = RegExp('^$key="');
      var replaced = false;
      for (var i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) {
          lines[i] = '$key="$value"';
          replaced = true;
          break;
        }
      }
      if (!replaced) lines.add('$key="$value"');
    }
    await file.writeAsString('${lines.join('\n')}\n');
  }

  /// 'YYYY-MM-DD HH:MM' from the contract's unix timestamp; '' when
  /// the backend did not provide one.
  static String _formatSnapshotDate(dynamic date) {
    if (date is! num) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch((date * 1000).round())
        .toLocal();
    final s = dt.toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  void _manageSnapshot(BuildContext context, String currentVm) async {
    // Expose quickemu's --snapshot apply/create/delete/info actions.
    // Load the existing snapshots first (v1 vm-snapshots contract) so
    // the dialog can list them like VirtualBox/Boxes do.
    final confPath = _vmConfFiles[currentVm] ?? '$currentVm.conf';
    final snapshots = await _backend.listSnapshots(confPath);
    if (!context.mounted) return;
    final tagController = TextEditingController();
    final selection = await showDialog<({String action, String tag})>(
      context: context,
      builder: (context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: tagController,
        builder: (context, value, _) {
          final tag = value.text.trim();
          return AlertDialog(
            title: Text(context.t('Snapshots {0}', args: [currentVm])),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshots.isNotEmpty) ...[
                  Text(
                    context.t('Existing snapshots'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  // Fixed size: a shrink-wrap ListView breaks the
                  // AlertDialog intrinsic-dimension pass.
                  SizedBox(
                    height: snapshots.length.clamp(1, 4) * 48.0,
                    width: 360,
                    child: ListView(
                      children: [
                        for (final s in snapshots)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history),
                            title: Text('${s['name']}'),
                            subtitle: Text(_formatSnapshotDate(s['date'])),
                            onTap: () => tagController.text = '${s['name']}',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: tagController,
                  decoration: InputDecoration(
                    hintText: context.t('Snapshot tag'),
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
                    Navigator.of(context).pop((action: 'info', tag: '')),
                child: Text(context.t('Info')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'create', tag: tag)),
                child: Text(context.t('Create')),
              ),
              TextButton(
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'apply', tag: tag)),
                child: Text(context.t('Apply')),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: tag.isEmpty
                    ? null
                    : () =>
                          Navigator.of(context)
                              .pop((action: 'delete', tag: tag)),
                child: Text(context.t('Delete')),
              ),
            ],
          );
        },
      ),
    );
    if (selection == null) return;
    // Applying a snapshot replaces the current disk state and deleting
    // removes it permanently — both need an explicit confirmation.
    if (selection.action == 'apply' || selection.action == 'delete') {
      if (!context.mounted) return;
      final isDelete = selection.action == 'delete';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            isDelete
                ? context.t('Delete snapshot {0}', args: [selection.tag])
                : context.t('Apply snapshot {0}', args: [selection.tag]),
          ),
          content: Text(
            isDelete
                ? context.t(
                    'The snapshot {0} of {1} will be permanently deleted. This cannot be undone.',
                    args: [selection.tag, currentVm],
                  )
                : context.t(
                    'The current state of {0} will be replaced by the snapshot {1}. This cannot be undone.',
                    args: [currentVm, selection.tag],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: isDelete
                  ? Text(context.t('Delete'))
                  : Text(context.t('Apply')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final results = await _backend.runAction([
      '--vm',
      confPath,
      '--snapshot',
      selection.action,
      if (selection.tag.isNotEmpty) selection.tag,
    ]);
    if (!mounted) return;
    _showProcessOutput([results]);
  }

  void _confirmDeleteVm(BuildContext context, String currentVm) async {
    // Preview what will be deleted via the backend's safe delete plan.
    final planResult = await DeleteVm(_backend).plan(currentVm);
    var planText = switch (planResult) {
      Ok<List<String>>(value: final v) when v.isNotEmpty => v.join('\n'),
      _ => '',
    };
    if (planText.isEmpty) {
      // Backends without a delete plan still need to show exactly what is
      // about to be removed: the .conf plus every file in the VM folder.
      final paths = <String>[
        _vmConfFiles[currentVm] ?? '$currentVm.conf',
        if (Directory(currentVm).existsSync())
          ...Directory(currentVm).listSync(recursive: true).map((e) => e.path),
      ]..sort();
      planText = paths.join('\n');
    }
    if (!context.mounted) return;
    showDialog<String?>(
      context: context,
      builder: (BuildContext context) {
        final error = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: error),
              const SizedBox(width: 8),
              Flexible(child: Text(context.t('Delete {0}', args: [currentVm]))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(
                  'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?',
                  args: [currentVm],
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    planText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
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
    ).then((result) async {
      result = result ?? 'cancel';
      if (result != 'cancel') {
        final List<String> command = [
          'quickemu',
          '--vm',
          '$currentVm.conf',
          '--delete-$result',
        ];
        await _backend.runAction(command.sublist(1));
      }
    });
  }

  void _cloneVm(BuildContext context, String currentVm) async {
    final name = await showValidatedTextDialog<VmNameError>(
      context: context,
      title: context.t('Clone {0}', args: [currentVm]),
      label: context.t('New VM name'),
      confirmLabel: context.t('Clone'),
      initialValue: '$currentVm-copy',
      dirty: VmNameInput.dirty,
      message: (context, e) => context.vmNameError(e),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final r = await _backend.runAction([
      '--vm',
      _vmConfFiles[currentVm] ?? '$currentVm.conf',
      '--clone',
      name,
    ]);
    if (!mounted) return;
    _showProcessOutput([r]);
    _getVms();
  }

  Future<void> _startVm(String currentVm) async {
    final Map<String, VmInfo> activeVms = _activeVms;
    final List<String> command = ['quickemu', '--vm', '$currentVm.conf'];
    // Respect a display= setting in the .conf; fall back
    // to the SPICE toggle.
    final confDisplay = ref
        .read(vmConfigStoreProvider)
        .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'display');
    if (confDisplay != null && confDisplay.isNotEmpty) {
      if (confDisplay != 'none') {
        command.addAll(['--display', confDisplay]);
      }
    } else if (_spicy) {
      command.addAll(['--display', 'spice']);
    }
    final startResult = await StartVm(_backend)(
      currentVm,
      display: command.contains('--display')
          ? command[command.indexOf('--display') + 1]
          : null,
    );
    if (!mounted) return;
    if (startResult is Err) {
      _showProcessOutput([
        ProcessResult(0, 1, '', startResult.failure.message),
      ]);
    }
    final VmInfo info = _parseVmInfo(currentVm);
    activeVms[currentVm] = info;
    setState(() {
      _activeVms = activeVms;
      _vmStates[currentVm] = 'running';
    });
  }

  Future<void> _stopVm(String currentVm) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final error = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: Text(context.t('Stop {0}', args: [currentVm])),
          content: Text(
            context.t(
              'Shut down {0} gracefully, or force it to stop? Forcing discards unsaved changes in the guest.',
              args: [currentVm],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: Text(context.t('Cancel')),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: error),
              onPressed: () => Navigator.pop(context, 'kill'),
              child: Text(context.t('Force stop')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'shutdown'),
              child: Text(context.t('Shut down')),
            ),
          ],
        );
      },
    );
    if (choice == 'shutdown') {
      // ACPI powerdown via the QEMU monitor socket; the
      // VM keeps running until the guest OS finishes.
      final r = await _backend.runAction([
        '--vm',
        _vmConfFiles[currentVm] ?? '$currentVm.conf',
        '--monitor-cmd',
        'system_powerdown',
      ]);
      if (!mounted) return;
      _showProcessOutput([r]);
    } else if (choice == 'kill') {
      // If Quickemu is newer than 4.9.6, use the new --kill option
      // which is macOS compatible.
      final quickemuVersion = Version.parse(await _backend.version());
      if (quickemuVersion >= Version(4, 9, 6)) {
        StopVm(_backend)(currentVm);
      } else {
        unawaited(_backend.killVmProcess(currentVm));
      }
      setState(() {
        _activeVms.remove(currentVm);
        _vmStates[currentVm] = 'stopped';
      });
    }
  }

  void _editVmSettings(String currentVm) {
    _editVmConfValues(
      currentVm,
      title: context.t('Settings (all)'),
      {
        'guest_os': context.t('Guest OS'),
        'ram': context.t('RAM'),
        'cpu_cores': context.t('CPU cores'),
        'disk_size': context.t('Disk size'),
        'boot': context.t('Boot mode'),
        'network': context.t('Network'),
        'macaddr': context.t('MAC address'),
        'secureboot': context.t('Secure boot'),
        'tpm': context.t('TPM'),
        'usb_devices': context.t('USB devices'),
        'gpu_passthrough': context.t('GPU passthrough'),
        'port_forwards': context.t('Port forwards'),
        'public_dir': context.t('Shared folder'),
        'viewer': context.t('Display viewer'),
        'display': context.t('Display'),
        'sound': context.t('Sound'),
      },
      options: {
        'boot': ['efi', 'legacy'],
        'network': ['nat', 'restrict', 'bridged', 'none'],
        'secureboot': ['on', 'off'],
        'tpm': ['on', 'off'],
        'viewer': ['spicy', 'remote-viewer', 'none'],
      },
    );
  }

  void _resizeVmDisk(BuildContext context, String currentVm) async {
    // Prefill with the current size so the user knows what they grow from.
    final currentSize =
        ref
            .read(vmConfigStoreProvider)
            .read(_vmConfFiles[currentVm] ?? '$currentVm.conf', 'disk_size') ??
        '64G';
    if (!context.mounted) return;
    final size = await showValidatedTextDialog<SizeError>(
      context: context,
      title: context.t('Resize disk of {0}', args: [currentVm]),
      label: context.t(
        'New size (current: {0}, grow only)',
        args: [currentSize],
      ),
      confirmLabel: context.t('Resize'),
      initialValue: currentSize,
      dirty: SizeInput.dirty,
      message: (context, e) => context.sizeError(e),
    );
    if (size == null || size.isEmpty || !mounted) return;
    final r = await _backend.runAction([
      '--vm',
      _vmConfFiles[currentVm] ?? '$currentVm.conf',
      '--disk-resize',
      size,
    ]);
    if (!mounted) return;
    _showProcessOutput([r]);
  }

  void _showProcessOutput(List<ProcessResult> results) {
    final output = results
        .map((r) => '${r.stdout}${r.stderr}')
        .where((s) => s.trim().isNotEmpty)
        .join('\n')
        .trim();
    if (output.isEmpty) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Command output')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              output,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('Dismiss')),
          ),
        ],
      ),
    );
  }

  VmInfo _parseVmInfo(String name) {
    final VmInfo info = VmInfo();
    final File portsFile = File('$name/$name.ports');
    if (portsFile.existsSync()) {
      final List<String> lines = portsFile.readAsLinesSync();
      for (final line in lines) {
        final List<String> parts = line.split(',');
        switch (parts[0]) {
          case 'ssh':
            info.sshPort = parts[1];
          case 'spice':
            info.spicePort = parts[1];
          default:
            info.other.add(parts.sublist(1).join(','));
        }
      }
    }
    return info;
  }

  bool _isValidConf(String conf) {
    final List<String> lines = File(conf).readAsLinesSync();
    for (final line in lines) {
      final List<String> parts = line.split('=');
      if (parts[0] == 'guest_os') {
        return true;
      }
    }
    return false;
  }

  void _getVms() async {
    final List<String> currentVms = [];
    final Map<String, String> vmConfFiles = {};
    final Map<String, VmInfo> activeVms = {};
    final Map<String, String> vmStates = {};

    // Prefer the structured backend contract when the installed
    // quickemu advertises it; fall back to the pid-file scan otherwise.
    _backendCaps ??= await _backend.getCapabilities();
    final Map<String, String> backendStates = {};
    final caps = _backendCaps?['capabilities'];
    if (caps is Map && caps['structuredStatus'] == true) {
      for (final name in switch (await ListVms(_backend)()) {
        Ok(:final value) => value,
        Err() => const <String>[],
      }) {
        final inspected = await InspectVm(_backend)(name);
        if (inspected case Ok(:final value)) {
          backendStates[name] = '${value['state']}';
        }
      }
    }

    // listSync instead of the async stream: the sync call also works inside
    // testWidgets/FakeAsync, where real async IO never gets drained.
    for (final entity in Directory.current.listSync()) {
      if ((entity.path.endsWith('.conf')) && (_isValidConf(entity.path))) {
        final String name = path.basenameWithoutExtension(entity.path);
        currentVms.add(name);
        vmConfFiles[name] = entity.path;
        var running = backendStates[name] == 'running';
        var state = backendStates[name] ?? 'stopped';
        if (backendStates.isEmpty) {
          final File pidFile = File('$name/$name.pid');
          if (pidFile.existsSync()) {
            final String pid = pidFile.readAsStringSync().trim();
            // Check if the process is still running using kill -0, which is
            // a portable way to check if a process is running on macOS and Linux.
            final ProcessResult result = Process.runSync('kill', ['-0', pid]);
            running = result.exitCode == 0;
            // A pid file with a dead process means the VM crashed or was
            // killed outside the app — surface it instead of "stopped".
            state = running ? 'running' : 'stale';
          } else {
            state = 'stopped';
          }
        }
        if (running) {
          if (_activeVms.containsKey(name)) {
            activeVms[name] = _activeVms[name]!;
          } else {
            activeVms[name] = _parseVmInfo(name);
          }
        }
        vmStates[name] = state;
        final store = ref.read(vmConfigStoreProvider);
        _vmDetails[name] = {
          for (final k in _detailKeys) k: store.read(entity.path, k),
        };
      }
    }
    // Surface VMs the backend knows about that our scan missed
    // (e.g. conf outside CWD or naming edge cases).
    for (final name in backendStates.keys) {
      if (!currentVms.contains(name) &&
          backendStates[name] == 'running' &&
          File('$name.conf').existsSync()) {
        currentVms.add(name);
        vmConfFiles[name] = '$name.conf';
        activeVms[name] = _parseVmInfo(name);
      }
    }
    currentVms.sort();
    if (!mounted) return;
    setState(() {
      _currentVms = currentVms;
      _vmConfFiles = vmConfFiles;
      _activeVms = activeVms;
      _vmStates = vmStates;
      _vmDetails.removeWhere((name, _) => !currentVms.contains(name));
      if (_selectedVm == null || !currentVms.contains(_selectedVm)) {
        _selectedVm = currentVms.isEmpty ? null : currentVms.first;
      }
    });
  }

  Future<bool> _detectSsh(int port) async {
    bool isSSH = false;
    try {
      final Socket socket = await Socket.connect('localhost', port);
      isSSH = await socket.any((event) => utf8.decode(event).contains('SSH'));
      socket.close();
      return isSSH;
    } catch (exception) {
      return false;
    }
  }

  Widget _buildVmList() {
    final List<Widget> widgetList = [];
    final Color buttonColor = Theme.of(context).colorScheme.primary;
    if (!_hasKvm) {
      widgetList.add(
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              context.t(
                'Hardware virtualisation (/dev/kvm) is not available; VMs will run slowly.',
              ),
            ),
          ),
        ),
      );
    }
    widgetList.addAll([
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              "${context.t('Directory where the machines are stored')}:",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: () async {
                final folder = await FilePicker.getDirectoryPath(
                  dialogTitle: "Pick a folder",
                );
                if (folder != null) {
                  setState(() {
                    Directory.current = folder;
                  });
                  _prefs.set(prefWorkingDirectory, Directory.current.path);
                }
              },
              child: Text(Directory.current.path),
            ),
          ],
        ),
      ),
      const Divider(thickness: 2),
      Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: TextField(
          decoration: InputDecoration(
            hintText: context.t('Search virtual machine'),
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (value) {
            setState(() {
              _vmFilter = value;
            });
          },
        ),
      ),
    ]);
    final filteredVms = _currentVms
        .where((vm) => vm.toLowerCase().contains(_vmFilter.toLowerCase()))
        .toList();
    if (_vmSort == 'running') {
      filteredVms.sort(
        (a, b) => (_activeVms.containsKey(b) ? 1 : 0).compareTo(
          _activeVms.containsKey(a) ? 1 : 0,
        ),
      );
    }
    final List<List<Widget>> rows = filteredVms.map((vm) {
      return _buildRow(vm, buttonColor);
    }).toList();
    for (final row in rows) {
      widgetList.addAll(row);
    }

    return ListView(padding: const EdgeInsets.all(16.0), children: widgetList);
  }

  List<Widget> _buildRow(String currentVm, Color buttonColor) {
    final bool active = _activeVms.containsKey(currentVm);
    final bool sshy = _sshVms.contains(currentVm);
    final bool newVM = _newVmNames.contains(currentVm);

    VmInfo vmInfo = VmInfo();
    String connectInfo = '';
    if (active) {
      vmInfo = _activeVms[currentVm]!;
      if (vmInfo.spicePort != null) {
        connectInfo += '${context.t('SPICE port')}: ${vmInfo.spicePort!} ';
      }
      if (vmInfo.sshPort != null && _terminalEmulator != null) {
        connectInfo += '${context.t('SSH port')}: ${vmInfo.sshPort!} ';
        _detectSsh(int.parse(vmInfo.sshPort!)).then((sshRunning) {
          if (sshRunning && !sshy) {
            setState(() {
              _sshVms.add(currentVm);
            });
          } else if (!sshRunning && sshy) {
            setState(() {
              _sshVms.remove(currentVm);
            });
          }
        });
      }
      for (final extra in vmInfo.other) {
        connectInfo += '$extra ';
      }
    }
    String vmStem = currentVm;
    SvgPicture? osIcon;
    while (vmStem.contains('-')) {
      vmStem = vmStem.substring(0, vmStem.lastIndexOf('-'));
      if (ref.read(osIconsProvider).containsKey(vmStem)) {
        osIcon = SvgPicture.asset(
          ref.read(osIconsProvider)[vmStem]!,
          width: 32,
          height: 32,
        );
        break;
      }
    }
    return <Widget>[
      ListTile(
        selected: currentVm == _selectedVm,
        onTap: () => setState(() => _selectedVm = currentVm),
        leading: osIcon ?? const Icon(Icons.computer, size: 32),
        subtitle: Text(
          switch (_vmStates[currentVm] ?? 'stopped') {
            'running' => context.t('Running'),
            'paused' => context.t('Paused'),
            'stale' => context.t('Stale (process exited unexpectedly)'),
            _ => context.t('Stopped'),
          },
          style: TextStyle(
            fontSize: 12,
            color: switch (_vmStates[currentVm]) {
              'running' => Colors.green,
              'paused' => Theme.of(context).colorScheme.tertiary,
              'stale' => Theme.of(context).colorScheme.error,
              _ => Theme.of(context).colorScheme.onSurfaceVariant,
            },
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(currentVm, overflow: TextOverflow.ellipsis)),
            if (newVM) const NewVmTag() else const SizedBox.shrink(),
            if (File('$currentVm/virtio-win.iso').existsSync() ||
                File('$currentVm/unattended.iso').existsSync())
              Tooltip(
                message: context.t(
                  'VirtIO drivers / unattended install present',
                ),
                child: const Icon(Icons.download_done, size: 18),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              icon: Icon(
                active ? Icons.play_arrow : Icons.play_arrow_outlined,
                color: active ? Colors.green : buttonColor,
                semanticLabel: active ? 'Running' : 'Run',
              ),
              tooltip: active
                  ? context.t('Running')
                  : context.t('Start the virtual machine'),
              onPressed: active ? null : () => _startVm(currentVm),
            ),
            IconButton(
              icon: Icon(
                active ? Icons.stop : Icons.stop_outlined,
                color: active ? Colors.red : null,
                semanticLabel: active ? 'Stop' : 'Not running',
              ),
              tooltip: active
                  ? context.t('Shut down or stop the virtual machine')
                  : context.t('Not running'),
              onPressed: !active ? null : () => _stopVm(currentVm),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, semanticLabel: 'More actions'),
              tooltip: context.t('More actions'),
              // Keep the menu inside the window: with ~17 items it exceeds
              // 800px and traps "Delete" below the fold.
              constraints: const BoxConstraints(maxHeight: 560),
              onSelected: (choice) async {
                switch (choice) {
                  case 'config':
                    showDialog<void>(
                      context: context,
                      builder: (context) => VmConfigEditorDialog(
                        vmName: currentVm,
                        confPath: _vmConfFiles[currentVm]!,
                      ),
                    );
                  case 'folder':
                    unawaited(_backend.openVmFolder(currentVm));
                  case 'snapshot':
                    _manageSnapshot(context, currentVm);
                  case 'shared':
                    _editVmConfValues(currentVm, {
                      'public_dir': context.t('Shared folder'),
                    }, title: context.t('Shared folder'));
                  case 'resources':
                    _editVmConfValues(currentVm, {
                      'ram': context.t('RAM (e.g. 4G)'),
                      'cpu_cores': context.t('CPU cores'),
                      'disk_size': context.t('Disk size (e.g. 64G)'),
                    }, title: context.t('Resources'));
                  case 'display':
                    _editVmConfValues(
                      currentVm,
                      {'viewer': context.t('Display viewer')},
                      title: context.t('Display viewer'),
                      options: {
                        'viewer': ['spicy', 'remote-viewer', 'none'],
                      },
                    );
                  case 'bootnet':
                    _editVmConfValues(
                      currentVm,
                      {
                        'boot': context.t('Boot mode'),
                        'network': context.t('Network'),
                        'macaddr': context.t('MAC address'),
                        'secureboot': context.t('Secure boot'),
                        'tpm': context.t('TPM'),
                      },
                      title: context.t('Boot & network'),
                      options: {
                        'boot': ['efi', 'legacy'],
                        'network': ['nat', 'restrict', 'bridged', 'none'],
                        'secureboot': ['on', 'off'],
                        'tpm': ['on', 'off'],
                      },
                    );
                  case 'devices':
                    _editVmConfValues(currentVm, {
                      'usb_devices': context.t('USB devices'),
                      'gpu_passthrough': context.t('GPU passthrough'),
                      'port_forwards': context.t('Port forwards'),
                      'sound': context.t('Sound'),
                      'display': context.t('Display'),
                    }, title: context.t('Devices'));
                  case 'pause':
                    await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--pause',
                    ]);
                  case 'resume':
                    await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--resume',
                    ]);
                  case 'screenshot':
                    final r = await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--screenshot',
                    ]);
                    if (!context.mounted) return;
                    _showProcessOutput([r]);
                  case 'send-keys':
                    final r = await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--send-keys',
                      'ctrl-alt-delete',
                    ]);
                    if (!context.mounted) return;
                    _showProcessOutput([r]);
                  case 'reset':
                    // QEMU monitor `system_reset` — equivalent to pressing
                    // the reset button: abrupt reboot, unsaved guest state
                    // may be lost, so confirm first.
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.t('Reset {0}?', args: [currentVm])),
                        content: Text(
                          context.t(
                            'The virtual machine reboots immediately. Unsaved guest state may be lost.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(context.t('Cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(context.t('Reset')),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    final resetResult = await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--monitor-cmd',
                      'system_reset',
                    ]);
                    if (!context.mounted) return;
                    _showProcessOutput([resetResult]);
                  case 'doctor':
                    final r = await _backend.runAction([
                      '--vm',
                      _vmConfFiles[currentVm] ?? '$currentVm.conf',
                      '--doctor',
                    ]);
                    if (!context.mounted) return;
                    _showProcessOutput([r]);
                  case 'resize':
                    _resizeVmDisk(context, currentVm);
                  case 'clone':
                    _cloneVm(context, currentVm);
                  case 'export':
                    // Export writes <vm>.tar.gz in the working directory —
                    // confirm before overwriting an existing archive.
                    if (File('$currentVm.tar.gz').existsSync()) {
                      final overwrite = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(
                            context.t(
                              'Replace {0}?',
                              args: ['$currentVm.tar.gz'],
                            ),
                          ),
                          content: Text(
                            context.t(
                              'The file already exists and will be overwritten.',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(context.t('Cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(context.t('Replace')),
                            ),
                          ],
                        ),
                      );
                      if (overwrite != true) return;
                    }
                    final r = await _backend.exportVm(currentVm);
                    if (!context.mounted) return;
                    _showProcessOutput([r]);
                  case 'settings':
                    _editVmSettings(currentVm);
                  case 'verify':
                    final iso = ref
                        .read(vmConfigStoreProvider)
                        .read(
                          _vmConfFiles[currentVm] ?? '$currentVm.conf',
                          'iso',
                        );
                    if (iso != null) {
                      final r = await _backend.verifyImage(iso);
                      if (!context.mounted) return;
                      _showProcessOutput([r]);
                    }
                  case 'delete':
                    _confirmDeleteVm(context, currentVm);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'config',
                  child: ListTile(
                    leading: const Icon(Icons.settings),
                    title: Text(context.t('Edit configuration')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'folder',
                  child: ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: Text(context.t('Open VM folder')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'snapshot',
                  child: ListTile(
                    leading: const Icon(Icons.photo_camera),
                    title: Text(context.t('Snapshots')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'shared',
                  child: ListTile(
                    leading: const Icon(Icons.folder_shared),
                    title: Text(context.t('Shared folder')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'resources',
                  child: ListTile(
                    leading: const Icon(Icons.memory),
                    title: Text(context.t('Resources')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'display',
                  child: ListTile(
                    leading: const Icon(Icons.display_settings),
                    title: Text(context.t('Display viewer')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'bootnet',
                  child: ListTile(
                    leading: const Icon(Icons.lan),
                    title: Text(context.t('Boot & network')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'devices',
                  child: ListTile(
                    leading: const Icon(Icons.developer_board),
                    title: Text(context.t('Devices')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'verify',
                  child: ListTile(
                    leading: const Icon(Icons.verified),
                    title: Text(context.t('Verify image')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (active)
                  PopupMenuItem(
                    value: 'pause',
                    child: ListTile(
                      leading: const Icon(Icons.pause),
                      title: Text(context.t('Pause')),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                else
                  PopupMenuItem(
                    value: 'resume',
                    child: ListTile(
                      leading: const Icon(Icons.play_circle),
                      title: Text(context.t('Resume')),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (active)
                  PopupMenuItem(
                    value: 'screenshot',
                    child: ListTile(
                      leading: const Icon(Icons.screenshot_monitor),
                      title: Text(context.t('Screenshot')),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (active)
                  PopupMenuItem(
                    value: 'send-keys',
                    child: ListTile(
                      leading: const Icon(Icons.keyboard),
                      title: Text(context.t('Send Ctrl+Alt+Del')),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (active)
                  PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      leading: const Icon(Icons.restart_alt),
                      title: Text(context.t('Reset')),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'doctor',
                  child: ListTile(
                    leading: const Icon(Icons.health_and_safety),
                    title: Text(context.t('Check VM')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'resize',
                  child: ListTile(
                    leading: const Icon(Icons.expand),
                    title: Text(context.t('Resize disk')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'clone',
                  child: ListTile(
                    leading: const Icon(Icons.content_copy),
                    title: Text(context.t('Clone')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: const Icon(Icons.archive),
                    title: Text(context.t('Export')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(context.t('Settings (all)')),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      context.t('Delete'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (connectInfo.isNotEmpty)
        ListTile(
          title: Text(connectInfo, style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                icon: Icon(
                  Icons.monitor,
                  color: (_spicy && vmInfo.spicePort != null)
                      ? buttonColor
                      : null,
                  semanticLabel: 'Connect display with SPICE',
                ),
                tooltip: _spicy
                    ? context.t('Connect display with SPICE')
                    : context.t('SPICE client not found'),
                onPressed: !_spicy || vmInfo.spicePort == null
                    ? null
                    : () {
                        unawaited(
                          _backend.launchSpiceViewer(vmInfo.spicePort!),
                        );
                      },
              ),
              IconButton(
                icon: SvgPicture.asset(
                  'assets/images/console.svg',
                  semanticsLabel: 'Connect with SSH',
                  colorFilter: ColorFilter.mode(
                    sshy ? buttonColor : Colors.grey,
                    BlendMode.srcIn,
                  ),
                ),
                tooltip: !sshy
                    ? context.t('SSH server not detected on guest')
                    : _terminalEmulator == null
                    ? context.t('No terminal emulator found')
                    : context.t('Connect with SSH'),
                onPressed: !sshy || _terminalEmulator == null
                    ? null
                    : () async {
                        final savedUser = await _prefs.getAs<String>(
                          'sshUser_$currentVm',
                        );
                        if (!mounted) return;
                        final TextEditingController
                        usernameController = TextEditingController(
                          text: savedUser ?? Platform.environment['USER'] ?? '',
                        );
                        showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(
                              context.t(
                                'Launch SSH connection to {0}',
                                args: [currentVm],
                              ),
                            ),
                            content: TextField(
                              controller: usernameController,
                              decoration: InputDecoration(
                                hintText: context.t("SSH username"),
                              ),
                            ),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  // Remove the stale known_hosts entry, e.g.
                                  // when a new guest reuses the SSH port of a
                                  // deleted VM.
                                  unawaited(
                                    _backend.forgetSshHostKey(vmInfo.sshPort!),
                                  );
                                },
                                child: Text(context.t('Forget host key')),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(context.t('Cancel')),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(context.t('Connect')),
                              ),
                            ],
                          ),
                        ).then((result) {
                          result = result ?? false;
                          if (result) {
                            _prefs.set(
                              'sshUser_$currentVm',
                              usernameController.text,
                            );
                            unawaited(
                              _backend.connectSsh(
                                terminalEmulator: _terminalEmulator!,
                                user: usernameController.text,
                                sshPort: vmInfo.sshPort!,
                              ),
                            );
                          }
                        });
                      },
              ),
            ],
          ),
        ),
      const Divider(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Manager')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: context.t('Sort'),
            onSelected: (v) => setState(() => _vmSort = v),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'name',
                child: Text(context.t('Sort by name')),
              ),
              PopupMenuItem(
                value: 'running',
                child: Text(context.t('Running first')),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final vm = _selectedVm;
          // Persistent details pane (VISTA S-01): at desktop widths it
          // shows the selected VM summary like VirtualBox/virt-manager;
          // under ~1000px the list keeps the full width as before.
          if (constraints.maxWidth < 1000 || vm == null) {
            return _buildVmList();
          }
          final state = _vmStates[vm] ?? 'stopped';
          final active = state == 'running' || state == 'paused';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _buildVmList()),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 6,
                child: VmDetailsPane(
                  name: vm,
                  state: state,
                  conf: _vmDetails[vm] ?? const {},
                  onStart: active ? null : () => _startVm(vm),
                  onStop: active ? () => _stopVm(vm) : null,
                  onConfigure: () => _editVmSettings(vm),
                  onSnapshots: () => _manageSnapshot(context, vm),
                  onDelete: () => _confirmDeleteVm(context, vm),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
