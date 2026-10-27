import 'dart:async';
import 'dart:core';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_actions_menu.dart';
import 'package:quickgui/features/machines/providers/vm_tags_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
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
import 'package:quickgui/features/machines/application/structured_or_legacy.dart';
import 'package:quickgui/features/machines/application/inspect_vm.dart';
import 'package:quickgui/features/machines/application/list_vms.dart';
import 'package:quickgui/features/machines/application/start_vm.dart';
import 'package:quickgui/features/machines/application/stop_vm.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/domain/vminfo.dart';
import 'package:quickgui/features/machines/presentation/details/vm_config_editor.dart';
import 'package:quickgui/features/machines/presentation/details/vm_details_pane.dart';
import 'package:quickgui/features/machines/domain/vm_config_value.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/shared/dialogs/validated_text_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

/// VM manager page.

part 'manager_actions.dart';
part 'manager_dialogs.dart';
part 'manager_rows.dart';

/// Displays a list of available VMs, running state and connection info,
/// with buttons to start and stop VMs.
class Manager extends ConsumerStatefulWidget {
  const Manager({super.key});

  @override
  ConsumerState<Manager> createState() => _ManagerState();
}

class _ManagerState extends ConsumerState<Manager> with WidgetsBindingObserver {
  VirtualizationBackend get _backend => ref.read(trackedBackendProvider);
  HostProbe get _probe => ref.read(hostProbeProvider);
  PreferencesRepository get _prefs => ref.read(preferencesRepositoryProvider);

  List<String> _currentVms = [];
  String _vmFilter = '';
  Timer? _searchDebounce;
  final _searchFocus = FocusNode(debugLabel: 'vm-search');
  String _vmSort = 'name';
  String _statusFilter = 'all';
  String? _tagFilter;
  bool _selectionMode = false;
  bool _batchBusy = false;
  bool _cards = false;
  final Set<String> _selection = {};
  DateTime? _refreshedAt;

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

  /// Feature-flag from `--capabilities` — a missing backend or an
  /// absent key means "assume supported" (legacy behaviour), an
  /// explicit `false` hides the action.
  bool _cap(String name) =>
      _backendCaps?['capabilities'] is! Map ||
      _backendCaps!['capabilities'][name] != false;
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
    _prefs.getAs<bool>(prefFirstRunHintShown).then((seen) {
      if (seen == true || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            context.t(
              'Welcome — pick an OS in Create, then manage your VMs here.',
            ),
          ),
        ),
      );
      _prefs.set(prefFirstRunHintShown, true);
    });
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
    _searchDebounce?.cancel();
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
    // Route through the config store — a single parser and the
    // fingerprint-aware read path, no raw file scans here.
    try {
      final value = ref.read(vmConfigStoreProvider).read(conf, 'guest_os');
      return value != null && value.isNotEmpty;
    } catch (_) {
      return false;
    }
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
            final int? pid = int.tryParse(pidFile.readAsStringSync().trim());
            // Ask the host probe whether the recorded process is still
            // alive (kill -0 on the host — works inside Flatpak too).
            running = pid != null && await _probe.isPidAlive(pid);
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
    // A migrated VM prefers its .toml - the backend consumes it when
    // both files exist, so every call must point at the newer format.
    for (final name in vmConfFiles.keys.toList()) {
      final toml = '$name.toml';
      if (File(toml).existsSync()) vmConfFiles[name] = toml;
    }
    currentVms.sort();
    if (!mounted) return;
    setState(() {
      _refreshedAt = DateTime.now();
      _selection.removeWhere((name) => !currentVms.contains(name));
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

  Future<bool> _detectSsh(int port) => _probe.isSshAlive(port);

  @override
  Widget build(BuildContext context) {
    // Keyboard shortcuts: Ctrl+F focuses search, Ctrl+N goes to the
    // creation wizard, Ctrl+R refreshes the library, Esc leaves
    // multi-select mode (keyboard a11y).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          if (GoRouter.maybeOf(context) != null) context.go('/create');
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _getVms,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selectionMode) {
            setState(() {
              _selectionMode = false;
              _selection.clear();
            });
          }
        },
      },
      child: FocusTraversalGroup(
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.t('Machines')),
            actions: [
              IconButton(
                tooltip: context.t('Select multiple'),
                icon: const Icon(Icons.checklist),
                onPressed: () => setState(() {
                  _selectionMode = !_selectionMode;
                  if (!_selectionMode) _selection.clear();
                }),
              ),
              IconButton(
                tooltip: context.t('Switch view'),
                icon: Icon(_cards ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _cards = !_cards),
              ),
              IconButton(
                tooltip: context.t('Edit tags'),
                icon: const Icon(Icons.label_outline),
                onPressed: _selectedVm == null
                    ? null
                    : () => _editTags([_selectedVm!]),
              ),
              IconButton(
                tooltip: _refreshedAt == null
                    ? context.t('Refresh')
                    : context.t(
                        'Last refreshed: {0}',
                        args: [
                          _refreshedAt!.toLocal().toString().substring(11, 19),
                        ],
                      ),
                icon: const Icon(Icons.refresh),
                onPressed: _getVms,
              ),
              IconButton(
                tooltip: context.t('Trash'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _showTrash,
              ),
              // At narrow widths or large text scales the labelled button
              // cannot fit next to the title and the other actions — fall
              // back to an icon with the same action and a tooltip.
              if (GoRouter.maybeOf(context) != null)
                if (MediaQuery.sizeOf(context).width < 850 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.5)
                  IconButton(
                    tooltip: context.t('New machine'),
                    icon: const Icon(Icons.add),
                    onPressed: () => context.go('/create'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: FilledButton.icon(
                      onPressed: () => context.go('/create'),
                      icon: const Icon(Icons.add),
                      label: Text(context.t('New machine')),
                    ),
                  ),
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
                      onOpenDetails: GoRouter.maybeOf(context) == null
                          ? null
                          : () => context.push(
                              '/machines/${Uri.encodeComponent(vm)}',
                            ),
                      onConfigure: () {
                        if (GoRouter.maybeOf(context) != null) {
                          context.push(
                            '/machines/${Uri.encodeComponent(vm)}/settings',
                          );
                        } else {
                          _editVmSettings(vm);
                        }
                      },
                      onSnapshots: () => _manageSnapshot(context, vm),
                      onDelete: () => _confirmDeleteVm(context, vm),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
