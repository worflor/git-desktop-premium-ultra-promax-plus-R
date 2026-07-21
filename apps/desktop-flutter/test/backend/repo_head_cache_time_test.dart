// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Pins RepoHeadCache's 2-second TTL boundary with a FakeClock so the
// freshness window is proven at the exact instant, not by sleeping.
//
// The cache stamps each entry with `clock.now()` at fetch time and treats
// it fresh while `clock.now() - fetchedAt < ttl`. Freezing the clock lets
// us: fetch h1 at T0, move HEAD to h2, then step the clock to T0+1.9s
// (still fresh → the STALE hash h1 is served from cache) and T0+2.1s
// (stale → a real re-fetch returns h2). That difference is what proves the
// boundary — with HEAD unchanged a re-fetch would be indistinguishable
// from a cache hit.
//
// Hermetic: drives a private (non-singleton) RepoHeadCache over a
// ScratchRepo through the app's own runGit path.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/repo_head_cache.dart';

import '../support/fake_clock.dart';
import '../support/scratch_repo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('entry is fresh at t+1.9s and stale at t+2.1s (exact 2s boundary)',
      () async {
    final repo = await ScratchRepo.create(name: 'repo_head_ttl');
    addTearDown(repo.dispose);

    final clock = FakeClock(DateTime.utc(2026, 1, 1, 12, 0, 0));
    // Fresh, non-shared instance so we never disturb RepoHeadCache.instance.
    final cache = RepoHeadCache(clock: clock);

    await repo.writeFile('a.txt', 'one\n');
    final h1 = await repo.commitAll('c1');

    // Fetch at T0 → stamps the entry with clock.now() == T0.
    expect(await cache.head(repo.dir.path), h1);

    // HEAD moves. A re-fetch (only on staleness) would now return h2.
    await repo.writeFile('a.txt', 'two\n');
    final h2 = await repo.commitAll('c2');
    expect(h2, isNot(h1));

    // t+1.9s: inside the 2s window → cache hit serves the STALE h1.
    clock.advance(const Duration(milliseconds: 1900));
    expect(await cache.head(repo.dir.path), h1,
        reason: 'entry must still be fresh 1.9s after fetch');

    // t+2.1s: past the window → re-fetch observes the moved HEAD → h2.
    clock.advance(const Duration(milliseconds: 200));
    expect(await cache.head(repo.dir.path), h2,
        reason: 'entry must be stale 2.1s after fetch');
  });

  test('evict forces an immediate re-fetch regardless of TTL freshness',
      () async {
    final repo = await ScratchRepo.create(name: 'repo_head_evict');
    addTearDown(repo.dispose);

    final clock = FakeClock(DateTime.utc(2026, 1, 1, 12, 0, 0));
    final cache = RepoHeadCache(clock: clock);

    await repo.writeFile('a.txt', 'one\n');
    final h1 = await repo.commitAll('c1');
    expect(await cache.head(repo.dir.path), h1);

    await repo.writeFile('b.txt', 'x\n');
    final h2 = await repo.commitAll('c2');

    // Clock has NOT advanced → entry is still nominally fresh. Evict must
    // override that and force a fresh subprocess that sees the moved HEAD.
    cache.evict(repo.dir.path);
    expect(await cache.head(repo.dir.path), h2,
        reason: 'evict must invalidate the fresh entry so HEAD is re-read');
  });

  test('forceRefresh bypasses a fresh entry', () async {
    final repo = await ScratchRepo.create(name: 'repo_head_force');
    addTearDown(repo.dispose);

    final clock = FakeClock(DateTime.utc(2026, 1, 1, 12, 0, 0));
    final cache = RepoHeadCache(clock: clock);

    await repo.writeFile('a.txt', 'one\n');
    final h1 = await repo.commitAll('c1');
    expect(await cache.head(repo.dir.path), h1);

    await repo.writeFile('c.txt', 'x\n');
    final h2 = await repo.commitAll('c2');

    expect(await cache.head(repo.dir.path), h1, reason: 'still fresh');
    expect(await cache.head(repo.dir.path, forceRefresh: true), h2,
        reason: 'forceRefresh ignores freshness');
  });
}
