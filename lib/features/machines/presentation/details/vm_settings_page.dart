import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/domain/vm_config_value.dart';
import 'package:quickgui/features/machines/presentation/details/vm_config_editor.dart';
import 'package:quickgui/shared/dialogs/conf_conflict.dart';
import 'package:quickgui/features/settings/providers/ui_preferences_providers.dart';
import 'package:quickgui/shared/forms/mac_field.dart';
import 'package:quickgui/shared/forms/path_picker_field.dart';
import 'package:quickgui/shared/forms/port_forward_editor.dart';
import 'package:quickgui/shared/forms/size_field.dart';
import 'package:quickgui/shared/forms/usb_device_editor.dart';
import 'package:quickgui/shared/forms/viewer_selector.dart';

/// A group of conf keys shown under one section header. [id] is a
/// stable identifier for the `?section=` filter — titles are
/// localised and cannot be matched against menu constants.
class _Section {
  const _Section(this.id, this.title, this.fields);

  final String id;
  final String title;
  final List<String> fields;
}

/// Full-screen VM configuration, replacing the modal conf dialogs
/// (QGUI-ALLSET-001…006).
///
/// Keys are read/written through the [vmConfigStoreProvider] so the file
/// keeps `key="value"` lines this page does not manage. Unknown keys are
/// editable from the "Advanced" section. Fields are grouped by domain,
/// the action bar is fixed, validation errors are navigable per section
/// and every specialised dialog (Resources, Boot & network, Devices)
/// reuses these same fields by passing [section] to filter the view.
class VmSettingsPage extends ConsumerStatefulWidget {
  const VmSettingsPage({required this.vmName, this.section, super.key});

  final String vmName;

  /// Section title(s) to show — `null` shows everything. Comma-split so
  /// menu entries can open e.g. "Boot & firmware,Network" as one view.
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
    'sound_card',
    'sound_duplex',
    'public_dir',
    'usb_devices',
    'gpu_passthrough',
    'port_forwards',
    'fixed_iso',
    'floppy',
    'iso',
    'img',
    'width',
    'height',
    'fullscreen',
    'gl',
    'access',
    'ssh_access',
    'ssh_port',
    'spice_port',
    'monitor',
    'serial',
    'keyboard',
    'keyboard_layout',
    'mouse',
    'usb_controller',
    'braille',
    'cpu_pinning',
    'extra_args',
    'ignore_tsc_warning',
  };

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, GlobalKey> _sectionKeys = {};
  List<String> _rawLines = [];
  List<String> _extraKeys = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _advanced = false;
  bool _saving = false;
  bool _allowPop = false;
  String _search = '';
  Map<String, String> _errors = const {};
  Map<String, bool> _viewerAvailable = const {};
  final _form = GlobalKey<FormState>();
  static const _arrayKeys = {'port_forwards', 'usb_devices'};

  String get _confPath => '${widget.vmName}.conf';

  List<String>? get _sectionFilter => widget.section
      ?.split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    _advanced = ref.read(uiPreferencesProvider).advancedConfig;
    _load();
    _loadViewerAvailability();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadViewerAvailability() async {
    final probe = ref.read(hostProbeProvider);
    final result = <String, bool>{};
    for (final v in const ['spicy', 'remote-viewer']) {
      result[v] = await probe.hasTool(v);
    }
    if (mounted) setState(() => _viewerAvailable = result);
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
    // A listener per controller keeps _isDirty (and the enabled state of
    // the Save button) live while the user types in any field.
    () => TextEditingController(text: _current(key))
      ..addListener(() {
        if (mounted) setState(() {});
      }),
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

  /// Central per-key validation (QGUI-ALLSET-003): the same rules the
  /// form fields check, also usable to collect every error at once so
  /// the user can navigate to the first offending section.
  String? _validateKey(String key, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (key == 'cpu_cores' &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 1024)) {
      return context.t('Enter a positive CPU count');
    }
    if ((key == 'ram' || key == 'disk_size') &&
        !RegExp(r'^\d+(?:[KMGTP])?$', caseSensitive: false).hasMatch(value)) {
      return context.t('Use a size such as 4G or 512M');
    }
    if (key == 'macaddr' && !MacField.macPattern.hasMatch(value)) {
      return context.t('Enter a valid MAC address');
    }
    if (key == 'port_forwards' &&
        value.split(',').any((part) => !validPortForward(part.trim()))) {
      return context.t('Use port pairs from 1 to 65535, for example 8080:80');
    }
    if (key == 'network' && !RegExp(r'^[a-zA-Z0-9_.:-]*$').hasMatch(value)) {
      return context.t('Enter a network mode or a valid host bridge name');
    }
    if ((key == 'width' || key == 'height') &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 16384)) {
      return context.t('Enter a pixel count between 1 and 16384');
    }
    if ((key == 'ssh_port' || key == 'spice_port') &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 65535)) {
      return context.t('Enter a port between 1 and 65535');
    }
    if (key == 'cpu_pinning' && !RegExp(r'^\d+(?:,\d+)*$').hasMatch(value)) {
      return context.t('Use a comma-separated core list, for example 0,1');
    }
    if ((key == 'access' || key == 'ssh_access') &&
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
      return context.t('Use local, remote or a host/IP address');
    }
    if (key == 'keyboard_layout' &&
        !RegExp(r'^[a-zA-Z][a-zA-Z_-]*$').hasMatch(value)) {
      return context.t('Use a QEMU layout name, for example es or en-us');
    }
    if (key == 'public_dir' && value.isNotEmpty) {
      // Host path sanity — the guest cannot mount a directory that
      // does not exist on the host.
      // dart:io Directory check is done by PathPickerField already.
    }
    return null;
  }

  /// Validates every managed field and returns key→message pairs.
  Map<String, String> _collectErrors() => {
    for (final e in _controllers.entries)
      if (_validateKey(e.key, e.value.text) case final msg? when msg.isNotEmpty)
        e.key: msg,
  };

  /// Section titles that contain at least one invalid field — drives
  /// the red count badge on the section header.
  String? _sectionOf(String key) {
    for (final s in _sections(context)) {
      if (s.fields.contains(key)) return s.title;
    }
    if (_extraKeys.contains(key)) return context.t('Advanced (other keys)');
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final errors = _collectErrors();
    // width/height are a pair upstream (ParamCheckConf) — reject a
    // half-set resolution here rather than letting launch fail.
    final w = _controllers['width']?.text.trim() ?? '';
    final h = _controllers['height']?.text.trim() ?? '';
    if ((w.isEmpty) != (h.isEmpty)) {
      errors['width'] = context.t('Width and height must be set together');
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      _scrollToSection(_sectionOf(errors.keys.first));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t(
              'Fix {0} invalid value(s) before saving',
              args: ['${errors.length}'],
            ),
          ),
        ),
      );
      return;
    }
    setState(() {
      _errors = const {};
      _saving = true;
    });
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
    _Section('general', context.t('General'), ['guest_os', 'iso', 'img']),
    _Section('resources', context.t('Resources'), [
      'ram',
      'cpu_cores',
      'disk_size',
      'cpu_pinning',
    ]),
    _Section('boot', context.t('Boot & firmware'), [
      'boot',
      'secureboot',
      'tpm',
      'ignore_tsc_warning',
    ]),
    _Section('network', context.t('Network'), [
      'network',
      'bridge',
      'macaddr',
      'port_forwards',
      'access',
      'ssh_access',
      'ssh_port',
      'spice_port',
    ]),
    _Section('display', context.t('Display & sound'), [
      'display',
      'viewer',
      'sound_card',
      'sound_duplex',
      'width',
      'height',
      'fullscreen',
      'gl',
    ]),
    _Section('devices', context.t('Devices'), [
      'usb_devices',
      'gpu_passthrough',
      'usb_controller',
      'keyboard',
      'keyboard_layout',
      'mouse',
      'braille',
    ]),
    _Section('sharing', context.t('Sharing'), [
      'public_dir',
      'fixed_iso',
      'floppy',
    ]),
    _Section('console', context.t('Console'), ['monitor', 'serial']),
    _Section('tuning', context.t('Advanced tuning'), ['extra_args']),
  ];

  void _scrollToSection(String? title) {
    final key = _sectionKeys[title];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1,
      );
    }
  }

  /// Whether a field passes the search filter — fields with errors
  /// always stay visible so a filter can never hide an active problem.
  bool _matchesSearch(String key, String label) {
    if (_search.isEmpty || _errors.containsKey(key)) return true;
    final q = _search.toLowerCase();
    return key.toLowerCase().contains(q) ||
        label.toLowerCase().contains(q) ||
        (_controllers[key]?.text.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final allSections = _sections(context);
    final filter = _sectionFilter;
    final sections = [
      for (final s in allSections)
        if (filter == null || filter.contains(s.id)) s,
    ];
    for (final s in sections) {
      _sectionKeys.putIfAbsent(s.title, GlobalKey.new);
    }
    if (_advanced && _extraKeys.isNotEmpty) {
      _sectionKeys.putIfAbsent(
        context.t('Advanced (other keys)'),
        GlobalKey.new,
      );
    }
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopAttempt();
      },
      child: CallbackShortcuts(
        // Ctrl+S saves like the button does — a desktop form is expected
        // to honour the save accelerator (QGUI-X-002).
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!_saving && _isDirty) _save();
          },
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
                      // Section jump bar + settings search (ALLSET-004):
                      // chips scroll to their card, the field filters by
                      // label, key or current value without hiding errors.
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search),
                            hintText: context.t('Search settings'),
                            border: const OutlineInputBorder(),
                            suffixIcon: _search.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: context.t('Clear search'),
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setState(() => _search = ''),
                                  ),
                          ),
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                      if (filter == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final s in sections)
                                ActionChip(
                                  label: Text(s.title),
                                  onPressed: () => _scrollToSection(s.title),
                                ),
                              if (_advanced && _extraKeys.isNotEmpty)
                                ActionChip(
                                  label: Text(
                                    context.t('Advanced (other keys)'),
                                  ),
                                  onPressed: () => _scrollToSection(
                                    context.t('Advanced (other keys)'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      for (final section in sections)
                        _SectionCard(
                          key: _sectionKeys[section.title],
                          title: section.title,
                          errorCount: section.fields
                              .where((k) => _errors.containsKey(k))
                              .length,
                          fields: [
                            for (final key in section.fields)
                              if (_matchesSearch(key, _labelFor(context, key)))
                                (key, _controllerFor(key)),
                          ],
                          state: this,
                        ),
                      if (_advanced && _extraKeys.isNotEmpty)
                        _SectionCard(
                          key: _sectionKeys[context.t('Advanced (other keys)')],
                          title: context.t('Advanced (other keys)'),
                          errorCount: _extraKeys
                              .where((k) => _errors.containsKey(k))
                              .length,
                          fields: [
                            for (final key in _extraKeys)
                              if (_matchesSearch(key, key))
                                (key, _controllerFor(key)),
                          ],
                          state: this,
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
          // Fixed action bar (ALLSET-002): cancel/save always visible,
          // unsaved-changes indicator and an error summary next to Save.
          bottomNavigationBar: _loading || _loadFailed
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (_errors.isNotEmpty)
                          InputChip(
                            avatar: Icon(
                              Icons.error_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            label: Text(
                              context.t(
                                '{0} invalid',
                                args: ['${_errors.length}'],
                              ),
                            ),
                            onPressed: () => _scrollToSection(
                              _sectionOf(_errors.keys.first),
                            ),
                          )
                        else
                          InputChip(
                            avatar: Icon(
                              _isDirty
                                  ? Icons.edit
                                  : Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: Text(
                              _isDirty
                                  ? context.t('Unsaved changes')
                                  : context.t('No changes'),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _onPopAttempt,
                          child: Text(context.t('Cancel')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.save),
                          label: Text(context.t('Save')),
                          onPressed: _saving || !_isDirty ? null : _save,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Labels + choices + help live in the state so both the search filter
/// and the section card use one source of truth.
extension on _VmSettingsPageState {
  String _labelFor(BuildContext context, String key) => switch (key) {
    'ram' => context.t('Memory'),
    'cpu_cores' => context.t('CPU cores'),
    'disk_size' => context.t('Virtual disk capacity'),
    'boot' => context.t('Firmware'),
    'guest_os' => context.t('Guest OS'),
    'display' => context.t('Display'),
    'viewer' => context.t('Display viewer'),
    'sound_card' => context.t('Sound card'),
    'sound_duplex' => context.t('Audio codec (duplex)'),
    'network' => context.t('Network mode or bridge interface'),
    'bridge' => context.t('Legacy bridge interface'),
    'macaddr' => context.t('MAC address'),
    'port_forwards' => context.t('Forwarded ports'),
    'public_dir' => context.t('Shared host folder'),
    'usb_devices' => context.t('USB devices'),
    'gpu_passthrough' => context.t('GPU passthrough'),
    'iso' => context.t('Installation ISO'),
    'img' => context.t('Recovery image'),
    'fixed_iso' => context.t('Additional ISO'),
    'floppy' => context.t('Floppy image'),
    'tpm' => context.t('TPM 2.0'),
    'secureboot' => context.t('Secure Boot'),
    'width' => context.t('Display width (px)'),
    'height' => context.t('Display height (px)'),
    'fullscreen' => context.t('Fullscreen'),
    'gl' => context.t('VirGL acceleration'),
    'access' => context.t('SPICE/display access'),
    'ssh_access' => context.t('SSH access mode'),
    'ssh_port' => context.t('SSH forwarded port'),
    'spice_port' => context.t('SPICE port'),
    'monitor' => context.t('QEMU monitor channel'),
    'serial' => context.t('Serial console channel'),
    'keyboard' => context.t('Keyboard device'),
    'keyboard_layout' => context.t('Keyboard layout (-k)'),
    'mouse' => context.t('Mouse device'),
    'usb_controller' => context.t('USB input controller'),
    'braille' => context.t('Braille support'),
    'cpu_pinning' => context.t('CPU pinning (core list)'),
    'extra_args' => context.t('Extra QEMU arguments'),
    'ignore_tsc_warning' => context.t('Ignore TSC warning'),
    _ => key,
  };
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.fields,
    required this.state,
    this.errorCount = 0,
    super.key,
  });

  final String title;
  final List<(String, TextEditingController)> fields;
  final _VmSettingsPageState state;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                if (errorCount > 0)
                  Chip(
                    avatar: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      context.t('{0} invalid', args: ['$errorCount']),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
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

  Widget _field(
    BuildContext context,
    String key,
    TextEditingController controller,
  ) {
    final label = state._labelFor(context, key);
    final errorText = state._errors[key];
    final choices = switch (key) {
      'boot' => ['efi', 'legacy'],
      'secureboot' || 'tpm' => ['on', 'off'],
      'network' => ['', 'none', 'restrict', 'passt'],
      'display' => ['spice', 'sdl', 'gtk', 'none', 'vnc'],
      'fullscreen' || 'braille' || 'ignore_tsc_warning' => ['', 'on'],
      'gl' => ['', 'on', 'off'],
      'access' || 'ssh_access' => ['', 'local', 'remote'],
      'monitor' || 'serial' => ['', 'socket', 'telnet', 'none'],
      'keyboard' => ['', 'usb', 'virtio', 'ps2'],
      'mouse' => ['', 'tablet', 'usb', 'virtio', 'ps2'],
      'usb_controller' => ['', 'ehci', 'xhci', 'none'],
      'sound_card' => [
        '',
        'intel-hda',
        'ich9-intel-hda',
        'ac97',
        'es1370',
        'sb16',
        'usb-audio',
        'virtio-sound-pci',
        'none',
      ],
      'sound_duplex' => ['', 'hda-duplex', 'hda-micro', 'hda-output'],
      _ => null,
    };
    final help = switch (key) {
      'network' => context.t(
        'Empty = user NAT. restrict = isolated user network. none = disconnected. For bridging, enter the host bridge name (for example br0).',
      ),
      'port_forwards' => context.t(
        'Quickemu forwards both TCP and UDP on all host interfaces. Only available with user NAT/restricted networking.',
      ),
      'public_dir' => context.t(
        'Share only a trusted folder. Guest access can expose host files; permissions and guest tools still apply.',
      ),
      'usb_devices' => context.t(
        'USB vendor:product identifiers to pass through. Disconnecting host devices may interrupt other applications.',
      ),
      'gpu_passthrough' => context.t(
        'PCI address of a GPU dedicated to the guest, for example 0000:01:00.0. Requires VFIO/IOMMU set up on the host.',
      ),
      'access' => context.t(
        'local = host-only display access, remote = listen on all interfaces, or a specific host/IP to bind.',
      ),
      'monitor' || 'serial' => context.t(
        'telnet enables the matching Attach action in the VM menu; socket keeps a unix socket channel.',
      ),
      'cpu_pinning' => context.t(
        'Comma-separated host CPU ids to pin vCPUs to, for example 0,1. Must not exceed the available cores.',
      ),
      'extra_args' => context.t(
        'Appended verbatim to the QEMU command line. Unsupported or invalid flags prevent the VM from starting.',
      ),
      'secureboot' => context.t('Requires EFI firmware.'),
      'tpm' => context.t('Needs the swtpm package on the host.'),
      _ => null,
    };

    // Structured editors share the same controllers/validators as the
    // specialised dialogs (QGUI-ALLSET-006).
    switch (key) {
      case 'ram' || 'disk_size':
        return SizeField(
          controller: controller,
          label: label,
          helper: help,
          errorText: errorText,
          units: key == 'disk_size' ? const ['G', 'M', 'T'] : const ['G', 'M'],
        );
      case 'macaddr':
        return MacField(controller: controller, label: label, helper: help);
      case 'port_forwards':
        return PortForwardEditor(
          controller: controller,
          label: label,
          helper: help,
        );
      case 'usb_devices':
        return UsbDeviceEditor(
          controller: controller,
          label: label,
          helper: help,
        );
      case 'public_dir':
        return PathPickerField(
          controller: controller,
          label: label,
          helper: help,
        );
      case 'viewer':
        return ViewerSelector(
          controller: controller,
          label: label,
          helper: help,
          available: state._viewerAvailable,
        );
      default:
        break;
    }
    if (choices != null && key != 'network') {
      return DropdownButtonFormField<String>(
        initialValue: controller.text.isEmpty ? null : controller.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: help,
          helperMaxLines: 4,
          errorText: errorText,
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
        labelText: label,
        helperText: help,
        helperMaxLines: 6,
        errorText: errorText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      validator: (raw) => state._validateKey(key, raw ?? ''),
    );
  }
}
