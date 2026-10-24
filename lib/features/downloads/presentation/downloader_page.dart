import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import 'package:quickgui/features/home/presentation/downloader_menu.dart';
import 'package:quickgui/features/home/presentation/logo.dart';

class DownloaderPage extends StatelessWidget {
  const DownloaderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Downloader'))),
      body: const Column(children: [Logo(), DownloaderMenu()]),
    );
  }
}
