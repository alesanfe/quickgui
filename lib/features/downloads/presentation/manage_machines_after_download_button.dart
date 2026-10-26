import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/machines/application/start_vm.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/features/machines/presentation/list/manager.dart';

/// Actions offered once a download completes: start the new VM directly
/// or jump to the machine manager.
class ManageMachinesAfterDownloadButton extends ConsumerWidget {
  const ManageMachinesAfterDownloadButton({
    required this.downloadFinished,
    required this.vmName,
    super.key,
  });

  final bool downloadFinished;

  /// Name of the VM just created (quickget convention `<os>-<release>`).
  final String vmName;

  Future<void> _startVm(BuildContext context, WidgetRef ref) async {
    final result = await StartVm(ref.read(trackedBackendProvider))(vmName);
    if (!context.mounted) return;
    if (result is Err) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Error')),
          content: Text(context.t('Could not start {0}.', args: [vmName])),
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
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (context) => const Manager()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (downloadFinished) ...[
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(context.t('Start {0}', args: [vmName])),
              onPressed: () => _startVm(context, ref),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const Manager(),
                  ),
                );
              },
              child: Text(context.t('Manage existing machines')),
            ),
          ] else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
