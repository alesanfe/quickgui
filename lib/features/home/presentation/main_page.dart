import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:window_manager/window_manager.dart';

import 'package:quickgui/features/home/presentation/logo.dart';
import 'package:quickgui/features/home/presentation/main_menu.dart';
import 'package:quickgui/features/home/presentation/left_menu.dart';
import 'package:quickgui/shared/widgets/dependency_warning.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    windowManager.setTitle(
      context.t('Quickgui : a Flutter frontend for Quickget and Quickemu'),
    );
  }

  @override
  Widget build(BuildContext context) {
    GettextLocalizations.of(context).enableExceptions(true);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Main menu')),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      drawer: const LeftMenu(),
      body: const Column(children: [Logo(), DependencyWarning(), MainMenu()]),
    );
  }
}
