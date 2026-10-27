import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/features/catalog/application/load_catalog.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';

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
