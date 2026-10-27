import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/features/activity/domain/app_operation.dart';
import 'package:quickgui/features/activity/providers/activity_providers.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/models/operation_state.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

final downloadTasksProvider = Provider<DownloadTasks>(DownloadTasks.new);

class DownloadTasks {
  DownloadTasks(this.ref);
  final Ref ref;

  AppOperation start({
    required String os,
    required String release,
    String edition = '',
    Map<String, String> configuration = const {},
  }) {
    final directory = Directory.current.path;
    final target = '$os-$release';
    Process? process;
    var cancelled = false;
    final activity = ref.read(activityProvider.notifier);
    final operation = activity.start(
      OperationKind.download,
      target,
      onCancel: () async {
        cancelled = true;
        process?.kill();
      },
    );
    final backend = ref.read(backendProvider);
    final store = ref.read(vmConfigStoreProvider);
    final prefs = ref.read(preferencesRepositoryProvider);
    unawaited(() async {
      var output = '';
      void capture(String chunk) {
        output += chunk;
        if (output.length > 65536) {
          output = output.substring(output.length - 65536);
        }
        final matches = RegExp(r'([0-9]+(?:\.[0-9]+)?)%')
            .allMatches(chunk)
            .toList();
        final last = matches.isEmpty ? null : matches.last[1];
        final parsed = last == null ? null : double.tryParse(last);
        final progress = parsed == null ? null : parsed / 100;
        activity.update(
          operation,
          cancelled
              ? const OperationState.cancelling()
              : OperationState.running(progress: progress?.clamp(0, 1)),
          output: output,
        );
      }

      try {
        process = await backend.startDownloadImage(os, release, edition);
        if (cancelled) process!.kill();
        final stdout = process!.stdout.transform(utf8.decoder).forEach(capture);
        final stderr = process!.stderr.transform(utf8.decoder).forEach(capture);
        final exit = await process!.exitCode;
        await Future.wait([stdout, stderr]);
        if (cancelled || exit < 0) {
          activity.update(
            operation,
            const OperationState.cancelled(),
            output: output,
          );
          return;
        }
        if (exit != 0) {
          activity.update(
            operation,
            OperationState.failed(code: 'download.exit_$exit', message: output),
            output: output,
          );
          return;
        }
        // Prefer the conventional quickget name (<os>-<release>.conf);
        // fall back to the newest .conf only when it is absent.
        final expected = '$target.conf';
        final confs =
            Directory(directory)
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.conf'))
                .toList()
              ..sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
              );
        File? conf = confs.isEmpty ? null : confs.first;
        for (final f in confs) {
          if (p.basename(f.path) == expected) {
            conf = f;
            break;
          }
        }
        if (conf == null) {
          throw StateError(
            'The expected configuration was not generated: $expected',
          );
        }
        if (configuration.isNotEmpty) {
          store.writeAll(conf.path, configuration);
        }
        final vmName = p.basenameWithoutExtension(conf.path);
        final newlyInstalled =
            await prefs.getAs<List<String>>(prefNewlyInstalledVms) ?? [];
        await prefs.set(
          prefNewlyInstalledVms,
          {...newlyInstalled, vmName}.toList(),
        );
        final history =
            await prefs.getAs<List<String>>(prefDownloadHistory) ?? [];
        await prefs.set(prefDownloadHistory, [
          ...history,
          '$vmName — ${DateTime.now().toIso8601String()}',
        ]);
        activity.update(
          operation,
          const OperationState.succeeded(null),
          output: output,
        );
      } catch (error) {
        activity.update(
          operation,
          OperationState.failed(code: 'download.failed', message: '$error'),
          output: output,
        );
      }
    }());
    return operation;
  }
}
