import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// Activity centre: tabbed view of in-flight operations plus the
/// persisted history, filterable by status, kind, target, age,
/// retryability, attention state and free text (QG-014). Filters are
/// persisted across sessions.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

enum _StatusTab { running, succeeded, failed, cancelled, all }

class _ActivityPageState extends ConsumerState<ActivityPage> {
  _StatusTab _tab = _StatusTab.all;
  ActivityFilter _filter = const ActivityFilter();
  final _searchCtrl = TextEditingController();
  var _restored = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _restoreFilters() async {
    final prefs = ref.read(preferencesRepositoryProvider);
    final raw = await prefs.getAs<String>(prefActivityFilters);
    if (!mounted || raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        setState(() {
          _filter = ActivityFilter.fromJson(json);
          _searchCtrl.text = _filter.query;
          _tab = switch (_filter.status) {
            OperationStatus.succeeded => _StatusTab.succeeded,
            OperationStatus.failed => _StatusTab.failed,
            OperationStatus.cancelled => _StatusTab.cancelled,
            _ => _StatusTab.all,
          };
        });
      }
    } catch (_) {
      // Corrupt preference: keep defaults.
    }
  }

  void _apply(ActivityFilter next) {
    setState(() => _filter = next);
    final prefs = ref.read(preferencesRepositoryProvider);
    prefs.set(prefActivityFilters, jsonEncode(next.toJson()));
  }

  void _setTab(_StatusTab tab) {
    setState(() => _tab = tab);
    _apply(
      _filter.copyWith(
        status: () => switch (tab) {
          _StatusTab.succeeded => OperationStatus.succeeded,
          _StatusTab.failed => OperationStatus.failed,
          _StatusTab.cancelled => OperationStatus.cancelled,
          _ => null,
        },
      ),
    );
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() => _tab = _StatusTab.all);
    _apply(const ActivityFilter());
  }

  static final _timeRanges = <(Duration?, String)>[
    (null, 'All time'),
    (const Duration(hours: 1), 'Last hour'),
    (const Duration(hours: 24), 'Last 24 hours'),
    (const Duration(days: 7), 'Last 7 days'),
    (const Duration(days: 30), 'Last 30 days'),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_restored) {
      _restored = true;
      _restoreFilters();
    }
    final activity = ref.watch(activityProvider);
    final all = activity.history;
    final now = DateTime.now();
    final counts = <OperationStatus, int>{
      for (final s in OperationStatus.values)
        s: all.where((e) => e.status == s).length,
    };
    final interrupted = counts[OperationStatus.interrupted] ?? 0;
    final cancelledCount =
        (counts[OperationStatus.cancelled] ?? 0) + interrupted;
    final kinds = all.map((e) => e.kind).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final targets = all.map((e) => e.target).toSet().toList()..sort();

    final filtered = [
      for (final e in all)
        if (_filter.matches(e, now)) e,
    ];
    final visibleActive = [
      for (final op in activity.active)
        if ((_filter.kind == null || op.kind == _filter.kind) &&
            (_filter.target == null || op.target == _filter.target) &&
            (_filter.query.isEmpty ||
                '${op.target} ${op.kind.wire}'.toLowerCase().contains(
                  _filter.query.toLowerCase(),
                )))
          op,
    ];

    final tabs = [
      (context.t('In progress'), activity.active.length),
      (context.t('Completed'), counts[OperationStatus.succeeded] ?? 0),
      (context.t('Failed'), counts[OperationStatus.failed] ?? 0),
      (context.t('Cancelled'), cancelledCount),
      (context.t('All'), all.length),
    ];
    final requiresActionCount = all.where((e) => e.requiresAction).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Activity')),
        actions: [
          if (_filter.isActive || _tab != _StatusTab.all)
            IconButton(
              tooltip: context.t('Clear filters'),
              icon: const Icon(Icons.filter_alt_off),
              onPressed: _clearFilters,
            ),
          if (all.isNotEmpty)
            IconButton(
              tooltip: context.t('Clear history'),
              icon: const Icon(Icons.clear_all),
              onPressed: () =>
                  ref.read(activityProvider.notifier).clearHistory(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: context.t('Search by machine, message or error code'),
              suffixIcon: _filter.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.t('Clear search'),
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _apply(_filter.copyWith(query: ''));
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => _apply(_filter.copyWith(query: v.trim())),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < tabs.length; i++)
                FilterChip(
                  selected: _tab == _StatusTab.values[i],
                  label: Text(
                    tabs[i].$2 > 0
                        ? '${tabs[i].$1} (${tabs[i].$2})'
                        : tabs[i].$1,
                  ),
                  onSelected: (_) => _setTab(_StatusTab.values[i]),
                ),
              const VerticalDivider(),
              if (kinds.length > 1)
                PopupMenuButton<OperationKind?>(
                  tooltip: context.t('Filter by type'),
                  onSelected: (k) => _apply(_filter.copyWith(kind: () => k)),
                  itemBuilder: (context) => [
                    PopupMenuItem(child: Text(context.t('All types'))),
                    for (final k in kinds)
                      PopupMenuItem(
                        value: k,
                        child: Text(operationKindLabel(context, k)),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(
                      _filter.kind == null
                          ? context.t('Type')
                          : operationKindLabel(context, _filter.kind!),
                    ),
                  ),
                ),
              if (targets.length > 1)
                PopupMenuButton<String?>(
                  tooltip: context.t('Filter by machine'),
                  onSelected: (t) => _apply(_filter.copyWith(target: () => t)),
                  itemBuilder: (context) => [
                    PopupMenuItem(child: Text(context.t('All machines'))),
                    for (final t in targets)
                      PopupMenuItem(value: t, child: Text(t)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.computer, size: 18),
                    label: Text(_filter.target ?? context.t('Machine')),
                  ),
                ),
              PopupMenuButton<Duration?>(
                tooltip: context.t('Filter by time'),
                onSelected: (d) => _apply(_filter.copyWith(maxAge: () => d)),
                itemBuilder: (context) => [
                  for (final (duration, label) in _timeRanges)
                    PopupMenuItem(
                      value: duration,
                      child: Text(context.t(label)),
                    ),
                ],
                child: Chip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(
                    context.t(
                      _timeRanges
                          .firstWhere(
                            (e) => e.$1 == _filter.maxAge,
                            orElse: () => _timeRanges.first,
                          )
                          .$2,
                    ),
                  ),
                ),
              ),
              FilterChip(
                selected: _filter.retryableOnly,
                label: Text(context.t('Retryable only')),
                onSelected: (v) => _apply(_filter.copyWith(retryableOnly: v)),
              ),
              FilterChip(
                selected: _filter.requiresActionOnly,
                avatar: requiresActionCount > 0
                    ? Badge(label: Text('$requiresActionCount'))
                    : null,
                label: Text(context.t('Requires action')),
                onSelected: (v) =>
                    _apply(_filter.copyWith(requiresActionOnly: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == _StatusTab.running || _tab == _StatusTab.all) ...[
            if (visibleActive.isNotEmpty)
              _SectionHeader(context.t('In progress')),
            for (final op in visibleActive) OperationTile(op: op),
            if (visibleActive.isNotEmpty) const SizedBox(height: 16),
          ],
          if (filtered.isNotEmpty || visibleActive.isNotEmpty)
            _SectionHeader(context.t('History')),
          if (filtered.isEmpty && visibleActive.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !_filter.isActive
                          ? context.t(
                              'No activity yet. Downloads and machine '
                              'operations will show up here.',
                            )
                          : context.t(
                              'No operations match the current filters.',
                            ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            for (final e in filtered) _HistoryTile(entry: e),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Icon per operation kind.
IconData operationKindIcon(OperationKind kind) => switch (kind) {
  OperationKind.download => Icons.download,
  OperationKind.start => Icons.play_arrow,
  OperationKind.stop => Icons.stop,
  OperationKind.clone => Icons.content_copy,
  OperationKind.export => Icons.archive,
  OperationKind.verify => Icons.verified,
  OperationKind.resize => Icons.expand,
  OperationKind.snapshot => Icons.photo_camera,
  OperationKind.delete => Icons.delete,
  OperationKind.import => Icons.upload_file,
  OperationKind.convert => Icons.transform,
  OperationKind.restore => Icons.restore,
  OperationKind.command => Icons.terminal,
  OperationKind.automation => Icons.auto_awesome,
};

/// Title per operation kind.
String operationKindLabel(BuildContext context, OperationKind kind) =>
    switch (kind) {
      OperationKind.download => context.t('Download'),
      OperationKind.start => context.t('Start'),
      OperationKind.stop => context.t('Stop'),
      OperationKind.clone => context.t('Clone'),
      OperationKind.export => context.t('Export'),
      OperationKind.verify => context.t('Verify image'),
      OperationKind.resize => context.t('Resize disk'),
      OperationKind.snapshot => context.t('Snapshots'),
      OperationKind.delete => context.t('Delete'),
      OperationKind.import => context.t('Import'),
      OperationKind.convert => context.t('Convert'),
      OperationKind.restore => context.t('Restore'),
      OperationKind.command => context.t('Command'),
      OperationKind.automation => context.t('Automation run'),
    };

class OperationTile extends ConsumerWidget {
  const OperationTile({required this.op, super.key});
  final AppOperation op;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = switch (op.state) {
      OperationRunning(:final progress?) => progress,
      OperationPaused(:final progress?) => progress,
      _ => null,
    };
    final subtitle = switch (op.state) {
      OperationRunning(:final progress?) => '${(progress * 100).toInt()}%',
      OperationRunning() => context.t('Running'),
      OperationQueued() => context.t('Queued'),
      OperationPaused() => context.t('Paused'),
      OperationCancelling() => context.t('Cancelling'),
      OperationValidating() => context.t('Validating'),
      OperationWaitingForConfirmation() => context.t(
        'Waiting for confirmation',
      ),
      _ => context.t('Running'),
    };
    return Card(
      child: ListTile(
        onTap: op.output.isEmpty
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(op.target),
                  content: SizedBox(
                    width: 720,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        op.output,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.t('Dismiss')),
                    ),
                  ],
                ),
              ),
        leading: Icon(operationKindIcon(op.kind)),
        title: Text('${operationKindLabel(context, op.kind)} — ${op.target}'),
        // Live region: screen readers announce state transitions
        // (queued → running → % → terminal) without a focus change.
        subtitle: Semantics(
          liveRegion: true,
          label:
              '${operationKindLabel(context, op.kind)} ${op.target}: $subtitle',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (op.output.isNotEmpty)
                Text(
                  op.output.trim().split('\n').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
        trailing: op.onCancel != null && !op.isTerminal
            ? IconButton(
                tooltip: context.t('Cancel'),
                icon: const Icon(Icons.cancel_outlined),
                onPressed: () => ref.read(activityProvider.notifier).cancel(op),
              )
            : null,
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry});
  final OperationHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, statusLabel) = switch (entry.status) {
      OperationStatus.succeeded => (
        Icons.check_circle_outline,
        Colors.green,
        context.t('Completed'),
      ),
      OperationStatus.failed => (
        Icons.error_outline,
        scheme.error,
        entry.retryable ? context.t('Failed (retryable)') : context.t('Failed'),
      ),
      OperationStatus.cancelled => (
        Icons.cancel_outlined,
        scheme.onSurfaceVariant,
        context.t('Cancelled'),
      ),
      OperationStatus.interrupted => (
        Icons.help_outline,
        scheme.tertiary,
        context.t('Interrupted'),
      ),
    };
    final notifier = ref.read(activityProvider.notifier);
    final attempt = notifier.attemptNumber(entry);
    // Watch the provider so the retry button hides while a retry is
    // actually in flight (QG-015: no duplicate concurrent retries).
    ref.watch(activityProvider);
    final inFlight = notifier.retryInFlight(entry);
    final lifecycleLabel = switch (entry.lifecycle) {
      OperationLifecycle.retrying => context.t('Retrying'),
      OperationLifecycle.recovered => context.t('Recovered'),
      OperationLifecycle.permanentlyFailed => context.t('Permanently failed'),
      OperationLifecycle.acknowledged => context.t('Acknowledged'),
      OperationLifecycle.ignored => context.t('Ignored'),
      OperationLifecycle.requiresAction => context.t('Requires action'),
      _ => null,
    };
    return ListTile(
      dense: true,
      leading: Icon(operationKindIcon(entry.kind)),
      title: Text(
        '${operationKindLabel(context, entry.kind)} — ${entry.target}'
        '${attempt > 1 ? context.t(' (attempt {0})', args: ['$attempt']) : ''}'
        '${entry.occurrences > 1 ? ' ×${entry.occurrences}' : ''}',
      ),
      subtitle: Text(
        '${_formatTime(entry.completedAt)}'
        '${lifecycleLabel != null ? ' — $lifecycleLabel' : ''}'
        '${entry.failureCode != null ? ' — ${entry.failureCode}' : ''}'
        '${entry.message.isNotEmpty ? ' — ${entry.message}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.retryable &&
              entry.retrySpec != null &&
              entry.retrySpec!.regeneratesPlan)
            Tooltip(
              message: context.t(
                'Needs a fresh plan — re-run from the VM actions',
              ),
              child: Icon(Icons.refresh, color: scheme.onSurfaceVariant),
            ),
          if (entry.canRetry && !inFlight)
            IconButton(
              tooltip: context.t('Retry'),
              icon: const Icon(Icons.replay),
              onPressed: () => _retry(context, ref),
            ),
          if (entry.requiresAction)
            IconButton(
              tooltip: context.t('Acknowledge'),
              icon: const Icon(Icons.check),
              onPressed: () =>
                  ref.read(activityProvider.notifier).acknowledge(entry),
            ),
          if (entry.status == OperationStatus.failed ||
              entry.status == OperationStatus.interrupted)
            IconButton(
              tooltip: context.t('Copy diagnostic'),
              icon: const Icon(Icons.content_copy, size: 18),
              onPressed: () => _copyDiagnostic(context),
            ),
          Icon(icon, color: color, semanticLabel: statusLabel),
        ],
      ),
    );
  }

  Future<void> _copyDiagnostic(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.toDiagnosticLine()));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('Diagnostic copied'))));
    }
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final spec = entry.retrySpec;
    if (spec == null) return;
    if (spec.requiresConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t('Retry {0}?', args: [entry.target])),
          content: Text(
            context.t('This operation may be destructive. Run it again?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.t('Retry')),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await ref.read(activityProvider.notifier).retry(entry);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

String _formatTime(DateTime dt) {
  final s = dt.toLocal().toString();
  return s.length >= 16 ? s.substring(0, 16) : s;
}
