import 'dart:collection';

/// Minimal insertion-ordered LRU cache.
///
/// `LinkedHashMap` iteration order is insertion order, so we can use it
/// as an LRU by deleting + re-inserting on access. Cheap and sufficient
/// for the small capacities most callers want (≤ a few hundred entries).
/// Prior to this class each cache was an ad-hoc copy of the same 20-line
/// pattern — replacing them all with a single well-tested implementation
/// keeps the semantics identical everywhere and eliminates the "I'll
/// forget the LRU-bump on this one" class of bug.
///
/// Keys can be anything that supplies correct `==`/`hashCode`
/// (primitives, strings, Dart records, manually-hashed composite ints).
/// Values can be anything — the cache doesn't care about their shape.
class LruCache<K, V> {
  LruCache({required this.maxSize, this.onEvict}) : assert(maxSize > 0);

  final int maxSize;

  /// Optional hook invoked with a value AS IT LEAVES the cache — on
  /// capacity eviction, overwrite of an existing key with a different
  /// instance, [remove], and [clear]. It is NOT fired by [get] (the value
  /// stays cached) nor by re-[put]ting the identical instance (an LRU
  /// bump, not a departure). Use it to release values that own resources
  /// GC won't reclaim promptly — e.g. `onEvict: (tp) => tp.dispose()` for
  /// a `TextPainter` cache. Defaults to null, so caches of plain values
  /// are entirely unaffected.
  final void Function(V evicted)? onEvict;

  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Return the value for [key], bumping it to MRU position. Returns
  /// `null` on miss; callers that care about explicit presence should
  /// use [containsKey] first (but that's rare — the common pattern is
  /// `get → if null, build and put`).
  V? get(K key) {
    if (!_entries.containsKey(key)) return null;
    final v = _entries.remove(key) as V;
    _entries[key] = v;
    return v;
  }

  /// Insert or overwrite. Also serves as an LRU bump when [key] already
  /// exists. Evicts the oldest entries until length ≤ [maxSize].
  void put(K key, V value) {
    final prior = _entries.remove(key);
    if (prior != null && !identical(prior, value)) onEvict?.call(prior);
    _entries[key] = value;
    while (_entries.length > maxSize) {
      final evicted = _entries.remove(_entries.keys.first) as V;
      onEvict?.call(evicted);
    }
  }

  bool containsKey(K key) => _entries.containsKey(key);

  V? remove(K key) {
    final removed = _entries.remove(key);
    if (removed != null) onEvict?.call(removed);
    return removed;
  }

  void clear() {
    final cb = onEvict;
    if (cb != null) {
      for (final v in _entries.values) {
        cb(v);
      }
    }
    _entries.clear();
  }

  /// Iteration is oldest → newest. Useful for debugging / diagnostics;
  /// prefer [get] for hot lookups so LRU order stays maintained.
  Iterable<MapEntry<K, V>> get entries => _entries.entries;
}
