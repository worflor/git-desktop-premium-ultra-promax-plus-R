// budgeted_lru_cache.dart — an LRU bounded on BOTH entry count and resident
// bytes.
//
// Count-only LRUs are how the changes page pinned gigabytes: "12 entries"
// sounds bounded until each entry is a combined diff of a machine-scale
// working tree. Memory is exhausted along the BYTES axis, so any cache whose
// values retain content must account bytes and evict on them. This primitive
// exists so no cache re-derives that lesson: give it a cost function and two
// ceilings, and both are enforced on every insert.
//
// Semantics (matching the call sites it replaced, so behavior is law-tested
// here instead of re-implemented inline):
//   • put() refreshes recency (remove + re-insert) and then evicts oldest-
//     first until both ceilings hold;
//   • the NEWEST entry always survives, even alone over the byte ceiling —
//     it is what the caller is about to use; the bound's job is to stop
//     ACCUMULATION, not to refuse the working set;
//   • peek() does not refresh recency (recency is an explicit caller choice
//     via re-put, exactly as the previous inline code behaved);
//   • cost is captured AT INSERT and maintained incrementally — O(1) per
//     operation, no full-cache walks.

import 'dart:collection';

class BudgetedLruCache<K, V> {
  final int maxEntries;
  final int maxCostBytes;
  final int Function(V value) costOf;

  final LinkedHashMap<K, V> _map = LinkedHashMap<K, V>();
  final Map<K, int> _costs = <K, int>{};
  int _totalCost = 0;

  BudgetedLruCache({
    required this.maxEntries,
    required this.maxCostBytes,
    required this.costOf,
  })  : assert(maxEntries > 0),
        assert(maxCostBytes >= 0);

  int get length => _map.length;
  int get totalCostBytes => _totalCost;
  bool get isEmpty => _map.isEmpty;
  Iterable<V> get values => _map.values;
  bool containsKey(K key) => _map.containsKey(key);

  /// Read without refreshing recency.
  V? peek(K key) => _map[key];

  /// Insert (or refresh) [value] under [key], then enforce both ceilings,
  /// oldest-first, always sparing the just-inserted entry.
  void put(K key, V value) {
    remove(key);
    final cost = costOf(value);
    _map[key] = value;
    _costs[key] = cost;
    _totalCost += cost;
    while (_map.length > maxEntries) {
      _evictOldest();
    }
    while (_totalCost > maxCostBytes && _map.length > 1) {
      _evictOldest();
    }
  }

  V? remove(K key) {
    if (!_map.containsKey(key)) return null;
    final removed = _map.remove(key);
    _totalCost -= _costs.remove(key) ?? 0;
    return removed;
  }

  void clear() {
    _map.clear();
    _costs.clear();
    _totalCost = 0;
  }

  void _evictOldest() {
    if (_map.isEmpty) return;
    remove(_map.keys.first);
  }
}
