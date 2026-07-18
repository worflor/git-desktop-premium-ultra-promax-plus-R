// budgeted_lru_cache_test.dart — laws for the byte-budgeted LRU. A count-only
// LRU pinned gigabytes of a heavy repo's diffs ("12 entries, all fine"); this
// primitive exists so every content-retaining cache enforces the BYTES axis.
// The laws here are what the changes page's caches now rely on structurally.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/budgeted_lru_cache.dart';

BudgetedLruCache<String, String> _cache({
  int maxEntries = 10,
  int maxCostBytes = 100,
}) => BudgetedLruCache(
  maxEntries: maxEntries,
  maxCostBytes: maxCostBytes,
  costOf: (v) => v.length,
);

void main() {
  test('enforces the entry-count ceiling oldest-first', () {
    final c = _cache(maxEntries: 3, maxCostBytes: 1000);
    for (final k in ['a', 'b', 'c', 'd']) {
      c.put(k, 'x');
    }
    expect(c.length, 3);
    expect(c.containsKey('a'), isFalse);
    expect(c.containsKey('d'), isTrue);
  });

  test('enforces the byte ceiling oldest-first with exact accounting', () {
    final c = _cache(maxCostBytes: 10);
    c.put('a', 'aaaa'); // 4
    c.put('b', 'bbbb'); // 8
    c.put('c', 'cccc'); // 12 → evict a → 8
    expect(c.containsKey('a'), isFalse);
    expect(c.containsKey('b'), isTrue);
    expect(c.containsKey('c'), isTrue);
    expect(c.totalCostBytes, 8);
  });

  test('the newest entry always survives, even alone over budget', () {
    final c = _cache(maxCostBytes: 10);
    c.put('small', 'xx');
    c.put('huge', 'x' * 50); // over the whole budget by itself
    expect(c.containsKey('small'), isFalse);
    expect(c.containsKey('huge'), isTrue,
        reason: 'the bound stops accumulation, never the working set');
    expect(c.length, 1);
  });

  test('re-putting a key refreshes recency and replaces its cost', () {
    final c = _cache(maxCostBytes: 10);
    c.put('a', 'aaaa'); // 4
    c.put('b', 'bb'); // 6
    c.put('a', 'aa'); // replace: 4  (a now newest)
    expect(c.totalCostBytes, 4);
    c.put('c', 'cccccc'); // 10 → fits; b is oldest now
    c.put('d', 'ddd'); // 13 → evict b → 11 → evict a → 9
    expect(c.containsKey('b'), isFalse);
    expect(c.containsKey('a'), isFalse);
    expect(c.containsKey('c'), isTrue);
    expect(c.containsKey('d'), isTrue);
  });

  test('remove and clear keep accounting exact', () {
    final c = _cache();
    c.put('a', 'aaaa');
    c.put('b', 'bb');
    expect(c.remove('a'), 'aaaa');
    expect(c.totalCostBytes, 2);
    expect(c.remove('a'), isNull);
    c.clear();
    expect(c.isEmpty, isTrue);
    expect(c.totalCostBytes, 0);
  });

  test('peek does not refresh recency', () {
    final c = _cache(maxEntries: 2, maxCostBytes: 1000);
    c.put('a', 'x');
    c.put('b', 'x');
    c.peek('a'); // must NOT rescue `a`
    c.put('c', 'x');
    expect(c.containsKey('a'), isFalse);
  });
}
