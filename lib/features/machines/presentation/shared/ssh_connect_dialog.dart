import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';

/// SSH connect flow: asks for the guest username (remembered per VM),
/// lets the user pick the connection target — the forwarded host port
/// or a bridged guest address reported by the agent (QG-051) — offers
/// to drop the stale known_hosts entry, and launches the terminal
/// emulator running ssh.
Future<void> showSshConnectDialog(
  BuildContext context, {
  required VirtualizationBackend backend,
  required PreferencesRepository prefs,
  required String vm,
  required String sshPort,
  required String terminalEmulator,
  List<String> guestAddresses = const [],
}) async {
  final savedUser = await prefs.getAs<String>('sshUser_$vm');
  final savedTarget = await prefs.getAs<String>('sshTarget_$vm');
  if (!context.mounted) return;
  final usernameController = TextEditingController(
    text: savedUser ?? Platform.environment['USER'] ?? '',
  );
  // The guest-address path uses its own port (default 22 — sshd's
  // well-known port on the guest, not the forwarded host port).
  final guestPortController = TextEditingController(text: '22');
  String target = guestAddresses.contains(savedTarget) ? savedTarget! : '';

  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.t('Launch SSH connection to {0}', args: [vm])),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  hintText: context.t("SSH username"),
                ),
              ),
              const SizedBox(height: 12),
              if (guestAddresses.isNotEmpty) ...[
                Text(
                  context.t('Connect via'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                RadioGroup<String>(
                  groupValue: target,
                  onChanged: (v) => setDialogState(() => target = v ?? ''),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          context.t(
                            'Forwarded port (localhost:{0})',
                            args: [sshPort],
                          ),
                        ),
                        value: '',
                      ),
                      for (final ip in guestAddresses)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context.t('Guest address {0}', args: [ip]),
                          ),
                          value: ip,
                        ),
                    ],
                  ),
                ),
                if (target.isNotEmpty)
                  TextField(
                    controller: guestPortController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: context.t('Guest SSH port'),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              // Remove the stale known_hosts entry, e.g.
              // when a new guest reuses the SSH port of a
              // deleted VM.
              unawaitedLogged(
                backend.forgetSshHostKey(sshPort),
                AppLog.vmLifecycle,
                'forget ssh key :$sshPort',
              );
            },
            child: Text(context.t('Forget host key')),
          ),
          TextButton(
            onPressed: () {
              final user = usernameController.text;
              final host = target.isEmpty ? 'localhost' : target;
              final port = target.isEmpty ? sshPort : guestPortController.text;
              final cmd = 'ssh -p $port ${user.isEmpty ? host : '$user@$host'}';
              unawaited(Clipboard.setData(ClipboardData(text: cmd)));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.t('Command copied'))),
              );
            },
            child: Text(context.t('Copy command')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('Connect')),
          ),
        ],
      ),
    ),
  );
  if (result != true) return;
  await prefs.set('sshUser_$vm', usernameController.text);
  await prefs.set('sshTarget_$vm', target);
  final isGuest = target.isNotEmpty;
  unawaitedLogged(
    backend.connectSsh(
      terminalEmulator: terminalEmulator,
      user: usernameController.text,
      sshPort: isGuest ? guestPortController.text : sshPort,
      host: isGuest ? target : null,
    ),
    AppLog.vmLifecycle,
    'ssh ${isGuest ? target : 'localhost'}:',
  );
}
