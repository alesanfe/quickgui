import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:tuple/tuple.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/option_selection.dart';

class VersionSelection extends StatefulWidget {
  const VersionSelection({required this.operatingSystem, super.key});

  final OperatingSystem operatingSystem;

  @override
  State<VersionSelection> createState() => _VersionSelectionState();
}

class _VersionSelectionState extends State<VersionSelection> {
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
      ),
      body: Scrollbar(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 4),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final item = list[index];
            return Card(
              child: ListTile(
                title: Text(item.version),
                onTap: () {
                  if (item.options.length > 1) {
                    Navigator.of(context)
                        .push<Option>(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (context) => OptionSelection(list[index]),
                          ),
                        )
                        .then((selection) {
                          if (selection != null && context.mounted) {
                            Navigator.of(context)
                                .pop(Tuple2<Version, Option?>(item, selection));
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
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
