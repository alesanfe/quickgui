import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/operations/operation_state.dart';

class DownloadLabel extends StatelessWidget {
  const DownloadLabel({
    required this.state,
    required this.downloader,
    super.key,
  });

  final OperationState<Object?> state;
  final String downloader;

  @override
  Widget build(BuildContext context) {
    final String text = switch (state) {
      OperationCancelled() => context.t('Download cancelled'),
      OperationFailed() => context.t('Download failed'),
      OperationSucceeded() => context.t('Download finished.'),
      OperationRunning(progress: final p?) =>
        downloader == 'curl' || downloader == ''
            ? context.t('Downloading... {0}%', args: [(p * 100).toInt()])
            : downloader != 'zsync'
            ? context.t('{0} Mbs downloaded', args: [p])
            : context.t('Downloading (no progress available)...'),
      OperationRunning() => context.t('Downloading (no progress available)...'),
      _ => context.t('Waiting for download to start'),
    };
    return Padding(padding: const EdgeInsets.all(8.0), child: Text(text));
  }
}
