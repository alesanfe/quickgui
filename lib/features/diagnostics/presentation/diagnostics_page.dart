import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/core/telemetry/legacy_telemetry.dart';
import 'package:quickgui/features/diagnostics/domain/diagnostics_report.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:quickgui/features/machines/providers/tracked_backend_provider.dart';
import 'package:quickgui/shared/widgets/bytes_formatter.dart';

/// Local diagnostics: backend, contract, tools, KVM, disk and capabilities.
/// Status is conveyed by icon + text, never by colour alone.
class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(diagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Diagnostics')),
        actions: [
          IconButton(
            tooltip: context.t('Refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
          IconButton(
            tooltip: context.t('Copy sanitised report'),
            icon: const Icon(Icons.copy),
            onPressed: report.value == null
                ? null
                : () async {
                    final text = report.value!.toSanitizedText(
                      homeDirectory: ref.read(hostProbeProvider).homeDirectory,
                    );
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t('Report copied'))),
                    );
                  },
          ),
        ],
      ),
      body: switch (report) {
        AsyncData(:final value) => _ReportView(value),
        AsyncError(:final error) => Center(
          child: Text('${context.t('Error')}: $error'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView(this.r);
  final DiagnosticsReport r;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(context.t('Versions'), [
          _Info('Quickgui', r.quickguiVersion),
          _Info('quickemu', r.backendVersion ?? context.t('Unknown')),
          _Status(
            context.t('Contract version'),
            ok: r.contractCompatible,
            detail: r.contractVersion?.toString() ?? context.t('None'),
          ),
        ]),
        _Section(context.t('Host'), [
          _Status(context.t('Backend found'), ok: r.backendAvailable),
          _Status('KVM', ok: r.kvmAvailable),
          _Info(context.t('Working directory'), r.workingDirectory),
          _Info(
            context.t('Free space'),
            r.freeSpaceBytes == null
                ? context.t('Unknown')
                : formatBytes(r.freeSpaceBytes!),
          ),
        ]),
        _Section(context.t('Tools'), [
          for (final e in r.tools.entries) _Status(e.key, ok: e.value),
        ]),
        _Section(context.t('Backend compatibility'), [
          _Status(
            context.t('Structured contract'),
            ok: r.contractCompatible,
            detail: r.contractVersion?.toString() ?? context.t('None'),
          ),
          _Info(context.t('Legacy fallbacks used'), '${LegacyTelemetry.count}'),
          if (LegacyTelemetry.commands.isNotEmpty)
            _Info(
              context.t('Commands without envelope'),
              LegacyTelemetry.commands.join(', '),
            ),
          if (LegacyTelemetry.last != null)
            _Info(
              context.t('Last fallback'),
              '${LegacyTelemetry.last!.command} — ${LegacyTelemetry.last!.reason}',
            ),
        ]),
        if (r.capabilities.isNotEmpty)
          _Section(context.t('Capabilities'), [
            for (final e in r.capabilities.entries) _Status(e.key, ok: e.value),
          ]),
        if (r.hostInfo.isNotEmpty)
          _Section(context.t('Host info'), [
            for (final e in r.hostInfo.entries)
              if (e.value is bool)
                _Status(e.key, ok: e.value as bool)
              else
                _Info(e.key, '${e.value}'),
          ]),
        if (r.backendAvailable) const _VfioScanSection(),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: const Icon(Icons.info_outline),
    title: Text(label),
    subtitle: SelectableText(value),
  );
}

class _Status extends StatelessWidget {
  const _Status(this.label, {required this.ok, this.detail});
  final String label;
  final bool ok;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ok ? context.t('OK') : context.t('Missing');
    return MergeSemantics(
      child: ListTile(
        dense: true,
        leading: Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? scheme.primary : scheme.error,
        ),
        title: Text(label),
        trailing: Text(detail == null ? state : '$detail · $state'),
      ),
    );
  }
}

/// On-demand `--vfio-scan`: lists IOMMU passthrough candidates only
/// when the user asks — the scan probes hardware and is not free.
class _VfioScanSection extends ConsumerStatefulWidget {
  const _VfioScanSection();

  @override
  ConsumerState<_VfioScanSection> createState() => _VfioScanSectionState();
}

class _VfioScanSectionState extends ConsumerState<_VfioScanSection> {
  List<Map<String, dynamic>>? _devices;
  bool _busy = false;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await ref.read(trackedBackendProvider).vfioScan();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Section(context.t('VFIO scan'), [
    if (_error != null) _Info(context.t('Error'), _error!),
    if (_devices != null && _devices!.isEmpty)
      _Info(context.t('Devices'), context.t('No passthrough candidates')),
    for (final d in _devices ?? const [])
      _Info(
        '${d['id'] ?? d['bdf'] ?? context.t('Device')}',
        '${d['name'] ?? d['driver'] ?? ''} ${d['iommuGroup'] != null ? '· group ${d['iommuGroup']}' : ''}'
            .trim(),
      ),
    ListTile(
      leading: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            )
          : const Icon(Icons.memory),
      title: Text(
        _devices == null
            ? context.t('Scan passthrough devices')
            : context.t('Scan again'),
      ),
      onTap: _busy ? null : _scan,
    ),
  ]);
}
