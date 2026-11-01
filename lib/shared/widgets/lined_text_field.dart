import 'package:flutter/material.dart';

/// Multiline [TextField] with a synchronised line-number gutter
/// (QGUI-CONF-002). Both panes share the same text metrics so the
/// numbers stay aligned at every text scale.
class LinedTextField extends StatefulWidget {
  const LinedTextField({
    required this.controller,
    required this.style,
    this.decoration = const InputDecoration(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.all(8),
    ),
    this.errorLines = const {},
    this.onChanged,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;

  /// The style applied to both the gutter numbers and the field text —
  /// pass a monospace style so columns line up.
  final TextStyle style;
  final InputDecoration decoration;

  /// 1-based line numbers to highlight in the gutter (validation).
  final Set<int> errorLines;
  final ValueChanged<String>? onChanged;

  @override
  State<LinedTextField> createState() => _LinedTextFieldState();
}

class _LinedTextFieldState extends State<LinedTextField> {
  final _fieldScroll = ScrollController();
  final _gutterScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // The gutter cannot own the field's controller, so it follows it:
    // every field scroll mirrors into the number column.
    _fieldScroll.addListener(() {
      if (_gutterScroll.hasClients &&
          _gutterScroll.offset != _fieldScroll.offset) {
        _gutterScroll.jumpTo(_fieldScroll.offset);
      }
    });
  }

  @override
  void dispose() {
    _fieldScroll.dispose();
    _gutterScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.controller.text).length + 1;
    final numbers = List.generate(lineCount, (i) => i + 1);
    final pad = widget.decoration.contentPadding;
    final gutterStyle = widget.style.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
              left: BorderSide(color: Theme.of(context).dividerColor),
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          // Top padding mirrors the field's contentPadding so line 1
          // aligns with the first text row.
          padding: EdgeInsets.only(
            top: pad is EdgeInsets ? pad.top : 8,
            bottom: pad is EdgeInsets ? pad.bottom : 8,
          ),
          child: SingleChildScrollView(
            controller: _gutterScroll,
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final n in numbers)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '$n',
                      style: widget.errorLines.contains(n)
                          ? gutterStyle.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            )
                          : gutterStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            scrollController: _fieldScroll,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: widget.style,
            decoration: widget.decoration,
            onChanged: (v) {
              widget.onChanged?.call(v);
              // Line count may have changed — rebuild the gutter.
              setState(() {});
            },
          ),
        ),
      ],
    );
  }
}
