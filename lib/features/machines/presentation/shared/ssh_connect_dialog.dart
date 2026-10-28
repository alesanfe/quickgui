import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';
import 'package:quickgui/features/settings/application/ports/preferences_repository.dart';

/// SSH connect flow: asks for the guest username (remembered per VM),
/// offers to drop the stale known_hosts entry, then launches the
/// terminal emulator running ssh against the mapped port.
Future<void> showSshConnectDialog(
  BuildContext context, {
  required VirtualizationBackend backend,
  required PreferencesRepository prefs,
  required String vm,
  required String sshPort,
  required String terminalEmulator,
}) async {
  final savedUser = await prefs.getAs<String>('sshUser_$vm');
  if (!context.mounted) return;
  final usernameController = TextEditingController(
    text: savedUser ?? Platform.environment['USER'] ?? '',
  );
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(context.t('Launch SSH connection to {0}', args: [vm])),
      content: TextField(
        controller: usernameController,
        decoration: InputDecoration(hintText: context.t("SSH username")),
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
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.t('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.t('Connect')),
        ),
      ],
    ),
  );
  if (result != true) return;
  await prefs.set('sshUser_$vm', usernameController.text);
  unawaitedLogged(
    backend.connectSsh(
      terminalEmulator: terminalEmulator,
      user: usernameController.text,
      sshPort: sshPort,
    ),
    AppLog.vmLifecycle,
    'ssh :$sshPort',
  );
}
