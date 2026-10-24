import 'package:flutter_riverpod/legacy.dart';
import 'package:quickgui/app/settings/app_settings.dart';

/// Bridge provider: exposes the singleton [AppSettings] created in `main()`
/// so features can migrate from `context.read<AppSettings>()` (package:provider)
/// to `ref.watch(appSettingsProvider)` file by file.
///
/// The instance is injected via `ProviderScope.overrides` in main.dart.
final appSettingsProvider = ChangeNotifierProvider<AppSettings>(
  (_) => throw UnimplementedError('appSettingsProvider must be overridden'),
);
