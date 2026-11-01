import 'package:flutter/material.dart';

/// Dialog shell enforcing the repo's scrollable-dialog pattern
/// (QGUI-UX-003): a fixed header, a scrollable body bounded by the
/// available window height and an always-visible action bar, so the
/// primary actions can never fall below the fold at small window
/// sizes or large text scales.
///
/// Use this instead of [AlertDialog] when the content is taller than
/// ~3 fields; the built-in scrollbar makes scrollability discoverable.
class QDialog extends StatefulWidget {
  const QDialog({
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 560,
    this.trailing,
    super.key,
  });

  /// Header text (already localised by the caller).
  final String title;

  /// Scrollable body.
  final Widget child;

  /// Action row widgets (cancel left, primary right, per QGUI-UX-004).
  final List<Widget> actions;

  /// Max content width.
  final double width;

  /// Optional widget at the header's trailing edge (e.g. a help menu).
  final Widget? trailing;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    List<Widget> actions = const [],
    double width = 560,
    Widget? trailing,
  }) => showDialog<T>(
    context: context,
    builder: (context) => QDialog(
      title: title,
      actions: actions,
      width: width,
      trailing: trailing,
      child: child,
    ),
  );

  @override
  State<QDialog> createState() => _QDialogState();
}

class _QDialogState extends State<QDialog> {
  /// Shared by the [Scrollbar] and the [SingleChildScrollView]: on
  /// desktop there is no implicit PrimaryScrollController, so without
  /// this the scrollbar has no ScrollPosition to attach to.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.width,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  ?widget.trailing,
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: Scrollbar(
                thumbVisibility: true,
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: widget.child,
                ),
              ),
            ),
            if (widget.actions.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: widget.actions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
