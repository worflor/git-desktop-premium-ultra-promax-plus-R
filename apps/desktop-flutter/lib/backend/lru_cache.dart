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
  LruCache({required this.maxSize}) : assert(maxSize > 0);

  final int maxSize;
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
    _entries.remove(key);
    _entries[key] = value;
    while (_entries.length > maxSize) {
      _entries.remove(_entries.keys.first);
    }
  }

  bool containsKey(K key) => _entries.containsKey(key);

  V? remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();

  /// Iteration is oldest → newest. Useful for debugging / diagnostics;
  /// prefer [get] for hot lookups so LRU order stays maintained.
  Iterable<MapEntry<K, V>> get entries => _entries.entries;
}
