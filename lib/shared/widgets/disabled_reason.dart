import 'package:flutter/material.dart';

/// Explains *why* a control is disabled (QGUI-UX-002).
///
/// A bare `onPressed: null` button only differs from an enabled one by
/// a small contrast reduction — users cannot tell it is unavailable
/// nor learn why. Wrapping the disabled control in [DisabledReason]
/// keeps the widget focusable enough that its tooltip fires on hover
/// and keyboard focus, and merges the reason into the semantics label
/// so screen readers announce "unavailable because …".
class DisabledReason extends StatefulWidget {
  const DisabledReason({required this.reason, required this.child, super.key});

  /// User-facing explanation, e.g. 'Available while the VM is running'.
  final String reason;

  /// The disabled control.
  final Widget child;

  @override
  State<DisabledReason> createState() => _DisabledReasonState();
}

class _DisabledReasonState extends State<DisabledReason> {
  final _focus = FocusNode(debugLabel: 'disabled-reason');
  final _tooltip = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    // Keyboard focus lands on the wrapper (the disabled child cannot
    // take it) and immediately reveals the reason as a tooltip.
    _focus.addListener(() {
      if (_focus.hasFocus) _tooltip.currentState?.ensureTooltipVisible();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The reason labels the keyboard-focusable wrapper; an inner
    // `container` boundary keeps the disabled child's "unfocusable"
    // flags from merging into it (a node cannot be both focusable
    // and unfocusable — that combination crashes the semantics
    // update). `enabled: false` must therefore never be set here.
    return Semantics(
      label: widget.reason,
      child: Focus(
        focusNode: _focus,
        child: Semantics(
          container: true,
          child: Tooltip(
            key: _tooltip,
            message: widget.reason,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Convenience for the common pattern: an [IconButton] that is disabled
/// while its precondition is unmet, carrying the reason in the tooltip
/// and semantics so [DisabledReason] behaviour applies consistently.
Widget reasonedIconButton({
  required BuildContext context,
  required IconData icon,
  required String tooltip,
  required VoidCallback? onPressed,
  String? disabledReason,
  Color? color,
  String? semanticLabel,
}) {
  final button = IconButton(
    tooltip: onPressed == null && disabledReason != null
        ? disabledReason
        : tooltip,
    icon: Icon(
      icon,
      // `outline` is a neutral desaturated grey in both themes, while
      // the theme's disabledColor reads as a muted primary — disabled
      // icons stayed visually close to enabled ones (QGUI-UX-002).
      color: onPressed == null ? Theme.of(context).colorScheme.outline : color,
      semanticLabel: semanticLabel ?? tooltip,
    ),
    onPressed: onPressed,
  );
  if (onPressed == null && disabledReason != null) {
    return DisabledReason(reason: disabledReason, child: button);
  }
  return button;
}
