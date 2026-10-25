import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/diagnostics/domain/diagnostics_report.dart';
import 'package:quickgui/features/diagnostics/providers/diagnostics_providers.dart';
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
        if (r.capabilities.isNotEmpty)
          _Section(context.t('Capabilities'), [
            for (final e in r.capabilities.entries) _Status(e.key, ok: e.value),
          ]),
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
