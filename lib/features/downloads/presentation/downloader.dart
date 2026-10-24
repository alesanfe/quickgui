import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_notifications/desktop_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/downloads/presentation/manage_machines_after_download_button.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/features/settings/providers/settings_providers.dart';
import 'package:quickgui/infrastructure/persistence/preferences_repository.dart';
import 'package:quickgui/infrastructure/platform/host_platform.dart';
import 'package:quickgui/infrastructure/vm_config.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/downloads/presentation/cancel_dismiss_button.dart';
import 'package:quickgui/features/downloads/presentation/download_label.dart';
import 'package:quickgui/features/downloads/presentation/download_progress_bar.dart';

class Downloader extends ConsumerStatefulWidget {
  const Downloader({
    required this.operatingSystem,
    required this.version,
    this.option,
    this.customConf,
    super.key,
  });

  final OperatingSystem operatingSystem;
  final Version version;
  final Option? option;

  /// Extra key="value" entries applied to the generated .conf after the
  /// download completes (pre-download customisation wizard).
  /// Extra key="value" entries applied to the generated .conf after the
  /// download completes (pre-download customisation wizard).
  final Map<String, String>? customConf;

  @override
  ConsumerState<Downloader> createState() => _DownloaderState();
}

class _DownloaderState extends ConsumerState<Downloader> {
  final NotificationsClient? notificationsClient = Platform.isMacOS
      ? null
      : NotificationsClient();
  final curlPattern = RegExp("( [0-9.]+%)");
  late final Stream<double> _progressStream;
  bool _downloadFinished = false;
  StreamController<double> controller = StreamController<double>();
  Process? _process;
  final List<String> _outputChunks = [];
  int _outputLength = 0;
  bool _showOutput = false;
  static const int _maxOutputLength = 512 * 1024;

  void _captureOutput(String chunk) {
    _outputChunks.add(chunk);
    _outputLength += chunk.length;
    // Bound the buffer: drop the oldest chunks when it grows too large.
    while (_outputLength > _maxOutputLength && _outputChunks.isNotEmpty) {
      _outputLength -= _outputChunks.removeAt(0).length;
    }
    if (_showOutput && mounted) {
      setState(() {});
    }
  }

  String get _processOutput => _outputChunks.join();

  @override
  void initState() {
    _progressStream = progressStream();
    super.initState();
  }

  void parseCurlProgress(String line) {
    final matches = curlPattern.allMatches(line).toList();
    if (matches.isNotEmpty) {
      final percent = matches[0].group(1);
      if (percent != null) {
        final value = double.parse(percent.replaceAll('%', '')) / 100.0;
        controller.add(value);
      }
    }
  }

  Future<void> addNewestVmToPrefs() async {
    final dir = Directory.current;
    final folders = await dir
        .list()
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();

    folders.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );

    // Update the prefNewlyInstalledVms with the newest folder
    if (folders.isNotEmpty) {
      final String newestFolder = p.basename(folders.first.path);

      final prefs = ref.read(preferencesRepositoryProvider);
      final List<String> newVmNames =
          await prefs.getAs<List<String>>(prefNewlyInstalledVms) ?? <String>[];

      newVmNames.add(newestFolder);

      prefs.set(prefNewlyInstalledVms, newVmNames);
    }
  }

  Stream<double> progressStream() {
    final options = [widget.operatingSystem.code, widget.version.version];
    if (widget.option != null) {
      options.add(widget.option!.option);
    }

    Process.start(HostPlatform.isFlatpak ? 'flatpak-spawn' : 'quickget', [
      if (HostPlatform.isFlatpak) ...['--host', 'quickget'] else 'quickget',
      ...options,
    ]).then((process) {
      process.stdout.transform(utf8.decoder).forEach(_captureOutput);
      if (widget.option!.downloader != 'zsync') {
        process.stderr.transform(utf8.decoder).forEach((chunk) {
          _captureOutput(chunk);
          parseCurlProgress(chunk);
        });
      } else {
        process.stderr.transform(utf8.decoder).forEach(_captureOutput);
        controller.add(-1);
      }

      process.exitCode.then((value) async {
        final bool cancelled = value.isNegative;
        controller.close();
        addNewestVmToPrefs();
        final prefs = ref.read(preferencesRepositoryProvider);
        final history =
            await prefs.getAs<List<String>>('downloadHistory') ?? <String>[];
        history.add(
          '${widget.operatingSystem.name} ${widget.version.version} — ${DateTime.now()}',
        );
        prefs.set('downloadHistory', history);
        final conf = widget.customConf ?? {};
        if (conf.isNotEmpty && !cancelled) {
          // Apply wizard values to the newest generated .conf.
          final confs =
              Directory.current
                  .listSync()
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.conf'))
                  .toList()
                ..sort(
                  (a, b) =>
                      b.lastModifiedSync().compareTo(a.lastModifiedSync()),
                );
          if (confs.isNotEmpty) {
            for (final e in conf.entries) {
              writeConfValue(confs.first.path, e.key, e.value);
            }
          }
        }
        setState(() {
          _downloadFinished = true;

          notificationsClient?.notify(
            cancelled
                ? context.t('Download cancelled')
                : context.t('Download complete'),
            body: cancelled
                ? context.t(
                    'Download of {0} has been canceled.',
                    args: [widget.operatingSystem.name],
                  )
                : context.t(
                    'Download of {0} has completed.',
                    args: [widget.operatingSystem.name],
                  ),
            appName: 'Quickgui',
            expireTimeoutMs: 10000 /* 10 seconds */,
          );
        });
      });

      setState(() {
        _process = process;
      });
    });
    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.t(
            'Downloading {0}',
            args: [
              '${widget.operatingSystem.name} ${widget.version.version}${widget.option!.option.isNotEmpty ? ' (${widget.option!.option})' : ''}',
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _progressStream,
              builder: (context, AsyncSnapshot<double> snapshot) {
                final data =
                    !snapshot.hasData || widget.option!.downloader != 'curl'
                    ? null
                    : snapshot.data;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DownloadLabel(
                      downloadFinished: _downloadFinished,
                      data: snapshot.hasData ? snapshot.data : null,
                      downloader: widget.option!.downloader,
                    ),
                    DownloadProgressBar(
                      downloadFinished: _downloadFinished,
                      data: snapshot.hasData ? data : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Text(
                        context.t(
                          'Target folder : {0}',
                          args: [Directory.current.path],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: Icon(
                        _showOutput ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(context.t('Show terminal output')),
                      onPressed: () {
                        setState(() {
                          _showOutput = !_showOutput;
                        });
                      },
                    ),
                    if (_showOutput)
                      Container(
                        height: 160,
                        width: 560,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            _processOutput,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          ManageMachinesAfterDownloadButton(
            downloadFinished: _downloadFinished,
          ),
          CancelDismissButton(
            onCancel: () {
              _process?.kill();
            },
            downloadFinished: _downloadFinished,
          ),
        ],
      ),
    );
  }
}
