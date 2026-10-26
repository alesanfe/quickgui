import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/infrastructure/storage/vm_config.dart';
import 'package:quickgui/shared/dialogs/conf_conflict.dart';

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

  String _initialContent = '';
  String _fingerprint = '';

  /// PopScope flag — set once the user explicitly accepts leaving
  /// (discard or successful save) so internal pops are not re-blocked.
  bool _allowPop = false;

  bool get _isDirty => _editorController.text != _initialContent;

  /// Intercepts closing (Escape/system back/Cancel) while edits are
  /// unsaved — offers Save, Discard and Cancel.
  Future<void> _onPopAttempt() async {
    if (_allowPop) return;
    if (!_isDirty) {
      _releaseAndPop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('Discard unsaved changes?')),
        content: Text(
          context.t('Your edits to this configuration have not been saved.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(context.t('Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(context.t('Discard')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(context.t('Save')),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'cancel') return;
    if (choice == 'discard') {
      _releaseAndPop();
      return;
    }
    // 'save': the flag is visible by the time _save() reaches its
    // internal Navigator.pop — the method awaits before popping.
    setState(() => _allowPop = true);
    await _save();
  }

  /// Releases the pop guard, then pops the dialog once the PopScope has
  /// rebuilt with `canPop: true`.
  void _releaseAndPop() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void initState() {
    super.initState();
    ref.read(vmConfigStoreProvider).loadRaw(widget.confPath).then((content) {
      _editorController.text = content;
      _initialContent = content;
      _fingerprint = VmConfigFileStore.fingerprint(widget.confPath);
      setState(() => _loading = false);
    });
  }

  Future<void> _save() async {
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
    if (!mounted) return;
    if (!await _checkExternalChange()) return;
    if (!mounted) return;
    await ref
        .read(vmConfigStoreProvider)
        .saveRaw(widget.confPath, _editorController.text);
    _fingerprint = VmConfigFileStore.fingerprint(widget.confPath);
    _initialContent = _editorController.text; // saved — no longer dirty
    if (!mounted) return;
    _releaseAndPop();
  }

  /// Detects an external modification since the editor was opened and
  /// resolves it via the conflict dialog. Returns true when the save may
  /// proceed, false when the user reloaded/aborted.
  Future<bool> _checkExternalChange() async {
    if (VmConfigFileStore.fingerprint(widget.confPath) == _fingerprint) {
      return true;
    }
    final disk = await ref.read(vmConfigStoreProvider).loadRaw(widget.confPath);
    if (!mounted) return false;
    final result = await showConfConflictDialog(
      context,
      confPath: widget.confPath,
      original: _initialContent,
      local: _editorController.text,
      disk: disk,
    );
    switch (result?.action) {
      case ConfConflictAction.reload:
        _editorController.text = disk;
        _initialContent = disk;
        _fingerprint = VmConfigFileStore.fingerprint(widget.confPath);
        return false;
      case ConfConflictAction.merge:
        _editorController.text = result?.merged ?? _editorController.text;
        return true;
      case ConfConflictAction.overwrite:
        return true;
      case ConfConflictAction.saveCopy:
        if (!mounted) return false;
        final path = await pickAndSaveConfCopy(
          context,
          widget.confPath,
          _editorController.text,
        );
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t('Local copy saved to {0}', args: [path])),
            ),
          );
        }
        return false;
      case ConfConflictAction.cancel:
      case null:
        return false;
    }
  }

  /// Lists rotated .bak files, previews the chosen one and restores it
  /// atomically — the current content is backed up first so the restore
  /// is itself undoable.
  Future<void> _restoreBackup() async {
    final backups = VmConfigFileStore.listBackups(widget.confPath);
    if (backups.isEmpty) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.t('Restore backup')),
        children: [
          for (final f in backups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f.path),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.path.split(RegExp(r'[/\\]')).last),
                  Text(
                    f.readAsStringSync(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    VmConfigFileStore.restoreBackup(widget.confPath, chosen);
    _editorController.text =
        VmConfigFileStore.fingerprint(widget.confPath).isNotEmpty
        ? File(widget.confPath).readAsStringSync()
        : _editorController.text;
    _initialContent = _editorController.text;
    _fingerprint = VmConfigFileStore.fingerprint(widget.confPath);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.t('Backup restored'))));
    }
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
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (_, _) => _onPopAttempt(),
      child: AlertDialog(
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
          if (VmConfigFileStore.listBackups(widget.confPath).isNotEmpty)
            TextButton.icon(
              onPressed: _restoreBackup,
              icon: const Icon(Icons.restore),
              label: Text(context.t('Restore backup')),
            ),
          ElevatedButton(onPressed: _save, child: Text(context.t('Save'))),
        ],
      ),
    );
  }
}
