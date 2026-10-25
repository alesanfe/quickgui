import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/features/machines/providers/backend_providers.dart';

class VmConfigEditorDialog extends ConsumerStatefulWidget {
  final String vmName;
  final String confPath;

  const VmConfigEditorDialog({
    required this.vmName,
    required this.confPath,
    super.key,
  });

  @override
  ConsumerState<VmConfigEditorDialog> createState() =>
      _VmConfigEditorDialogState();
}

class _VmConfigEditorDialogState extends ConsumerState<VmConfigEditorDialog> {
  final TextEditingController _editorController = TextEditingController();
  bool _loading = true;
  String? _error;

  /// quickemu conf lines are `key="value"`; comments (#) and blank lines
  /// are allowed. Returns the offending line number, or null if valid.
  static int? _firstInvalidLine(String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!RegExp(r'^[a-zA-Z_][\w-]*\s*=').hasMatch(line)) return i + 1;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    ref.read(vmConfigStoreProvider).loadRaw(widget.confPath).then((content) {
      _editorController.text = content;
      setState(() => _loading = false);
    });
  }

  void _save() async {
    final badLine = _firstInvalidLine(_editorController.text);
    if (badLine != null) {
      setState(() {
        _error = context.t(
          'Line {0}: expected key="value".',
          args: ['$badLine'],
        );
      });
      return;
    }
    await ref
        .read(vmConfigStoreProvider)
        .saveRaw(widget.confPath, _editorController.text);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _openDocs() async {
    const url =
        'https://github.com/quickemu-project/quickemu/blob/master/docs/quickemu_conf.5.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('Edit VM: {0}', args: [widget.vmName])),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.confPath,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: Text(context.t('Open config documentation')),
                      onPressed: _openDocs,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: TextField(
                      controller: _editorController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(8),
                      ),
                      onChanged: (_) {
                        if (_error != null) {
                          setState(() => _error = null);
                        }
                      },
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
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
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t('Cancel')),
        ),
        ElevatedButton(onPressed: _save, child: Text(context.t('Save'))),
      ],
    );
  }
}
