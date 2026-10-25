import 'package:flutter/material.dart';

class DownloaderPageButton extends StatelessWidget {
  const DownloaderPageButton({
    required this.text,
    this.label,
    this.onPressed,
    this.busy = false,
    super.key,
  });

  final String? label;
  final String text;
  final VoidCallback? onPressed;

  /// Shows a progress indicator inside the button while an async check
  /// (e.g. `quickget --check`) is in flight, instead of the [text].
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(4.0),
              child: Center(
                child: Text(
                  label?.toUpperCase() ?? '',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: busy ? null : onPressed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
                child: busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
