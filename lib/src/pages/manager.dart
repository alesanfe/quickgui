import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as path;
import 'package:process_run/shell.dart';
import 'package:quickgui/src/widgets/manager/new_vm_tag.dart';
import 'package:version/version.dart';

import '../globals.dart';
import '../mixins/preferences_mixin.dart';
import '../model/osicons.dart';
import '../model/vminfo.dart';
import '../pages/vm_config_editor.dart';

/// VM manager page.
/// Displays a list of available VMs, running state and connection info,
/// with buttons to start and stop VMs.
class Manager extends StatefulWidget {
  const Manager({super.key});

  @override
  State<Manager> createState() => _ManagerState();
}

class _ManagerState extends State<Manager>
    with PreferencesMixin, WidgetsBindingObserver {
  List<String> _currentVms = [];
  String _vmFilter = '';
  Map<String, String> _vmConfFiles = {};
  Map<String, VmInfo> _activeVms = {};
  bool _spicy = false;
  final List<String> _sshVms = [];
  String? _terminalEmulator;
  final List<String> _supportedTerminalEmulators = [
    if (Platform.isMacOS) 'osascript',
    'alacritty',
    'cool-retro-term',
    'foot',
    'gnome-terminal',
    'guake',
    'kgx',
    'kitty',
    'mate-terminal',
    'konsole',
    'lxterm',
    'lxterminal',
    'pterm',
    'sakura',
    'terminator',
    'tilix',
    'uxterm',
    'uxrvt',
    'wezterm',
    'xfce4-terminal',
    'xrvt',
    'xterm',
  ];
  Timer? refreshTimer;
  List<String> _newVmNames = <String>[];

  @override
  void initState() {
    super.initState();
    _getTerminalEmulator();
    _detectSpice();
    _setNewVmName();
    getPreference<String>(prefWorkingDirectory).then((pref) {
      if (!mounted) return;
      setState(() {
        if (pref != null && Directory(pref).existsSync()) {
          Directory.current = pref;
        } else if (!isWritableDirectory(Directory.current.path)) {
          Directory.current = fallbackWorkingDirectory();
        }
      });
      Future.delayed(
        Duration.zero,
        () => _getVms(),
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
        await getPreference<List<String>>(prefNewlyInstalledVms) ?? <String>[];
    // Delete prefNewlyInstalledVms to only display once
    savePreference(prefNewlyInstalledVms, <String>[]);
  }

  void _getTerminalEmulator() async {
    // Find out which terminal emulator we have set as the default.
    String result = whichSync('x-terminal-emulator') ?? '';
    if (result.isNotEmpty) {
      String terminalEmulator = await File(result).resolveSymbolicLinks();
      terminalEmulator = path.basenameWithoutExtension(terminalEmulator);
      if (_supportedTerminalEmulators.contains(terminalEmulator)) {
        setState(() {
          _terminalEmulator = path.basename(terminalEmulator);
        });
      }
    } else {
      // If x-terminal-emulator doesn't exist or returns empty, look for
      // supported terminals in the PATH
      for (String terminal in _supportedTerminalEmulators) {
        String? terminalPath = whichSync(terminal);
        if (terminalPath != null) {
          setState(() {
            _terminalEmulator = terminal;
          });
          break;
        }
      }
    }
  }

  void _detectSpice() async {
    var result = whichSync('spicy') ?? '';
    setState(() {
      _spicy = result.isNotEmpty;
    });
  }

  void _manageSnapshot(BuildContext context, String currentVm) async {
    // Expose quickemu's --snapshot apply/create/delete/info actions.
    final shell = Shell();
    final tagController = TextEditingController();
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Snapshots {0}', args: [currentVm])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tagController,
              decoration: InputDecoration(hintText: context.t('Snapshot tag')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('info'),
            child: Text(context.t('Info')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop('create ${tagController.text.trim()}'),
            child: Text(context.t('Create')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop('apply ${tagController.text.trim()}'),
            child: Text(context.t('Apply')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .pop('delete ${tagController.text.trim()}'),
            child: Text(context.t('Delete')),
          ),
        ],
      ),
    ).then((action) async {
      if (action == null || action.isEmpty) return;
      final parts = action.split(' ');
      final command = [
        'quickemu',
        '--vm',
        '$currentVm.conf',
        '--snapshot',
        ...parts.where((p) => p.isNotEmpty),
      ];
      final results = await shell.run(command.join(' '));
      if (!mounted) return;
      _showProcessOutput(results);
    });
  }

  void _confirmDeleteVm(BuildContext context, String currentVm) {
    showDialog<String?>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('Delete {0}', args: [currentVm])),
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
            Text(
              _vmConfFiles[currentVm] ?? '$currentVm.conf',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text(context.t('Cancel')),
            onPressed: () => Navigator.pop(context, 'cancel'),
          ),
          TextButton(
            child: Text(context.t('Delete disk image')),
            onPressed: () => Navigator.pop(context, 'disk'),
          ),
          TextButton(
            child: Text(context.t('Delete whole VM')),
            onPressed: () => Navigator.pop(context, 'vm'),
          ),
        ],
      ),
    ).then((result) async {
      result = result ?? 'cancel';
      if (result != 'cancel') {
        List<String> command = [
          'quickemu',
          '--vm',
          '$currentVm.conf',
          '--delete-$result',
        ];
        var shell = Shell();
        await shell.run(command.join(' '));
      }
    });
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('quickemu'),
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
    VmInfo info = VmInfo();
    File portsFile = File('$name/$name.ports');
    if (portsFile.existsSync()) {
      List<String> lines = portsFile.readAsLinesSync();
      for (var line in lines) {
        List<String> parts = line.split(',');
        switch (parts[0]) {
          case 'ssh':
            info.sshPort = parts[1];
            break;
          case 'spice':
            info.spicePort = parts[1];
            break;
        }
      }
    }
    return info;
  }

  bool _isValidConf(String conf) {
    List<String> lines = File(conf).readAsLinesSync();
    for (var line in lines) {
      List<String> parts = line.split('=');
      if (parts[0] == 'guest_os') {
        return true;
      }
    }
    return false;
  }

  void _getVms() async {
    List<String> currentVms = [];
    Map<String, String> vmConfFiles = {};
    Map<String, VmInfo> activeVms = {};

    await for (var entity in Directory.current.list(
      recursive: false,
      followLinks: true,
    )) {
      if ((entity.path.endsWith('.conf')) && (_isValidConf(entity.path))) {
        String name = path.basenameWithoutExtension(entity.path);
        currentVms.add(name);
        vmConfFiles[name] = entity.path;
        File pidFile = File('$name/$name.pid');
        if (pidFile.existsSync()) {
          String pid = pidFile.readAsStringSync().trim();
          // Check if the process is still running using kill -0, which is
          // a portable way to check if a process is running on macOS and Linux.
          ProcessResult result = Process.runSync('kill', ['-0', pid]);
          if (result.exitCode == 0) {
            if (_activeVms.containsKey(name)) {
              activeVms[name] = _activeVms[name]!;
            } else {
              activeVms[name] = _parseVmInfo(name);
            }
          }
        }
      }
    }
    currentVms.sort();
    setState(() {
      _currentVms = currentVms;
      _vmConfFiles = vmConfFiles;
      _activeVms = activeVms;
    });
  }

  Future<bool> _detectSsh(int port) async {
    bool isSSH = false;
    try {
      Socket socket = await Socket.connect('localhost', port);
      isSSH = await socket.any((event) => utf8.decode(event).contains('SSH'));
      socket.close();
      return isSSH;
    } catch (exception) {
      return false;
    }
  }

  Widget _buildVmList() {
    List<Widget> widgetList = [];
    final Color buttonColor = Theme.of(context).colorScheme.primary;
    widgetList.addAll([
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "${context.t('Directory where the machines are stored')}:",
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: () async {
                var folder = await FilePicker.getDirectoryPath(
                  dialogTitle: "Pick a folder",
                );
                if (folder != null) {
                  setState(() {
                    Directory.current = folder;
                  });
                  savePreference(prefWorkingDirectory, Directory.current.path);
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
    List<List<Widget>> rows = filteredVms.map((vm) {
      return _buildRow(vm, buttonColor);
    }).toList();
    for (var row in rows) {
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
    }
    String vmStem = currentVm;
    SvgPicture? osIcon;
    while (vmStem.contains('-')) {
      vmStem = vmStem.substring(0, vmStem.lastIndexOf('-'));
      if (osIcons.containsKey(vmStem)) {
        osIcon = SvgPicture.asset(osIcons[vmStem]!, width: 32, height: 32);
        break;
      }
    }
    return <Widget>[
      ListTile(
        leading: osIcon ?? const Icon(Icons.computer, size: 32),
        title: Row(
          children: [
            Text(currentVm),
            newVM ? const NewVmTag() : const SizedBox.shrink(),
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
              onPressed: active
                  ? null
                  : () async {
                      Map<String, VmInfo> activeVms = _activeVms;
                      List<String> command = [
                        'quickemu',
                        '--vm',
                        '$currentVm.conf',
                      ];
                      if (_spicy) {
                        command.addAll(['--display', 'spice']);
                      }
                      var shell = Shell();
                      var results = await shell.run(command.join(' '));
                      if (!mounted) return;
                      _showProcessOutput(results);
                      VmInfo info = _parseVmInfo(currentVm);
                      activeVms[currentVm] = info;
                      setState(() {
                        _activeVms = activeVms;
                      });
                    },
            ),
            IconButton(
              icon: Icon(
                active ? Icons.stop : Icons.stop_outlined,
                color: active ? Colors.red : null,
                semanticLabel: active ? 'Stop' : 'Not running',
              ),
              onPressed: !active
                  ? null
                  : () {
                      showDialog<bool>(
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          title: Text(context.t('Stop The Virtual Machine?')),
                          content: Text(
                            context.t(
                              'You are about to terminate the virtual machine {0}',
                              args: [currentVm],
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(context.t('Cancel')),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(context.t('OK')),
                            ),
                          ],
                        ),
                      ).then((result) async {
                        result = result ?? false;
                        if (result) {
                          var shell = Shell();
                          // If Quickemu is newer than 4.9.6, use the new --kill option
                          // which is macOS compatible.
                          var quickemuVersion = Version.parse(
                            await fetchQuickemuVersion(),
                          );
                          if (quickemuVersion >= Version(4, 9, 6)) {
                            shell.run(
                              [
                                'quickemu',
                                '--vm',
                                '$currentVm.conf',
                                '--kill',
                              ].join(' '),
                            );
                          } else {
                            shell.run(['killall', currentVm].join(' '));
                          }
                          setState(() {
                            _activeVms.remove(currentVm);
                          });
                        }
                      });
                    },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, semanticLabel: 'More actions'),
              tooltip: context.t('More actions'),
              enabled: !active,
              onSelected: (choice) {
                switch (choice) {
                  case 'config':
                    showDialog(
                      context: context,
                      builder: (context) => VmConfigEditorDialog(
                        vmName: currentVm,
                        confPath: _vmConfFiles[currentVm]!,
                      ),
                    );
                  case 'folder':
                    Shell().run(
                      '${Platform.isMacOS ? 'open' : 'xdg-open'} "$currentVm"',
                    );
                  case 'snapshot':
                    _manageSnapshot(context, currentVm);
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
                  value: 'delete',
                  child: ListTile(
                    leading: const Icon(Icons.delete),
                    title: Text(context.t('Delete')),
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
                        var shell = Shell();
                        shell.run(['spicy', '-p', vmInfo.spicePort!].join(' '));
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
                    : () {
                        TextEditingController usernameController =
                            TextEditingController(
                              text: Platform.environment['USER'] ?? '',
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
                                  Shell().run(
                                    'ssh-keygen -R [localhost]:${vmInfo.sshPort!}',
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
                            List<String> sshArgs = [
                              'ssh',
                              '-p',
                              vmInfo.sshPort!,
                              usernameController.text.isEmpty
                                  ? 'localhost'
                                  : '${usernameController.text}@localhost',
                            ];
                            // Set the arguments to execute the ssh command in the default terminal.
                            // Strip the extension as x-terminal-emulator may point to a .wrapper
                            switch (path.basenameWithoutExtension(
                              _terminalEmulator!,
                            )) {
                              case 'osascript':
                                sshArgs = [
                                  '-e \'tell app "Terminal" to do script "${sshArgs.join(' ')}"\'',
                                ];
                                break;
                              case 'gnome-terminal':
                              case 'mate-terminal':
                                sshArgs.insert(0, '--');
                                break;
                              case 'kitty':
                              case 'foot':
                                // Run the command directly: `kitty ssh ...`
                                break;
                              case 'wezterm':
                                sshArgs.insert(0, 'start');
                                break;
                              case 'alacritty':
                              case 'xterm':
                              case 'lxterm':
                              case 'uxterm':
                              case 'konsole':
                              case 'uxrvt':
                              case 'xrvt':
                              case 'sakura':
                              case 'cool-retro-term':
                              case 'pterm':
                              case 'lxterminal':
                              case 'tilix':
                              case 'kgx':
                                sshArgs.insert(0, '-e');
                                break;
                              case 'terminator':
                              case 'xfce4-terminal':
                                sshArgs.insert(0, '-x');
                                break;
                              case 'guake':
                                String command = sshArgs.join(' ');
                                sshArgs = ['-e', command];
                                break;
                            }
                            sshArgs.insert(0, _terminalEmulator!);
                            var shell = Shell();
                            shell.run(sshArgs.join(' '));
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
      appBar: AppBar(title: Text(context.t('Manager'))),
      body: _buildVmList(),
    );
  }
}
