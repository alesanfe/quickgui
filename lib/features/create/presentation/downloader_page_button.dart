import 'package:flutter/material.dart';
import 'package:quickgui/shared/widgets/disabled_reason.dart';

/// Wide labelled button used by the download controls (OS / Version /
/// Download). [busy] replaces the text with a progress indicator while
/// a pre-flight check is in flight. [disabledReason] explains a null
/// [onPressed] through the shared disabled-state pattern.
class DownloaderPageButton extends StatelessWidget {
  const DownloaderPageButton({
    required this.text,
    this.label,
    this.onPressed,
    this.busy = false,
    this.disabledReason,
    this.icon,
    super.key,
  });

  final String? label;
  final String text;
  final VoidCallback? onPressed;
  final bool busy;
  final String? disabledReason;

  /// QGUI-CREATE-101: picker steps show a chevron, the final step a
  /// download glyph — the button is a navigation/launch action, not a
  /// plain label.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
                  if (icon != null) ...[
                    const SizedBox(width: 6),
                    Icon(icon, size: 18),
                  ],
                ],
              ),
      ),
    );
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
            if (disabledReason != null && onPressed == null && !busy)
              DisabledReason(reason: disabledReason!, child: button)
            else
              button,
          ],
        ),
      ),
    );
  }
}
