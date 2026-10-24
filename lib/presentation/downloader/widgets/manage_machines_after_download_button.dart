import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/presentation/manager/manager.dart';

class ManageMachinesAfterDownloadButton extends StatelessWidget {
  const ManageMachinesAfterDownloadButton({
    required this.downloadFinished,
    super.key,
  });

  final bool downloadFinished;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (downloadFinished)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (context) => const Manager()),
                );
              },
              child: Text(context.t('Manage existing machines')),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}
