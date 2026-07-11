// Law-based coverage for LruCache (lib/backend/lru_cache.dart), which was
// previously untested.
//
// The core of this file is a model-based property test: a plain-Dart
// reference LRU (recency list + map) is driven by the same random op
// sequence as the real LruCache, and after every single op the two are
// asserted to agree on size, bound, key/value contents, and oldest->newest
// order. `entries` is used (not `get`) to read back contents because
// `entries` is documented as non-mutating (oldest->newest, no MRU bump) —
// using it to verify "does get() return the right value" is equivalent to
// calling get() itself for present keys (both read the same underlying
// LinkedHashMap slot) but, unlike get(), it never perturbs the very MRU
// order the next assertion checks. `Get` op cases below still exercise the
// real bumping `cache.get()` call directly, so the MRU-bump contract is
// covered by the mutating path too.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/lru_cache.dart';

import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Reference oracle: a textbook LRU over (recency list + map).
// ---------------------------------------------------------------------------

class _Oracle<K, V> {
  _Oracle(this.maxSize);

  final int maxSize;
  final List<K> recency = <K>[]; // oldest -> newest
  final Map<K, V> map = <K, V>{};

  /// Reference model of the onEvict contract: values are logged here AS THEY
  /// LEAVE — capacity eviction, overwrite-with-a-different-instance, remove,
  /// and clear (oldest->newest). get() and a same-instance re-put never log.
  final List<V> evicted = <V>[];

  V? get(K key) {
    if (!map.containsKey(key)) return null;
    recency.remove(key);
    recency.add(key);
    return map[key];
  }

  void put(K key, V value) {
    if (map.containsKey(key)) {
      final prior = map[key] as V;
      if (!identical(prior, value)) evicted.add(prior);
      recency.remove(key);
    } else if (recency.length >= maxSize) {
      final oldest = recency.removeAt(0);
      evicted.add(map.remove(oldest) as V);
    }
    recency.add(key);
    map[key] = value;
  }

  bool containsKey(K key) => map.containsKey(key);

  V? remove(K key) {
    if (!map.containsKey(key)) return null;
    recency.remove(key);
    final removed = map.remove(key) as V;
    evicted.add(removed);
    return removed;
  }

  void clear() {
    for (final k in recency) {
      evicted.add(map[k] as V);
    }
    recency.clear();
    map.clear();
  }
}

// ---------------------------------------------------------------------------
// Op model
// ---------------------------------------------------------------------------

sealed class _LruOp {
  const _LruOp();
}

class _OpPut extends _LruOp {
  final int key;
  final int value;
  const _OpPut(this.key, this.value);
  @override
  String toString() => 'Put($key, $value)';
}

class _OpGet extends _LruOp {
  final int key;
  const _OpGet(this.key);
  @override
  String toString() => 'Get($key)';
}

class _OpRemove extends _LruOp {
  final int key;
  const _OpRemove(this.key);
  @override
  String toString() => 'Remove($key)';
}

class _OpContainsKey extends _LruOp {
  final int key;
  const _OpContainsKey(this.key);
  @override
  String toString() => 'ContainsKey($key)';
}

class _OpClear extends _LruOp {
  const _OpClear();
  @override
  String toString() => 'Clear()';
}

class _LruCase {
  final int maxSize;
  final List<_LruOp> ops;
  const _LruCase(this.maxSize, this.ops);
  @override
  String toString() => 'maxSize=$maxSize ops=$ops';
}

/// Generates a bounded `maxSize` (small, so eviction is exercised often) and
/// a random sequence of ops over a small key pool (so puts/gets/removes
/// collide with each other rather than always hitting fresh keys).
Gen<_LruCase> _genCase({int maxOps = 40, int keyPoolSize = 6}) {
  return (rng) {
    final maxSize = rng.intBetween(1, 5);
    final opCount = rng.intBetween(0, maxOps);
    var valueCounter = 0;
    final ops = <_LruOp>[];
    for (var i = 0; i < opCount; i++) {
      final key = rng.intBetween(0, keyPoolSize - 1);
      switch (rng.intBetween(0, 4)) {
        case 0:
          ops.add(_OpPut(key, valueCounter++));
        case 1:
          ops.add(_OpGet(key));
        case 2:
          ops.add(_OpRemove(key));
        case 3:
          ops.add(_OpContainsKey(key));
        default:
          ops.add(const _OpClear());
      }
    }
    return _LruCase(maxSize, ops);
  };
}

/// Applies [op] to both the real cache and the oracle, then asserts every
/// invariant that must hold after ANY op: size agreement, the maxSize
/// bound, key/value content agreement (via the non-mutating `entries`
/// reader), and oldest->newest order agreement.
void _applyAndCheck(
  LruCache<int, int> cache,
  _Oracle<int, int> oracle,
  _LruOp op,
  int maxSize,
) {
  switch (op) {
    case _OpPut(:final key, :final value):
      cache.put(key, value);
      oracle.put(key, value);
    case _OpGet(:final key):
      final actual = cache.get(key);
      final expected = oracle.get(key);
      expect(actual, expected, reason: 'get($key) mismatch after $op');
    case _OpRemove(:final key):
      final actual = cache.remove(key);
      final expected = oracle.remove(key);
      expect(actual, expected, reason: 'remove($key) mismatch after $op');
    case _OpContainsKey(:final key):
      final actual = cache.containsKey(key);
      final expected = oracle.containsKey(key);
      expect(actual, expected, reason: 'containsKey($key) mismatch after $op');
    case _OpClear():
      cache.clear();
      oracle.clear();
  }

  expect(cache.length, oracle.map.length,
      reason: 'length diverged from oracle after $op');
  expect(cache.length <= maxSize, isTrue,
      reason: 'cache exceeded maxSize=$maxSize after $op');
  expect(cache.isEmpty, cache.length == 0,
      reason: 'isEmpty inconsistent with length after $op');
  expect(cache.isNotEmpty, cache.length != 0,
      reason: 'isNotEmpty inconsistent with length after $op');

  final actualEntries = cache.entries.toList();
  final actualKeys = actualEntries.map((e) => e.key).toList();
  expect(actualKeys, oracle.recency,
      reason: 'oldest->newest order diverged from oracle after $op');
  for (final e in actualEntries) {
    expect(e.value, oracle.map[e.key],
        reason: 'value for key ${e.key} diverged from oracle after $op');
  }
}

/// Same as [_applyAndCheck] but also asserts the onEvict eviction LOG agrees
/// with the oracle after every op. Values are unique ints, so sorted-list
/// equality is multiset equality — clear()'s emission order isn't over-pinned.
void _applyAndCheckEvictions(
  LruCache<int, int> cache,
  _Oracle<int, int> oracle,
  List<int> realEvicted,
  _LruOp op,
  int maxSize,
) {
  _applyAndCheck(cache, oracle, op, maxSize);
  expect(realEvicted.toList()..sort(), oracle.evicted.toList()..sort(),
      reason: 'onEvict log diverged from oracle after $op');
}

void main() {
  group('LruCache — model-based property', () {
    test('matches a reference LRU oracle across random op sequences', () {
      forAll<_LruCase>(
        _genCase(),
        describe: 'lru_cache model equivalence',
        count: 300,
        check: (testCase) {
          final cache = LruCache<int, int>(maxSize: testCase.maxSize);
          final oracle = _Oracle<int, int>(testCase.maxSize);
          for (final op in testCase.ops) {
            _applyAndCheck(cache, oracle, op, testCase.maxSize);
          }
        },
      );
    });
  });

  group('LruCache — onEvict model-based property', () {
    test('eviction log matches the oracle across random op sequences', () {
      forAll<_LruCase>(
        _genCase(),
        describe: 'lru_cache onEvict model equivalence',
        count: 300,
        check: (testCase) {
          final realEvicted = <int>[];
          final cache = LruCache<int, int>(
            maxSize: testCase.maxSize,
            onEvict: realEvicted.add,
          );
          final oracle = _Oracle<int, int>(testCase.maxSize);
          for (final op in testCase.ops) {
            _applyAndCheckEvictions(
                cache, oracle, realEvicted, op, testCase.maxSize);
          }
        },
      );
    });
  });

  group('LruCache — onEvict direct semantics', () {
    test('capacity eviction fires onEvict with the evicted (oldest) value', () {
      final evicted = <int>[];
      final cache = LruCache<int, int>(maxSize: 2, onEvict: evicted.add);
      cache.put(1, 10);
      cache.put(2, 20);
      expect(evicted, isEmpty, reason: 'no eviction under capacity');
      cache.put(3, 30); // evicts key 1
      expect(evicted, [10], reason: 'the evicted oldest value is emitted');
    });

    test('overwrite fires onEvict with the prior value, not the new one', () {
      final evicted = <int>[];
      final cache = LruCache<int, int>(maxSize: 3, onEvict: evicted.add);
      cache.put(1, 10);
      cache.put(1, 11); // overwrite
      expect(evicted, [10],
          reason: 'the replaced prior value is emitted, once');
    });

    test('re-putting the IDENTICAL instance does not fire onEvict (a bump)',
        () {
      final evicted = <Object>[];
      final cache = LruCache<int, Object>(maxSize: 3, onEvict: evicted.add);
      final shared = Object();
      cache.put(1, shared);
      cache.put(1, shared); // same instance → pure LRU bump, not a departure
      expect(evicted, isEmpty,
          reason: 'an identical-instance re-put is a bump, not an eviction');
    });

    test('remove fires onEvict with the removed value', () {
      final evicted = <int>[];
      final cache = LruCache<int, int>(maxSize: 3, onEvict: evicted.add);
      cache.put(1, 10);
      cache.put(2, 20);
      cache.remove(1);
      expect(evicted, [10]);
      cache.remove(99); // absent → no fire
      expect(evicted, [10], reason: 'removing an absent key fires nothing');
    });

    test('clear fires onEvict for every entry, oldest to newest', () {
      final evicted = <int>[];
      final cache = LruCache<int, int>(maxSize: 3, onEvict: evicted.add);
      cache.put(1, 10);
      cache.put(2, 20);
      cache.put(3, 30);
      cache.clear();
      expect(evicted, [10, 20, 30],
          reason: 'clear emits all values in oldest->newest order');
      expect(cache.isEmpty, isTrue);
    });

    test('a null onEvict (the default) is simply never called', () {
      // Smoke: the non-callback path must behave exactly as before.
      final cache = LruCache<int, int>(maxSize: 1);
      cache.put(1, 10);
      cache.put(2, 20); // would evict; no callback to fire
      expect(cache.containsKey(2), isTrue);
      expect(cache.containsKey(1), isFalse);
    });
  });

  group('LruCache — direct semantics (read the source, pin the contract)', () {
    test('get() bumps the accessed key to most-recently-used', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(cache.entries.map((e) => e.key).toList(), ['a', 'b', 'c']);

      cache.get('a');
      expect(cache.entries.map((e) => e.key).toList(), ['b', 'c', 'a'],
          reason: 'get() must move the accessed key to the MRU end');
    });

    test('put() on an existing key bumps to MRU AND overwrites the value',
        () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('a', 99);

      final entries = cache.entries.toList();
      expect(entries.map((e) => e.key).toList(), ['b', 'c', 'a'],
          reason: 're-putting an existing key must bump it to MRU');
      expect(entries.firstWhere((e) => e.key == 'a').value, 99,
          reason: 're-putting an existing key must overwrite its value');
    });

    test('containsKey() does not bump order', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(cache.entries.map((e) => e.key).toList(), ['a', 'b', 'c']);

      final has = cache.containsKey('a');
      expect(has, isTrue);
      expect(cache.entries.map((e) => e.key).toList(), ['a', 'b', 'c'],
          reason: 'containsKey() must be a pure read — no MRU bump');
    });

    test('eviction removes exactly the oldest entry when maxSize is exceeded',
        () {
      final cache = LruCache<int, int>(maxSize: 2);
      cache.put(1, 10);
      cache.put(2, 20);
      cache.put(3, 30); // must evict key 1 (the oldest), not key 2.

      expect(cache.length, 2);
      expect(cache.containsKey(1), isFalse,
          reason: 'the oldest entry must be evicted');
      expect(cache.entries.map((e) => e.key).toList(), [2, 3]);
    });
  });
}
