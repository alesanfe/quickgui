import 'package:logging/logging.dart';

/// Logger categories — structured, local-only diagnostics.
abstract class AppLog {
  static final bootstrap = Logger('app.bootstrap');
  static final backendDiscovery = Logger('backend.discovery');
  static final backendProcess = Logger('backend.process');
  static final backendContract = Logger('backend.contract');
  static final filesystem = Logger('filesystem');
  static final preferences = Logger('preferences');
  static final navigation = Logger('ui.navigation');
  static final vmLifecycle = Logger('vm.lifecycle');
  static final download = Logger('download');
  static final diagnostics = Logger('diagnostics');

  /// Local-only console logging (no remote telemetry, per privacy
  /// policy for a local virtualization app).
  static void init({Level level = Level.INFO}) {
    Logger.root.level = level;
    Logger.root.onRecord.listen((r) {
      // ignore: avoid_print
      print('${r.time} [${r.level.name}] ${r.loggerName}: ${r.message}');
    });
  }
}
