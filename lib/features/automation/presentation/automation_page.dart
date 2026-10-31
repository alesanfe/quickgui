import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/features/automation/domain/automation_profile.dart';
import 'package:quickgui/features/automation/domain/automation_run.dart';
import 'package:quickgui/features/automation/providers/automation_providers.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/presentation/version_selection.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';

/// Automation section: describe a machine, let `quickprovision` obtain,
/// install, provision, verify and seal it — the pipeline that turns a
/// cloud/ISO image into a ready-to-use VM in the working directory.
class AutomationPage extends ConsumerStatefulWidget {
  const AutomationPage({super.key});

  @override
  ConsumerState<AutomationPage> createState() => _AutomationPageState();
}

class _AutomationPageState extends ConsumerState<AutomationPage> {
  OperatingSystem? _os;
  Version? _version;
  Option? _option;

  final _name = TextEditingController();
  final _hostname = TextEditingController();
  final _username = TextEditingController(text: 'dev');
  final _cpus = TextEditingController(text: '2');
  final _ram = TextEditingController(text: '4G');
  final _disk = TextEditingController(text: '32G');
  final _packages = TextEditingController(text: 'git, curl, qemu-guest-agent');
  final _services = TextEditingController(text: 'qemu-guest-agent');
  final _snapshot = TextEditingController(text: 'prepared');
  final _sshTimeout = TextEditingController(text: '30');
  bool _shutdown = true;
  final _checks = <String>{'ssh-alive', 'hostname', 'network-dns'};

  @override
  void dispose() {
    for (final c in [
      _name,
      _hostname,
      _username,
      _cpus,
      _ram,
      _disk,
      _packages,
      _services,
      _snapshot,
      _sshTimeout,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _csv(TextEditingController c) => [
    for (final s in c.text.split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  List<AutomationCheck> _selectedChecks(String hostname) {
    final all = defaultChecks(
      hostname: hostname,
      os: _os!.code,
      packages: _csv(_packages),
    );
    return [
      for (final c in all)
        if (_checks.contains(c.name)) c,
    ];
  }

  AutomationProfile _buildProfile() {
    final slug = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : '${_os!.code}-${_version!.version}';
    final hostname = _hostname.text.trim().isNotEmpty
        ? _hostname.text.trim()
        : slug;
    return AutomationProfile(
      os: _os!.code,
      release: _version!.version,
      edition: _option?.option ?? '',
      name: slug,
      cpus: int.tryParse(_cpus.text.trim()) ?? 2,
      ram: _ram.text.trim().isEmpty ? '4G' : _ram.text.trim().toUpperCase(),
      diskSize: _disk.text.trim().isEmpty
          ? '32G'
          : _disk.text.trim().toUpperCase(),
      hostname: hostname,
      username: _username.text.trim().isEmpty ? 'dev' : _username.text.trim(),
      sshTimeoutMin: int.tryParse(_sshTimeout.text.trim()) ?? 30,
      packages: _csv(_packages),
      services: _csv(_services),
      checks: _selectedChecks(hostname),
      shutdown: _shutdown,
      snapshot: _snapshot.text.trim(),
    );
  }

  bool get _formValid =>
      _os != null && _version != null && _username.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(automationControllerProvider);
    final available = ref.watch(automationAvailableProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Automation'))),
      body: switch (available) {
        AsyncData(:final value) when !value => _UnavailableNotice(),
        AsyncError() || AsyncData() => _buildBody(context, ui),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildBody(BuildContext context, AutomationUiState ui) {
    final run = ui.run;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t(
            'Describe the machine you want; quickprovision obtains the image, '
            'installs it, provisions it, verifies the result and seals a '
            'snapshot — a ready-to-use VM appears in Machines.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (run == null) ...[
          _buildForm(context, ui),
          if (ui.plan != null) _PlanCard(plan: ui.plan!),
        ] else
          _RunCard(run: run, log: ui.log),
      ],
    );
  }

  Widget _buildForm(BuildContext context, AutomationUiState ui) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('Machine'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.public),
                  label: Text(_os?.name ?? context.t('Operating system')),
                  onPressed: () => _pickOs(context),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.tag),
                  label: Text(_version?.version ?? context.t('Version')),
                  onPressed: _os == null ? null : () => _pickVersion(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _field(_name, context.t('Name'), width: 220),
                _field(_hostname, context.t('Hostname'), width: 220),
                _field(_username, context.t('Username'), width: 160),
                _field(_cpus, context.t('CPU cores'), width: 110),
                _field(_ram, context.t('RAM'), width: 110),
                _field(_disk, context.t('Disk size'), width: 110),
                _field(_sshTimeout, context.t('SSH timeout (min)'), width: 140),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              _packages,
              context.t('Packages (comma separated)'),
              width: 460,
            ),
            const SizedBox(height: 8),
            _field(
              _services,
              context.t('Services to enable (comma separated)'),
              width: 460,
            ),
            const SizedBox(height: 12),
            Text(
              context.t('Post-install checks'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final c in defaultChecks(
                  hostname: _hostname.text.trim(),
                  os: _os?.code ?? '',
                  packages: _csv(_packages),
                ))
                  FilterChip(
                    label: Text(c.name),
                    selected: _checks.contains(c.name),
                    onSelected: (v) => setState(
                      () => v ? _checks.add(c.name) : _checks.remove(c.name),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    title: Text(context.t('Shut down when done')),
                    value: _shutdown,
                    onChanged: (v) => setState(() => _shutdown = v),
                  ),
                ),
                _field(_snapshot, context.t('Snapshot name'), width: 180),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.preview),
                  label: Text(context.t('Preview plan')),
                  onPressed: _formValid && !ui.busy ? _previewPlan : null,
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: Text(context.t('Start automation run')),
                  onPressed: _formValid && !ui.busy ? _startRun : null,
                ),
                if (ui.busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {double width = 200}) =>
      SizedBox(
        width: width,
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  Future<void> _pickOs(BuildContext context) async {
    final selection = await Navigator.of(context).push<OperatingSystem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const OperatingSystemSelection(),
      ),
    );
    if (selection == null) return;
    setState(() {
      _os = selection;
      _version = null;
      _option = null;
      if (selection.versions.length == 1 &&
          selection.versions.first.options.length == 1) {
        _version = selection.versions.first;
        _option = selection.versions.first.options.first;
      }
      if (_name.text.trim().isEmpty) {
        _name.text = '${selection.code}-dev';
      }
    });
  }

  Future<void> _pickVersion(BuildContext context) async {
    final selection = await Navigator.of(context)
        .push<Tuple2<Version, Option?>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => VersionSelection(operatingSystem: _os!),
          ),
        );
    if (selection == null) return;
    setState(() {
      _version = selection.item1;
      _option = selection.item2;
    });
  }

  Future<void> _previewPlan() async {
    final dir = await ref.read(automationWorkDirProvider.future);
    if (!mounted) return;
    final plan = await ref
        .read(automationControllerProvider.notifier)
        .previewPlan(_buildProfile(), dir);
    if (!mounted) return;
    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t('quickprovision could not resolve this profile.'),
          ),
        ),
      );
    }
  }

  Future<void> _startRun() async {
    final dir = await ref.read(automationWorkDirProvider.future);
    if (!mounted) return;
    await ref
        .read(automationControllerProvider.notifier)
        .start(_buildProfile(), dir);
  }
}

/// Shown when `quickprovision` is not on PATH — the engine ships with
/// quickemu, so this usually means an older backend install.
class _UnavailableNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 48),
          const SizedBox(height: 12),
          Text(
            context.t('The quickprovision binary was not found on PATH.'),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.t(
              'Automation runs need the quickprovision engine that ships '
              'with quickemu. Install or update quickemu and try again.',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

/// The resolved plan: provider plus the steps the engine will run.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final steps = plan['steps'] is List
        ? plan['steps'] as List
        : const <dynamic>[];
    final warnings = plan['warnings'] is List
        ? plan['warnings'] as List
        : const <dynamic>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('Plan — {0}', args: ['${plan['provider'] ?? 'auto'}']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in steps) Chip(label: Text('$s'))],
            ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text('$w')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Live run view: step list, progress bar, verify results and the
/// event log tail.
class _RunCard extends ConsumerWidget {
  const _RunCard({required this.run, required this.log});

  final AutomationRun run;
  final List<String> log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = !run.isTerminal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${run.profileName.isNotEmpty ? run.profileName : run.vmName} '
                    '${run.vmName.isNotEmpty ? '· ${run.vmName}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(run: run),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: running ? run.progress : 1),
            const SizedBox(height: 12),
            for (final s in run.steps) _StepTile(step: s),
            if (run.results.isNotEmpty) ...[
              const Divider(),
              Text(
                context.t('Checks'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final r in run.results)
                ListTile(
                  dense: true,
                  leading: Icon(
                    r.pass ? Icons.check_circle : Icons.error,
                    color: r.pass
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  title: Text(r.name),
                  subtitle: r.output.isNotEmpty
                      ? Text(
                          r.output,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace'),
                        )
                      : null,
                  trailing: r.pass ? null : Text('rc=${r.rc}'),
                ),
            ],
            if (run.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SelectableText(
                  run.error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Divider(),
            ExpansionTile(
              dense: true,
              title: Text(context.t('Event log')),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        log.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(context.t('Copy')),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: log.join('\n'))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (running)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: Text(context.t('Cancel run')),
                    onPressed: () => ref
                        .read(automationControllerProvider.notifier)
                        .cancelRun(),
                  ),
                if (run.status == AutomationRunStatus.failed)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.replay),
                    label: Text(context.t('Resume run')),
                    onPressed: () => ref
                        .read(automationControllerProvider.notifier)
                        .resume(),
                  ),
                if (run.isTerminal) ...[
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add),
                    label: Text(context.t('New run')),
                    onPressed: () {
                      ref.invalidate(vmLibraryProvider);
                      ref.read(automationControllerProvider.notifier).reset();
                    },
                  ),
                  if (run.status == AutomationRunStatus.completed)
                    FilledButton.icon(
                      icon: const Icon(Icons.computer),
                      label: Text(context.t('Open in Machines')),
                      onPressed: () {
                        ref.invalidate(vmLibraryProvider);
                        GoRouter.maybeOf(context)?.go('/machines');
                      },
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.run});

  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (run.status) {
      AutomationRunStatus.running => (
        context.t('Running'),
        Theme.of(context).colorScheme.primary,
      ),
      AutomationRunStatus.completed => (context.t('Completed'), Colors.green),
      AutomationRunStatus.failed => (
        context.t('Failed'),
        Theme.of(context).colorScheme.error,
      ),
      AutomationRunStatus.cancelled => (
        context.t('Cancelled'),
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      AutomationRunStatus.idle => (
        context.t('Idle'),
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Chip(
      label: Text(label),
      side: BorderSide(color: color),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final AutomationStep step;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.status) {
      AutomationStepStatus.pending => (
        Icons.radio_button_unchecked,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      AutomationStepStatus.running => (
        Icons.hourglass_top,
        Theme.of(context).colorScheme.primary,
      ),
      AutomationStepStatus.done => (Icons.check_circle, Colors.green),
      AutomationStepStatus.failed => (
        Icons.error,
        Theme.of(context).colorScheme.error,
      ),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text('${step.index}. ${step.id}'),
      subtitle: step.error.isNotEmpty
          ? Text(
              step.error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          : step.message.isNotEmpty
          ? Text(step.message, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
    );
  }
}
