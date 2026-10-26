import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/domain/vm_config_value.dart';
import 'package:quickgui/features/machines/presentation/details/vm_config_editor.dart';
import 'package:quickgui/shared/dialogs/conf_conflict.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';

/// A group of conf keys shown under one section header.
class _Section {
  const _Section(this.title, this.fields);

  final String title;
  final List<String> fields;
}

/// Full-screen VM configuration, replacing the modal conf dialogs.
///
/// Keys are read/written through the [vmConfigStoreProvider] so the file
/// keeps `key="value"` lines this page does not manage. Unknown keys are
/// editable from the "Advanced" section.
class VmSettingsPage extends ConsumerStatefulWidget {
  const VmSettingsPage({required this.vmName, this.section, super.key});

  final String vmName;
  final String? section;

  @override
  ConsumerState<VmSettingsPage> createState() => _VmSettingsPageState();
}

class _VmSettingsPageState extends ConsumerState<VmSettingsPage> {
  static const _fixedKeys = {
    'guest_os',
    'ram',
    'cpu_cores',
    'disk_size',
    'boot',
    'network',
    'bridge',
    'macaddr',
    'secureboot',
    'tpm',
    'display',
    'viewer',
    'sound',
    'public_dir',
    'usb_devices',
    'port_forwards',
    'fixed_iso',
    'floppy',
    'iso',
    'img',
  };

  final Map<String, TextEditingController> _controllers = {};
  List<String> _rawLines = [];
  List<String> _extraKeys = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _advanced = false;
  bool _saving = false;
  bool _allowPop = false;
  final _form = GlobalKey<FormState>();
  static const _arrayKeys = {'port_forwards', 'usb_devices'};

  String get _confPath => '${widget.vmName}.conf';

  @override
  void initState() {
    super.initState();
    _advanced = ref.read(uiPreferencesProvider).advancedConfig;
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final raw = await ref.read(vmConfigStoreProvider).loadRaw(_confPath);
      if (!mounted) return;
      final lines = raw.split('\n');
      final found = <String>{};
      for (final line in lines) {
        final m = RegExp(r'^([a-zA-Z_][\w-]*)\s*=').firstMatch(line.trim());
        if (m != null) found.add(m.group(1)!);
      }
      setState(() {
        _rawLines = lines;
        _extraKeys = (found.difference(_fixedKeys)).toList()..sort();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  String _current(String key) {
    for (final line in _rawLines) {
      if (_arrayKeys.contains(key)) {
        final m = RegExp('^${RegExp.escape(key)}=\\((.*)\\)\\s*\$')
            .firstMatch(line.trim());
        if (m != null) return parseVmArray(m.group(1)!).join(', ');
      }
      final m = RegExp('^${RegExp.escape(key)}="(.*)"').firstMatch(line.trim());
      if (m != null) return decodeVmValue(m.group(1)!);
    }
    return '';
  }

  TextEditingController _controllerFor(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: _current(key)),
  );

  /// True when any field differs from the loaded configuration.
  bool get _isDirty => _controllers.entries.any(
    (e) => e.value.text.trim() != _current(e.key).trim(),
  );

  /// Intercepts navigation away (back button, swipe, system close)
  /// while edits are unsaved — offers Save, Discard and Keep editing.
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
    await _save();
  }

  /// Releases the pop guard, then pops once PopScope has rebuilt with
  /// `canPop: true`.
  void _releaseAndPop() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.canPop()) context.pop();
    });
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      // Round-trip the whole file through saveRaw: the port has no
      // per-key remove, so managed keys are filtered out of the raw text
      // and rewritten with their edited values. Unknown keys and comments
      // survive untouched.
      final store = ref.read(vmConfigStoreProvider);
      final managed = _controllers.keys.toSet();
      final raw = await store.loadRaw(_confPath);
      if (!mounted) return;
      final kept = raw.split('\n').where((line) {
        final m = RegExp(r'^([a-zA-Z_][\w-]*)\s*=').firstMatch(line.trim());
        return m == null || !managed.contains(m.group(1));
      }).toList();
      // Drop the trailing empty element produced by split() so we do not
      // accumulate blank lines on every save.
      while (kept.isNotEmpty && kept.last.trim().isEmpty) {
        kept.removeLast();
      }
      for (final key in [..._fixedKeys, ..._extraKeys]) {
        final controller = _controllers[key];
        if (controller == null) continue;
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          kept.add(
            _arrayKeys.contains(key)
                ? '$key=${encodeVmArray(value.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty))}'
                : '$key="${encodeVmValue(value)}"',
          );
        }
      }
      var merged = '${kept.join('\n')}\n';
      if (raw != _rawLines.join('\n')) {
        final result = await showConfConflictDialog(
          context,
          confPath: _confPath,
          original: _rawLines.join('\n'),
          local: merged,
          disk: raw,
        );
        if (!mounted) return;
        switch (result?.action) {
          case ConfConflictAction.reload:
            await _load();
            return;
          case ConfConflictAction.merge:
            merged = result?.merged ?? merged;
          case ConfConflictAction.overwrite:
            break;
          case ConfConflictAction.saveCopy:
            final path = await pickAndSaveConfCopy(context, _confPath, merged);
            if (!mounted) return;
            if (path != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.t('Local copy saved to {0}', args: [path]),
                  ),
                ),
              );
            }
            return;
          case ConfConflictAction.cancel:
          case null:
            return;
        }
      }
      await store.saveRaw(_confPath, merged);
      if (!mounted) return;
      // Persisted — refresh the baseline so _isDirty is false and the
      // pop guard lets the route close.
      _rawLines = merged.split('\n');
      _allowPop = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Configuration saved'))));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/machines/${Uri.encodeComponent(widget.vmName)}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t('Could not save configuration: {0}', args: ['$error']),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<_Section> _sections(BuildContext context) => [
    _Section(context.t('Hardware'), [
      'ram',
      'cpu_cores',
      'disk_size',
      'tpm',
      'secureboot',
    ]),
    _Section(context.t('Boot'), ['boot', 'guest_os', 'iso', 'img']),
    _Section(context.t('Display & sound'), ['display', 'viewer', 'sound']),
    _Section(context.t('Network'), [
      'network',
      'bridge',
      'macaddr',
      'port_forwards',
    ]),
    _Section(context.t('Sharing & devices'), [
      'public_dir',
      'usb_devices',
      'fixed_iso',
      'floppy',
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = _sections(context);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopAttempt();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t('Settings — {0}', args: [widget.vmName])),
          actions: [
            Tooltip(
              message: context.t(
                'Show all options, including ones not covered by the basic editor',
              ),
              child: Row(
                children: [
                  Text(context.t('Advanced')),
                  Switch(
                    value: _advanced,
                    onChanged: (v) => setState(() => _advanced = v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.t('Open config documentation'),
              icon: const Icon(Icons.help_outline),
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://github.com/quickemu-project/quickemu/blob/master/docs/quickemu_conf.5.md',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(context.t('Unable to load configuration')),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _load,
                      child: Text(context.t('Retry')),
                    ),
                  ],
                ),
              )
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(
                          context.t('Changes take effect at the next start'),
                        ),
                        subtitle: Text(
                          context.t(
                            'Stop the machine before changing disks, firmware or network configuration.',
                          ),
                        ),
                      ),
                    ),
                    for (final section in sections)
                      if (widget.section == null ||
                          section.title == widget.section)
                        _SectionCard(
                          title: section.title,
                          fields: [
                            for (final key in section.fields)
                              (key, _controllerFor(key)),
                          ],
                        ),
                    if (_advanced && _extraKeys.isNotEmpty)
                      _SectionCard(
                        title: context.t('Advanced (other keys)'),
                        fields: [
                          for (final key in _extraKeys)
                            (key, _controllerFor(key)),
                        ],
                      ),
                    const SizedBox(height: 24),

                    if (_advanced)
                      TextButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => VmConfigEditorDialog(
                            vmName: widget.vmName,
                            confPath: _confPath,
                          ),
                        ),
                        icon: const Icon(Icons.code),
                        label: Text(context.t('Edit raw configuration')),
                      ),
                  ],
                ),
              ),
        bottomNavigationBar: _loading || _loadFailed
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    heightFactor: 1,
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(context.t('Save')),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.fields});

  final String title;
  final List<(String, TextEditingController)> fields;

  Widget _field(
    BuildContext context,
    String key,
    TextEditingController controller,
  ) {
    final labels = {
      'ram': context.t('Memory'),
      'cpu_cores': context.t('CPU cores'),
      'disk_size': context.t('Virtual disk capacity'),
      'boot': context.t('Firmware'),
      'guest_os': context.t('Guest OS'),
      'display': context.t('Display'),
      'viewer': context.t('Display viewer'),
      'sound': context.t('Audio'),
      'network': context.t('Network mode or bridge interface'),
      'bridge': context.t('Legacy bridge interface'),
      'macaddr': context.t('MAC address'),
      'port_forwards': context.t('Forwarded ports (host:guest)'),
      'public_dir': context.t('Shared host folder'),
      'usb_devices': context.t('USB devices (vendor:product)'),
      'iso': context.t('Installation ISO'),
      'img': context.t('Recovery image'),
      'fixed_iso': context.t('Additional ISO'),
      'floppy': context.t('Floppy image'),
      'tpm': context.t('TPM 2.0'),
      'secureboot': context.t('Secure Boot'),
    };
    final choices = switch (key) {
      'boot' => ['efi', 'legacy'],
      'secureboot' || 'tpm' => ['on', 'off'],
      'network' => ['', 'none', 'restrict', 'passt'],
      'viewer' => ['spicy', 'remote-viewer', 'none'],
      'display' => ['spice', 'sdl', 'gtk', 'none', 'vnc'],
      _ => null,
    };
    final help = switch (key) {
      'network' => context.t(
        'Empty = user NAT. restrict = isolated user network. none = disconnected. For bridging, enter the host bridge name (for example br0).',
      ),
      'port_forwards' => context.t(
        'Comma-separated host:guest pairs. Quickemu forwards both TCP and UDP on all host interfaces. Only available with user NAT/restricted networking.',
      ),
      'public_dir' => context.t(
        'Share only a trusted folder. Guest access can expose host files; permissions and guest tools still apply.',
      ),
      'usb_devices' => context.t(
        'Comma-separated USB vendor:product identifiers. Disconnecting host devices may interrupt other applications.',
      ),
      _ => null,
    };
    if (choices != null && key != 'network') {
      return DropdownButtonFormField<String>(
        initialValue: controller.text.isEmpty ? null : controller.text,
        decoration: InputDecoration(
          labelText: labels[key] ?? key,
          border: const OutlineInputBorder(),
        ),
        items: {...choices, if (controller.text.isNotEmpty) controller.text}
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) => controller.text = value ?? '',
      );
    }
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labels[key] ?? key,
        helperText: help,
        helperMaxLines: 6,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      validator: (raw) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        if (key == 'cpu_cores' &&
            (int.tryParse(value) == null ||
                int.parse(value) < 1 ||
                int.parse(value) > 1024)) {
          return context.t('Enter a positive CPU count');
        }
        if ((key == 'ram' || key == 'disk_size') &&
            !RegExp(
              r'^\d+(?:[KMGTP])?$',
              caseSensitive: false,
            ).hasMatch(value)) {
          return context.t('Use a size such as 4G or 512M');
        }
        if (key == 'macaddr' &&
            !RegExp(r'^(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$')
                .hasMatch(value)) {
          return context.t('Enter a valid MAC address');
        }
        if (key == 'port_forwards' &&
            value.split(',').any((part) => !validPortForward(part.trim()))) {
          return context.t(
            'Use port pairs from 1 to 65535, for example 8080:80',
          );
        }
        if (key == 'network' &&
            !RegExp(r'^[a-zA-Z0-9_.:-]*$').hasMatch(value)) {
          return context.t('Enter a network mode or a valid host bridge name');
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            for (final (key, controller) in fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _field(context, key, controller),
              ),
          ],
        ),
      ),
    );
  }
}
