import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/app/router/app_router.dart';
import 'package:quickgui/features/diagnostics/presentation/diagnostics_page.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

/// Persistent warning shown when the virtualization backend
/// (quickemu/quickget) is not available. Offers a path to Diagnostics
/// where the user can see exactly what is missing.
class DependencyWarning extends ConsumerWidget {
  const DependencyWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(backendAvailableProvider);
    return switch (available) {
      AsyncData(:final value) when !value => Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: Icon(
              Icons.warning_amber,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            title: Text(
              context.t('Quickemu was not found in your PATH'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            subtitle: Text(
              context.t(
                'Downloads and virtual machines will not work until it is installed.',
              ),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            trailing: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(appRoute<void>(const DiagnosticsPage())),
              child: Text(context.t('Open diagnostics')),
            ),
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
