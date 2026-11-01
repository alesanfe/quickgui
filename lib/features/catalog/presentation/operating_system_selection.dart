import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/features/catalog/application/load_catalog.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/machines/application/ports/proc.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/features/machines/presentation/shared/process_output_dialog.dart';

class OperatingSystemSelection extends ConsumerStatefulWidget {
  const OperatingSystemSelection({super.key});

  @override
  ConsumerState<OperatingSystemSelection> createState() =>
      _OperatingSystemSelectionState();
}

class _OperatingSystemSelectionState
    extends ConsumerState<OperatingSystemSelection> {
  String term = "";
  final focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _retry = 0;

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

  /// Per-OS catalogue actions: `--show` prints the release matrix,
  /// `--open-homepage` opens the project page, `--update` refreshes the
  /// cached release data for that OS.
  Future<void> _osAction(OperatingSystem os, String action) async {
    final flag = switch (action) {
      'show' => '--show',
      'homepage' => '--open-homepage',
      'url' => '--url',
      _ => '--update',
    };
    ProcResult result;
    try {
      result = await ref.read(backendProvider).runQuickget([flag, os.code]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    if (flag == '--open-homepage') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.exitCode == 0
                ? context.t('Opened homepage for {0}', args: [os.name])
                : context.t(
                    'Could not open homepage ({0})',
                    args: ['${result.exitCode}'],
                  ),
          ),
        ),
      );
    } else {
      showProcessOutputDialog(context, [result]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Select operating system')),
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
                            hintText: context.t('Search operating system'),
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
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: FutureBuilder(
          // _retry re-runs loadOperatingSystems when the catalogue fails;
          // the provider holds a fixed Future, so a retry must bypass it.
          future: _retry == 0
              ? ref.watch(osCatalogueProvider)
              : loadOperatingSystems(ref.read(backendProvider)),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<OperatingSystem>> snapshot,
              ) {
                if (snapshot.hasError || snapshot.data == null) {
                  if (snapshot.connectionState == ConnectionState.done ||
                      snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            context.t(
                              'Could not load the OS catalogue. Check that quickget is installed and try again.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => setState(() => _retry++),
                            icon: const Icon(Icons.refresh),
                            label: Text(context.t('Retry')),
                          ),
                        ],
                      ),
                    );
                  }
                }
                if (snapshot.hasData) {
                  final List<OperatingSystem> list = snapshot.data!
                      .where(
                        (os) =>
                            os.name.toLowerCase().contains(term.toLowerCase()),
                      )
                      .toList();
                  // OS-003: "no matches for X" is a different state
                  // from "catalogue unavailable" — name the term and
                  // offer a one-tap clear instead of a dead list.
                  if (list.isEmpty && snapshot.data!.isNotEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            context.t(
                              'No operating systems match "{0}"',
                              args: [term],
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              setState(() => term = '');
                            },
                            child: Text(context.t('Clear search')),
                          ),
                        ],
                      ),
                    );
                  }
                  if (list.isEmpty) {
                    return Center(
                      child: Text(context.t('The catalogue is empty')),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      Widget icon;

                      if (ref.watch(osIconsProvider).containsKey(item.code)) {
                        icon = SvgPicture.asset(
                          ref.watch(osIconsProvider)[item.code]!,
                          width: 32,
                          height: 32,
                        );
                      } else {
                        icon = const Icon(Icons.computer, size: 32);
                      }
                      return Card(
                        child: ListTile(
                          title: Text(item.name),
                          leading: icon,
                          trailing: PopupMenuButton<String>(
                            tooltip: context.t('Details'),
                            icon: const Icon(Icons.more_vert),
                            onSelected: (action) => _osAction(item, action),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'show',
                                child: Text(context.t('Show release info')),
                              ),
                              PopupMenuItem(
                                value: 'homepage',
                                child: Text(context.t('Open homepage')),
                              ),
                              PopupMenuItem(
                                value: 'url',
                                child: Text(context.t('Show download URLs')),
                              ),
                              PopupMenuItem(
                                value: 'update',
                                child: Text(context.t('Check for updates')),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context).pop(item);
                          },
                        ),
                      );
                    },
                  );
                } else {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(context.t('Loading available downloads')),
                      ],
                    ),
                  );
                }
              },
        ),
      ),
    );
  }
}
