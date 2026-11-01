import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Display-viewer dropdown that marks uninstalled viewers
/// (QGUI-VIEW-002/003): `available` maps a viewer binary to whether
/// the host probe found it, so the user learns "remote-viewer — not
/// installed" before saving instead of at the next start. Unknown
/// current values stay selectable (never silently rewritten).
class ViewerSelector extends StatelessWidget {
  const ViewerSelector({
    required this.controller,
    required this.label,
    this.available = const {},
    this.helper,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  /// viewer binary → installed. Empty = no probe results (all shown
  /// without an availability note).
  final Map<String, bool> available;
  final String? helper;

  static const _known = ['spicy', 'remote-viewer', 'none'];

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim();
    final values = {'', ..._known, if (current.isNotEmpty) current};
    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? '' : current,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 4,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final v in values)
          DropdownMenuItem(
            value: v,
            child: Text(switch (v) {
              '' => context.t('Automatic'),
              _ when available.containsKey(v) && !available[v]! =>
                '$v — ${context.t('not installed')}',
              _ => v,
            }),
          ),
      ],
      onChanged: (v) => controller.text = v ?? '',
    );
  }
}
