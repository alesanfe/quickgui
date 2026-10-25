import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:quickgui/infrastructure/networking/quickgui_releases.dart';

/// Injectable seam around [fetchLatestQuickguiRelease]: tests substitute a
/// canned fetcher so no real network runs inside FakeAsync.
final latestReleaseProvider = Provider<Future<String> Function()>(
  (ref) => fetchLatestQuickguiRelease,
);
