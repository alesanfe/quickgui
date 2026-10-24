import 'dart:async';

import 'package:alchemist/alchemist.dart';

/// Golden config: only CI goldens (text rendered as blocks), so images are
/// identical on every host and in CI. Platform goldens are disabled because
/// font rasterisation differs between Linux and macOS.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await AlchemistConfig.runWithConfig<FutureOr<void>>(
    config: const AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: false),
    ),
    run: testMain,
  );
}
