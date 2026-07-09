// Law-based coverage for logos_git_resolver.dart, previously untested.
//
// This module owns process-wide static state (an LRU of built engines, an
// in-flight-build map, and per-repo HEAD snapshots), so every test starts
// from `invalidateAllLogosGit()` in setUp — never relying on prior test
// ordering.
//
// The resolver has a deliberate short (2s) TTL fast-path that skips even a
// `git rev-parse HEAD` probe if the last resolve for that repo was very
// recent — a real performance trade-off, not something these tests should
// route around with a hack. Where a test needs to observe HEAD-move
// invalidation specifically (not the TTL window), it waits past the TTL
// with a real delay so the assertion exercises the resolver's actual
// rev-parse-based staleness check, not an accident of timing.
//
// Building a real engine spawns git subprocesses, an isolate build, and
// (best-effort, gracefully-degrading) engram asset loading, so these are
// slower than typical unit tests — hence the generous suite timeout.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/logos_git_resolver.dart';

import '../support/scratch_repo.dart';

Future<ScratchRepo> _oneCommitRepo(String name) async {
  final repo = await ScratchRepo.create(name: name);
  await repo.writeFile('f.txt', 'hello\n');
  await repo.commitAll('add f');
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(invalidateAllLogosGit);

  group('resolveLogosGit', () {
    test(
      'single-flight: two concurrent calls for the same repo share one '
      'Future',
      () async {
        final repo = await _oneCommitRepo('resolver_singleflight');
        addTearDown(repo.dispose);

        final f1 = resolveLogosGit(repo.dir.path);
        final f2 = resolveLogosGit(repo.dir.path);
        expect(identical(f1, f2), isTrue,
            reason: 'two resolves fired without awaiting the first must '
                'dedup onto the exact same Future object');

        final engine = await f1;
        expect(engine, isNotNull);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'caching: a second resolve on an unmoved HEAD returns an identical '
      'engine object',
      () async {
        final repo = await _oneCommitRepo('resolver_cache');
        addTearDown(repo.dispose);

        final engineA = await resolveLogosGit(repo.dir.path);
        expect(engineA, isNotNull);
        final engineB = await resolveLogosGit(repo.dir.path);
        expect(identical(engineA, engineB), isTrue,
            reason: 'HEAD did not move — the cached engine object must be '
                'returned, not a rebuild');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'HEAD move: a further commit invalidates the cached engine',
      () async {
        final repo = await _oneCommitRepo('resolver_head_move');
        addTearDown(repo.dispose);

        final engineA = await resolveLogosGit(repo.dir.path);
        expect(engineA, isNotNull);

        await repo.writeFile('f.txt', 'hello again\n');
        await repo.commitAll('update f');

        // Clear the TTL fast-path window deliberately: this law is about
        // the resolver's HEAD-move detection (its rev-parse check), not
        // about racing the 2s cache-hit TTL.
        await Future<void>.delayed(const Duration(seconds: 3));

        final engineB = await resolveLogosGit(repo.dir.path);
        expect(identical(engineA, engineB), isFalse,
            reason: 'HEAD moved — resolveLogosGit must rebuild, not reuse '
                'the stale cached engine');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'invalidateLogosGit forces a rebuild on the next resolve',
      () async {
        final repo = await _oneCommitRepo('resolver_invalidate');
        addTearDown(repo.dispose);

        final engineA = await resolveLogosGit(repo.dir.path);
        expect(engineA, isNotNull);

        invalidateLogosGit(repo.dir.path);

        final engineB = await resolveLogosGit(repo.dir.path);
        expect(identical(engineA, engineB), isFalse,
            reason:
                'invalidateLogosGit must force a fresh build, never reuse '
                'the dropped engine');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'LRU bound: the 6th distinct repo evicts the 1st (maxSize 5)',
      () async {
        final repos = <ScratchRepo>[];
        addTearDown(() async {
          for (final r in repos) {
            await r.dispose();
          }
        });
        for (var i = 0; i < 6; i++) {
          repos.add(await _oneCommitRepo('resolver_lru_$i'));
        }

        final firstEngine = await resolveLogosGit(repos[0].dir.path);
        expect(firstEngine, isNotNull);
        for (var i = 1; i < 6; i++) {
          final engine = await resolveLogosGit(repos[i].dir.path);
          expect(engine, isNotNull, reason: 'repo $i must build cleanly');
        }

        // The engine cache is bounded at 5; resolving a 6th distinct repo
        // must have evicted repo 0, so resolving it again must rebuild.
        final firstAgain = await resolveLogosGit(repos[0].dir.path);
        expect(identical(firstEngine, firstAgain), isFalse,
            reason: 'repo 0 should have been evicted once a 6th distinct '
                'repo was resolved (LRU bound of 5)');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  group('peekResolvedLogosGitHeadHash', () {
    test(
      'returns the resolved HEAD hash for a known repo, and null for an '
      'unknown one',
      () async {
        final repo = await _oneCommitRepo('resolver_peek');
        addTearDown(repo.dispose);
        final headHash = await repo.head();
        expect(headHash, isNotNull);

        final engine = await resolveLogosGit(repo.dir.path);
        expect(engine, isNotNull);

        expect(peekResolvedLogosGitHeadHash(repo.dir.path), headHash);
        expect(
          peekResolvedLogosGitHeadHash('${repo.dir.path}-never-resolved'),
          isNull,
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
