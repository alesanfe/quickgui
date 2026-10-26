import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:go_router/go_router.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/activity/presentation/operation_tile.dart';
import 'package:quickgui/features/activity/presentation/activity_page.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/providers/vm_library_providers.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(vmLibraryProvider);
    final activity = ref.watch(activityProvider);
    final available = ref.watch(backendAvailableProvider);
    final free = ref.watch(hostFreeSpaceProvider);
    final machines = library.asData?.value ?? const <LibraryMachine>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Home')),
        actions: [
          IconButton(
            tooltip: context.t('Refresh'),
            onPressed: () {
              ref.invalidate(vmLibraryProvider);
              ref.invalidate(hostFreeSpaceProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.t('Welcome to Quickgui'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(context.t('Create, run and manage your virtual machines.')),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                key: const ValueKey('nav.create-machine'),
                onPressed: () => context.go('/create'),
                icon: const Icon(Icons.add),
                label: Text(context.t('Create a machine')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('nav.import-disk'),
                onPressed: () => context.go('/create'),
                icon: const Icon(Icons.upload_file),
                label: Text(context.t('Import a disk image')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('nav.machines'),
                onPressed: () => context.go('/machines'),
                icon: const Icon(Icons.computer),
                label: Text(context.t('Machines')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                context,
                Icons.computer,
                context.t('Machines'),
                '${machines.length}',
              ),
              _metric(
                context,
                Icons.play_circle,
                context.t('Running'),
                '${machines.where((m) => m.active).length}',
              ),
              _metric(
                context,
                Icons.warning_amber,
                context.t('Warnings'),
                '${machines.where((m) => m.state == 'stale').length}',
              ),
              _metric(
                context,
                Icons.storage,
                context.t('Free disk space'),
                free.when(
                  data: (value) => value == null ? '—' : formatBytes(value),
                  loading: () => '…',
                  error: (_, _) => '—',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(
                available.asData?.value == true
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
              ),
              title: Text(context.t('Backend status')),
              subtitle: Text(
                available.when(
                  data: (ok) => ok
                      ? context.t('Quickemu is available')
                      : context.t(
                          'Quickemu is unavailable. Open diagnostics for installation help.',
                        ),
                  loading: () => context.t('Checking…'),
                  error: (_, _) => context.t('Could not check Quickemu'),
                ),
              ),
              trailing: TextButton(
                onPressed: () => context.go('/diagnostics'),
                child: Text(context.t('Diagnostics')),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.t('Machines'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          library.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Card(
              child: ListTile(
                title: Text(context.t('Could not load machines')),
                subtitle: Text('$error'),
                trailing: IconButton(
                  tooltip: context.t('Retry'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(vmLibraryProvider),
                ),
              ),
            ),
            data: (items) => items.isEmpty
                ? Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('No virtual machines yet'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.t(
                              'Choose an operating system or import an existing image to get started.',
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => context.go('/create'),
                            child: Text(context.t('Create your first machine')),
                          ),
                        ],
                      ),
                    ),
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final machine in items.take(6))
                        SizedBox(
                          width: 300,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.computer),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          machine.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(machine.state),
                                  Text(
                                    '${machine.values['cpu_cores'] ?? '—'} CPU · ${machine.values['ram'] ?? '—'} RAM',
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: () => context.push(
                                      '/machines/${Uri.encodeComponent(machine.name)}',
                                    ),
                                    child: Text(context.t('Open details')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('Recent activity'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => context.go('/activity'),
                child: Text(context.t('View all')),
              ),
            ],
          ),
          for (final operation in activity.active) OperationTile(op: operation),
          for (final entry in activity.history.take(5))
            HistoryEntryTile(entry: entry),
          if (activity.active.isEmpty && activity.history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t(
                  'No activity yet. Downloads and machine operations will show up here.',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(label),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
