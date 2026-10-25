import 'package:tuple/tuple.dart';

import 'package:quickgui/core/errors/failure.dart';
import 'package:quickgui/core/result/result.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/machines/application/ports/virtualization_backend.dart';

/// Use case: load the OS catalogue (structured JSON, CSV fallback).
/// Returns raw rows [displayName, os, release, option, downloader].
class LoadCatalog {
  LoadCatalog(this._backend);
  final VirtualizationBackend _backend;

  Future<Result<List<List<String>>>> call() async {
    if (!await _backend.checkAvailability()) {
      return const Err(
        Failure('backend.unavailable', 'Virtualization backend not found'),
      );
    }
    return Ok(await _backend.listOperatingSystems());
  }
}

/// Loads the OS catalogue and parses it into domain objects.
Future<List<OperatingSystem>> loadOperatingSystems(
  VirtualizationBackend backend,
) async {
  final rows = await backend.listOperatingSystems();
  final output = <OperatingSystem>[];
  OperatingSystem? currentOperatingSystem;
  Version? currentVersion;

  for (final chunks in rows) {
    Tuple5<String, String, String, String, String> supportedVersion;
    final chunksTyped = chunks.cast<String>();
    if (chunksTyped.length == 4) // Legacy version of quickget
    {
      supportedVersion = Tuple5.fromList([...chunksTyped, "curl"]);
    } else {
      final t5 = [
        chunks[0],
        chunks[1],
        chunks[2],
        chunks[3],
        chunks[4],
      ].toList();
      supportedVersion = Tuple5.fromList(t5);
    }

    if (currentOperatingSystem?.code != supportedVersion.item2) {
      currentOperatingSystem = OperatingSystem(
        supportedVersion.item1,
        supportedVersion.item2,
      );
      output.add(currentOperatingSystem);
      currentVersion = null;
    }
    if (currentVersion?.version != supportedVersion.item3) {
      currentVersion = Version(supportedVersion.item3);
      currentOperatingSystem!.versions.add(currentVersion);
    }
    currentVersion!.options.add(
      Option(supportedVersion.item4, supportedVersion.item5),
    );
  }

  return output;
}
