import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/option_selection.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';
import 'package:quickgui/shared/widgets/field_help.dart';

class VersionSelection extends ConsumerStatefulWidget {
  const VersionSelection({required this.operatingSystem, super.key});

  final OperatingSystem operatingSystem;

  @override
  ConsumerState<VersionSelection> createState() => _VersionSelectionState();
}

class _VersionSelectionState extends ConsumerState<VersionSelection> {
  String term = "";
  final focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    focusNode.requestFocus();
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.operatingSystem.versions
        .where(
          (version) =>
              version.version.toLowerCase().contains(term.toLowerCase()),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t(
            'Select version for {0}',
            args: [widget.operatingSystem.name],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).canvasColor),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.search),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          focusNode: focusNode,
                          decoration: InputDecoration.collapsed(
                            hintText: context.t('Search version'),
                          ),
                          onChanged: (value) {
                            setState(() {
                              term = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          // QGUI-VERSION-003: one global architecture check in the
          // header instead of a repeated competitive icon per row.
          TextButton.icon(
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(context.t('Check architectures')),
            onPressed: () async {
              final result = await ref.read(backendProvider).runQuickget([
                '--check-all-arch',
                widget.operatingSystem.code,
              ]);
              if (context.mounted) {
                showProcessOutputDialog(context, [result]);
              }
            },
          ),
        ],
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 4),
          children: [
            // C-08 / QGUI-VERSION-002: quickget does not declare release
            // metadata (LTS/recommended/EOL), so we say so honestly once
            // instead of guessing from version numbers per row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FieldHelp(
                description: context.t(
                  'Recommendation unavailable — quickget does not report release metadata for this OS.',
                ),
                constraint: context.t(
                  'Expand a version to compare editions and check architecture support before downloading.',
                ),
              ),
            ),
            for (final item in list)
              Card(
                child: ListTile(
                  title: Text(item.version),
                  // Objective data only — no invented "recommended"
                  // badge: the real edition list from the model.
                  subtitle: item.options.isNotEmpty
                      ? Text(item.options.map((o) => o.option).join(', '))
                      : null,
                  onTap: () => _select(item),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _select(Version item) {
    if (item.options.length > 1) {
      final navigator = Navigator.of(context);
      navigator
          .push<Option>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (context) => OptionSelection(item),
            ),
          )
          .then((selection) {
            if (selection != null && context.mounted) {
              navigator.pop(Tuple2<Version, Option?>(item, selection));
            }
          });
    } else {
      Navigator.of(context).pop(
        Tuple2<Version, Option?>(
          item,
          item.options.isEmpty ? null : item.options.first,
        ),
      );
    }
  }
}
