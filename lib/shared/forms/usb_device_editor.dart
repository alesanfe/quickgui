import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Structured editor for `vendor:product` USB passthrough pairs
/// (QGUI-DEV-001): rows of two validated hex fields instead of raw
/// comma-separated syntax. [controller] keeps the quickemu text
/// (`046d:c52b, 0781:5567`) so serialisation is unchanged.
class UsbDeviceEditor extends StatefulWidget {
  const UsbDeviceEditor({
    required this.controller,
    required this.label,
    this.helper,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  static final _hex4 = RegExp(r'^[0-9a-fA-F]{4}$');

  static List<(String, String)> parse(String raw) => [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty)
        switch (part.trim().split(':')) {
          [final v, final p] => (v.trim(), p.trim()),
          _ => (part.trim(), ''),
        },
  ];

  @override
  State<UsbDeviceEditor> createState() => _UsbDeviceEditorState();
}

class _UsbDeviceEditorState extends State<UsbDeviceEditor> {
  late List<(TextEditingController, TextEditingController)> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final (v, p) in UsbDeviceEditor.parse(widget.controller.text))
        (TextEditingController(text: v), TextEditingController(text: p)),
    ];
  }

  @override
  void dispose() {
    for (final (v, p) in _rows) {
      v.dispose();
      p.dispose();
    }
    super.dispose();
  }

  void _sync() {
    widget.controller.text = _rows
        .where(
          (r) => r.$1.text.trim().isNotEmpty || r.$2.text.trim().isNotEmpty,
        )
        .map((r) => '${r.$1.text.trim()}:${r.$2.text.trim()}')
        .join(', ');
    setState(() {});
  }

  String? get _error {
    for (final (v, p) in _rows) {
      if (v.text.trim().isEmpty && p.text.trim().isEmpty) continue;
      if (!UsbDeviceEditor._hex4.hasMatch(v.text.trim()) ||
          !UsbDeviceEditor._hex4.hasMatch(p.text.trim())) {
        return context.t('Use 4-digit hexadecimal IDs, for example 046d:c52b');
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
                    decoration: InputDecoration(
                      labelText: context.t('Vendor ID'),
                      hintText: '046d',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':'),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _rows[i].$2,
                    decoration: InputDecoration(
                      labelText: context.t('Product ID'),
                      hintText: 'c52b',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                IconButton(
                  tooltip: context.t('Remove device'),
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
            label: Text(context.t('Add USB device')),
            onPressed: () {
              _rows.add((TextEditingController(), TextEditingController()));
              setState(() {});
            },
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
