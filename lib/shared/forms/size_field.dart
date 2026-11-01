import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Structured size input (QGUI-RES-001/RESIZE-001): a numeric field
/// plus an explicit unit selector bound to one [TextEditingController]
/// that keeps the quickemu representation (`32G`, `512M`, `1T`).
///
/// Splitting value and unit removes the "what do I type?" ambiguity of
/// a free-text size field; an empty amount stays empty so quickemu
/// defaults still apply.
class SizeField extends StatefulWidget {
  const SizeField({
    required this.controller,
    required this.label,
    this.helper,
    this.errorText,
    this.units = const ['G', 'M'],
    this.allowEmpty = true,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? errorText;
  final List<String> units;
  final bool allowEmpty;

  /// Called after every edit so parents (e.g. dialog builders) can
  /// rebuild confirm-button state even though the field writes into
  /// [controller] directly.
  final VoidCallback? onChanged;

  /// Splits `32G` into ('32', 'G'); a bare number keeps [fallbackUnit].
  static (String amount, String unit) split(
    String value, {
    String fallbackUnit = 'G',
  }) {
    final v = value.trim().toUpperCase();
    final m = RegExp(r'^(\d+(?:\.\d+)?)([KMGT])?$').firstMatch(v);
    if (m == null) {
      // Unparseable legacy value: surface it raw so nothing is lost.
      return (v, fallbackUnit);
    }
    return (m.group(1)!, m.group(2) ?? fallbackUnit);
  }

  @override
  State<SizeField> createState() => _SizeFieldState();
}

class _SizeFieldState extends State<SizeField> {
  late final TextEditingController _amountCtrl;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final (a, u) = SizeField.split(widget.controller.text);
    _amountCtrl = TextEditingController(text: a);
    _unit = u;
    if (!widget.units.contains(_unit)) _unit = widget.units.first;
    widget.controller.addListener(_syncExternal);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncExternal);
    _amountCtrl.dispose();
    super.dispose();
  }

  /// Reflects changes to the bound controller that did not come from
  /// this field (external edits, profile presets, loaded values).
  void _syncExternal() {
    final (a, u) = SizeField.split(widget.controller.text, fallbackUnit: _unit);
    var dirty = false;
    if (a != _amountCtrl.text) {
      _amountCtrl.text = a;
      dirty = true;
    }
    if (widget.units.contains(u) && u != _unit) {
      _unit = u;
      dirty = true;
    }
    if (dirty && mounted) setState(() {});
  }

  void _write({String? unit}) {
    final a = _amountCtrl.text.trim();
    final u = unit ?? _unit;
    widget.controller.text = a.isEmpty ? '' : '$a$u';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.helper,
              helperMaxLines: 4,
              errorText: widget.errorText,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              // The user may type the unit into the field ("64G") — the
              // suffix moves to the unit selector instead of doubling.
              final raw = v.trim();
              final (a, u) = SizeField.split(raw, fallbackUnit: _unit);
              if (RegExp(r'[KMGT]$').hasMatch(raw.toUpperCase())) {
                if (a != _amountCtrl.text) {
                  _amountCtrl.text = a;
                  _amountCtrl.selection = TextSelection.collapsed(
                    offset: a.length,
                  );
                }
                if (u != _unit) setState(() => _unit = u);
                widget.controller.text = raw.toUpperCase();
              } else {
                _write();
              }
              widget.onChanged?.call();
            },
            validator: (raw) {
              final v = (raw ?? '').trim();
              if (v.isEmpty) {
                return widget.allowEmpty ? null : context.t('Enter a size');
              }
              if (SizeField.split(v).$1 != v &&
                  !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(v)) {
                return context.t('Use a size such as 4G or 512M');
              }
              if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(v)) {
                return context.t('Enter a positive number');
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: DropdownButton<String>(
            value: _unit,
            items: [
              for (final u in widget.units)
                DropdownMenuItem(value: u, child: Text(u)),
            ],
            onChanged: (u) {
              if (u == null) return;
              setState(() => _unit = u);
              _write(unit: u);
              widget.onChanged?.call();
            },
          ),
        ),
      ],
    );
  }
}
