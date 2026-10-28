import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/core/extensions/preferences_repository_x.dart';
import 'package:quickgui/core/logging/app_logging.dart';
import 'package:quickgui/shared/providers/preferences_providers.dart';

/// User-defined grouping tags per VM. Persisted as a JSON map
/// `{ "vm-name": ["tag", ...] }` under [prefVmTags].
class VmTagsController extends Notifier<Map<String, List<String>>> {
  @override
  Map<String, List<String>> build() {
    unawaitedLogged(_load(), AppLog.preferences, 'load vm tags');
    return const {};
  }

  Future<void> _load() async {
    final raw = await ref
        .read(preferencesRepositoryProvider)
        .getAs<String>(prefVmTags);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        if (!ref.mounted) return;
        state = {
          for (final e in decoded.entries)
            if (e.value is List)
              '${e.key}': [for (final t in e.value as List) '$t'],
          ...state,
        };
      }
    } catch (_) {
      // Corrupted pref: start empty rather than crash the app.
    }
  }

  /// All tags in use across VMs, sorted.
  List<String> get allTags =>
      {for (final tags in state.values) ...tags}.toList()..sort();

  List<String> tagsFor(String vm) => state[vm] ?? const [];

  Future<void> setTags(String vm, List<String> tags) {
    final next = Map<String, List<String>>.of(state);
    if (tags.isEmpty) {
      next.remove(vm);
    } else {
      next[vm] = List.unmodifiable(tags);
    }
    state = next;
    return ref
        .read(preferencesRepositoryProvider)
        .set(prefVmTags, jsonEncode(next));
  }

  Future<void> addTag(String vm, String tag) {
    final current = tagsFor(vm);
    if (current.contains(tag)) return Future.value();
    return setTags(vm, [...current, tag]);
  }

  Future<void> removeTag(String vm, String tag) =>
      setTags(vm, tagsFor(vm).where((t) => t != tag).toList());
}

/// VM name → tags map.
final vmTagsProvider =
    NotifierProvider<VmTagsController, Map<String, List<String>>>(
      VmTagsController.new,
    );

/// Sorted set of every tag in use (for the filter chips row).
final allVmTagsProvider = Provider<List<String>>(
  (ref) => ref.watch(vmTagsProvider.notifier).allTags,
);
