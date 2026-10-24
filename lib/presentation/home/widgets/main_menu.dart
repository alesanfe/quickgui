import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/presentation/downloader/downloader_page.dart';
import 'package:quickgui/presentation/manager/manager.dart';
import 'package:quickgui/presentation/home/widgets/home_page_button.dart';

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HomePageButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      fullscreenDialog: true,
                      pageBuilder: (context, animation1, animation2) =>
                          const Manager(),
                      transitionDuration: const Duration(milliseconds: 150),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) => FadeTransition(opacity: animation, child: child),
                    ),
                  );
                },
                text: context.t('Manage existing machines'),
              ),
              HomePageButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      fullscreenDialog: true,
                      pageBuilder: (context, animation1, animation2) =>
                          const DownloaderPage(),
                      transitionDuration: const Duration(milliseconds: 150),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) => FadeTransition(opacity: animation, child: child),
                    ),
                  );
                },
                text: context.t('Create new machines'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
