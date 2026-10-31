/// Collection grouping for the machine library (QG-032).
///
/// The tag convention `group:name` already exists for organising VMs;
/// the part before the first colon names the collection. `_favorite`
/// and other underscore-prefixed internal tags never name a
/// collection, and a tag that ends at the colon (`"web:"`) is ignored.
library;

/// The collection a VM belongs to, or null when ungrouped.
String? vmCollection(Iterable<String> tags) {
  final sorted = tags.toList()..sort();
  for (final tag in sorted) {
    if (tag.startsWith('_')) continue;
    final colon = tag.indexOf(':');
    if (colon > 0 && colon < tag.length - 1) {
      return tag.substring(0, colon);
    }
  }
  return null;
}

/// Groups [vms] by collection preserving the input order inside each
/// group. Collections sort alphabetically; ungrouped VMs always come
/// last so ad-hoc machines never hide between named collections.
Map<String?, List<String>> groupMachines(
  Iterable<String> vms,
  Map<String, List<String>> tagsByVm,
) {
  final grouped = <String?, List<String>>{};
  for (final vm in vms) {
    final collection = vmCollection(tagsByVm[vm] ?? const <String>{});
    grouped.putIfAbsent(collection, () => []).add(vm);
  }
  final sortedKeys = grouped.keys.toList()
    ..sort((a, b) {
      if (a == null) return 1;
      if (b == null) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return {for (final key in sortedKeys) key: grouped[key]!};
}
