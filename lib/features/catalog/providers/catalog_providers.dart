import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/features/catalog/domain/operating_system.dart';

/// OS catalogue loaded at startup; null while the backend is missing or
/// the catalogue has not been loaded yet.
final osCatalogueProvider = Provider<Future<List<OperatingSystem>>?>(
  (ref) => null,
);

/// OS icon asset paths keyed by OS code; populated at startup from the
/// bundled asset manifest.
final osIconsProvider = Provider<Map<String, String>>((ref) => const {});
