import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Structured editor for `host:guest` port forwards (QGUI-DEV-001):
/// each rule is a validated row of two numeric fields instead of a
/// comma-separated string the user must remember. The [controller]
/// still stores the quickemu `host:guest, host:guest` text so the
/// conf serialisation is unchanged.
class PortForwardEditor extends StatefulWidget {
  const PortForwardEditor({
    required this.controller,
    required this.label,
    this.helper,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  /// Parses `2222:22, 8080:80` into editable pairs.
  static List<(String, String)> parse(String raw) => [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty)
        switch (part.trim().split(':')) {
          [final h, final g] => (h.trim(), g.trim()),
          // Unrecognised fragment: keep it verbatim in the host slot
          // so the editor never silently drops data.
          _ => (part.trim(), ''),
        },
  ];

  static String serialise(List<(String, String)> rows) => rows
      .where((r) => r.$1.trim().isNotEmpty || r.$2.trim().isNotEmpty)
      .map((r) => '${r.$1.trim()}:${r.$2.trim()}')
      .join(', ');

  static bool _validPort(String v) {
    final n = int.tryParse(v.trim());
    return n != null && n >= 1 && n <= 65535;
  }

  @override
  State<PortForwardEditor> createState() => _PortForwardEditorState();
}

class _PortForwardEditorState extends State<PortForwardEditor> {
  late List<(TextEditingController, TextEditingController)> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final (h, g) in PortForwardEditor.parse(widget.controller.text))
        (TextEditingController(text: h), TextEditingController(text: g)),
    ];
  }

  @override
  void dispose() {
    for (final (h, g) in _rows) {
      h.dispose();
      g.dispose();
    }
    super.dispose();
  }

  void _sync() {
    widget.controller.text = PortForwardEditor.serialise([
      for (final (h, g) in _rows) (h.text, g.text),
    ]);
    setState(() {});
  }

  String? get _error {
    final seen = <String>{};
    for (final (h, g) in _rows) {
      if (h.text.trim().isEmpty && g.text.trim().isEmpty) continue;
      if (!PortForwardEditor._validPort(h.text) ||
          !PortForwardEditor._validPort(g.text)) {
        return context.t('Use port pairs from 1 to 65535, for example 8080:80');
      }
      final key = h.text.trim();
      if (!seen.add(key)) {
        return context.t('Duplicate host port {0}', args: [key]);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              widget.helper!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rows[i].$1,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.t('Host port'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _rows[i].$2,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.t('Guest port'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                IconButton(
                  tooltip: context.t('Remove rule'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    _rows[i].$1.dispose();
                    _rows[i].$2.dispose();
                    _rows.removeAt(i);
                    _sync();
                  },
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.t('Add port forward')),
            onPressed: () {
              _rows.add((TextEditingController(), TextEditingController()));
              setState(() {});
            },
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
