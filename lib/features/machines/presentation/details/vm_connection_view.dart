import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/features/machines/presentation/shared/ssh_connect_dialog.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

class VmConnectionView extends ConsumerStatefulWidget {
  const VmConnectionView({required this.vm, required this.confPath, super.key});
  final String vm;
  final String confPath;

  @override
  ConsumerState<VmConnectionView> createState() => _VmConnectionViewState();
}

class _VmConnectionViewState extends ConsumerState<VmConnectionView> {
  String? _message;
  bool _checking = false;
  bool _fullscreen = false;
  final Map<String, String> _ports = {};

  @override
  void initState() {
    super.initState();
    _readPorts();
  }

  void _readPorts() {
    _ports.clear();
    final file = File(
      p.join(p.dirname(widget.confPath), widget.vm, '${widget.vm}.ports'),
    );
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final parts = line.split(',');
        if (parts.length >= 2) _ports[parts.first] = parts[1];
      }
    }
  }

  Future<void> _connect(bool ssh) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _message = null;
      _readPorts();
    });
    final backend = ref.read(trackedBackendProvider);
    final probe = ref.read(hostProbeProvider);
    final preferences = ref.read(preferencesRepositoryProvider);
    final configured = ref
        .read(vmConfigStoreProvider)
        .read(widget.confPath, 'viewer');
    final preferred = ref.read(uiPreferencesProvider).preferredViewer;
    final viewer = configured == null || configured.isEmpty
        ? (preferred.isEmpty ? 'spicy' : preferred)
        : configured;
    try {
      final port = _ports[ssh ? 'ssh' : 'spice'];
      if (port == null || int.tryParse(port) == null) {
        if (mounted) {
          setState(
            () => _message = context.t(
              'The guest has not published a connection port. Start the machine and wait until it is ready, then retry.',
            ),
          );
        }
        return;
      }
      if (ssh) {
        final portNum = int.tryParse(port);
        if (portNum != null && !await probe.isSshAlive(portNum)) {
          if (mounted) {
            setState(
              () => _message = context.t(
                'The forwarded port is not serving SSH yet. Wait for guest startup and check the guest SSH service.',
              ),
            );
          }
          return;
        }
        final terminal = await probe.terminalEmulator();
        if (!mounted) return;
        if (terminal == null) {
          setState(() => _message = context.t('No terminal emulator found'));
          return;
        }
        await showSshConnectDialog(
          context,
          backend: backend,
          prefs: preferences,
          vm: widget.vm,
          sshPort: port,
          terminalEmulator: terminal,
        );
      } else {
        if (!{'spicy', 'remote-viewer'}.contains(viewer) ||
            !await probe.hasTool(viewer)) {
          if (mounted) {
            setState(
              () => _message = context.t(
                'The selected SPICE viewer is unavailable. Install spicy or remote-viewer and choose it in Settings.',
              ),
            );
          }
          return;
        }
        final socket = await Socket.connect(
          '127.0.0.1',
          int.tryParse(port) ?? 0,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        if (!mounted) return;
        setState(
          () => _message = context.t(
            'External viewer opened. Display resize, clipboard and guest integration are provided by the viewer and guest tools.',
          ),
        );
        final result = await backend.launchSpiceViewer(
          port,
          viewer: viewer,
          fullscreen: _fullscreen,
        );
        if (result.exitCode != 0 && mounted) {
          setState(() => _message = '${result.stderr}');
        }
      }
    } on SocketException {
      if (mounted) {
        setState(
          () => _message = context.t(
            'The SPICE port is closed. The machine may still be starting or may have stopped. Refresh the status and retry.',
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = context.t('Connection failed: {0}', args: ['$error']),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.desktop_windows_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                context.t('Connect to your machine'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                context.t(
                  'Quickgui manages the connection here and opens the native viewer. A SPICE or VNC display is not embedded in this build.',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _checking ? null : () => _connect(false),
                    icon: const Icon(Icons.monitor),
                    label: Text(context.t('Connect / reconnect')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _checking ? null : () => _connect(true),
                    icon: const Icon(Icons.terminal),
                    label: Text(context.t('Connect with SSH')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(_readPorts),
                    icon: const Icon(Icons.refresh),
                    label: Text(context.t('Refresh ports')),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('Open viewer in full screen')),
                value: _fullscreen,
                onChanged: (value) => setState(() => _fullscreen = value),
              ),
              if (_checking) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(_message!),
                ),
            ],
          ),
        ),
      ),
      for (final entry in _ports.entries)
        ListTile(
          leading: const Icon(Icons.cable),
          title: Text(entry.key.toUpperCase()),
          subtitle: Text('127.0.0.1:${entry.value}'),
        ),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(context.t('Serial and VNC access')),
        subtitle: Text(
          context.t(
            'Serial sockets and VNC addresses can be configured in Advanced settings. No terminal or VNC client is embedded; do not expose these ports to untrusted networks.',
          ),
        ),
      ),
    ],
  );
}
