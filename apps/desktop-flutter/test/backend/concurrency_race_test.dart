// Genuine async-interleaving concurrency laws for the git subprocess seam
// (backend/git.dart) and the engine resolver (backend/logos_git_resolver.dart).
//
// `git_subprocess_semaphore_test.dart` exercises the semaphore's internal
// bookkeeping with sequential `await`s — useful, but it never actually fires
// overlapping subprocesses. This file fires REAL concurrent work via
// `Future.wait` over lists built without an intervening `await`, so the
// races this app is actually exposed to — the user's terminal and the app
// hitting the same repo at once, a stampede of UI callers resolving the
// same engine, a refresh racing a commit — get to actually race.
//
// Every assertion here is a law: read-coalescing collapses identical
// concurrent reads onto one spawn, the semaphore never lets peak
// concurrency exceed its cap, concurrent mutations never corrupt the
// object store (`git fsck` stays clean), a read racing a ref-moving
// mutation never observes a torn value, and the resolver's single-flight
// guard dedups a stampede onto one build. If a race exposes a real bug,
// the law is left failing rather than weakened.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
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

  // -------------------------------------------------------------------
  // Law 1: read-coalescing under true concurrency.
  // -------------------------------------------------------------------
  group('law 1: read-coalescing under true concurrency', () {
    tearDown(GitSpawn.reset);

    test(
      'K=8 identical concurrent runGit reads coalesce onto exactly one '
      'subprocess, and every caller sees the identical result object',
      () async {
        final repo = await ScratchRepo.create(name: 'coalesce_identical');
        addTearDown(repo.dispose);
        GitSpawn.reset();

        const k = 8;
        // Built WITHOUT an intervening await — all K calls are in flight
        // before any of them can complete, which is what actually makes
        // this a race rather than a relabeled sequential test. Bare
        // `runGit`, not `repo.git` — the latter's isolation `extraEnv`
        // unconditionally bypasses the dedup path (see git.dart's `_git`
        // doc comment), which would make this test pass for the wrong
        // reason.
        final futures = <Future<ProcessResult>>[
          for (var i = 0; i < k; i++)
            runGit(repo.dir.path, const ['status', '--porcelain']),
        ];
        final results = await Future.wait(futures);

        expect(GitSpawn.runCount, 1,
            reason: 'K=$k identical concurrent runGit reads fired via '
                'Future.wait must coalesce onto exactly one subprocess '
                'spawn, got ${GitSpawn.runCount}');

        final first = results.first;
        for (final r in results) {
          expect(identical(r, first), isTrue,
              reason: 'every coalesced caller must receive the exact same '
                  'ProcessResult object (not merely equal bytes) — proof '
                  'they all awaited the one shared in-flight future');
        }
        expect(first.exitCode, 0);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'K=8 DIFFERENT concurrent runGit reads never coalesce — each spawns '
      'its own subprocess',
      () async {
        final repo = await ScratchRepo.create(name: 'coalesce_distinct');
        addTearDown(repo.dispose);
        GitSpawn.reset();

        const k = 8;
        // `log -n 1 --skip=$i` is a dedupable subcommand, always exits 0
        // (skipping past the available commit count just returns an empty
        // page), and is distinct per `i` — so this proves the dedup key is
        // argv-sensitive, not "any read coalesces."
        final futures = <Future<ProcessResult>>[
          for (var i = 0; i < k; i++)
            runGit(repo.dir.path, ['log', '-n', '1', '--skip=$i']),
        ];
        final results = await Future.wait(futures);

        expect(GitSpawn.runCount, k,
            reason: 'K=$k distinct-argv concurrent runGit reads must each '
                'spawn their own subprocess, got ${GitSpawn.runCount}');
        for (final r in results) {
          expect(r.exitCode, 0);
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // -------------------------------------------------------------------
  // Law 2: the semaphore actually bounds peak concurrency.
  // -------------------------------------------------------------------
  group('law 2: semaphore bounds peak concurrency', () {
    tearDown(() {
      GitSpawn.reset();
      resetGitSubprocessPeakForTesting();
    });

    test(
      'K=30 concurrent DISTINCT-argv reads never push observed peak '
      'concurrency above gitSubprocessMaxConcurrency',
      () async {
        final repo = await ScratchRepo.create(name: 'semaphore_peak');
        addTearDown(repo.dispose);
        GitSpawn.reset();
        resetGitSubprocessPeakForTesting();

        const k = 30;
        final futures = <Future<ProcessResult>>[
          for (var i = 0; i < k; i++)
            runGit(repo.dir.path, ['log', '-n', '1', '--skip=$i']),
        ];
        final results = await Future.wait(futures);

        expect(results.length, k);
        for (final r in results) {
          expect(r.exitCode, 0,
              reason: 'every distinct concurrent read must complete '
                  'successfully even while queued behind the semaphore');
        }
        // Confirms none of the 30 accidentally coalesced — otherwise the
        // peak assertion below would be trivially true for the wrong
        // reason (fewer real concurrent acquires than intended).
        expect(GitSpawn.runCount, k,
            reason: 'the 30 distinct-argv reads must not coalesce, so the '
                'semaphore genuinely sees $k independent acquires');

        final peak = gitSubprocessPeakForTesting();
        expect(peak, lessThanOrEqualTo(gitSubprocessMaxConcurrency),
            reason: 'observed peak concurrent git subprocesses ($peak) '
                'must never exceed the semaphore cap '
                '($gitSubprocessMaxConcurrency)');
        expect(peak, greaterThan(0),
            reason: 'sanity: the burst should have actually driven some '
                'concurrency, not degenerated into fully-serial execution');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // -------------------------------------------------------------------
  // Law 3: concurrent mutations never corrupt the object store.
  // -------------------------------------------------------------------
  group('law 3: concurrent mutations never corrupt the object store', () {
    tearDown(GitSpawn.reset);

    Future<void> raceConcurrentCommits(int seed) async {
      final repo = await ScratchRepo.create(name: 'race_mutations_$seed');
      addTearDown(repo.dispose);

      const workerCount = 6;
      // Each worker writes its own file then stages+commits it. Two
      // workers still share ONE index and ONE index.lock, so this
      // genuinely contends: `git add`/`git commit` losing the lock race
      // is expected and tolerated (git.dart's own transient index.lock
      // retry may absorb some of that, but not necessarily all of it
      // under 6-way contention) — only the END STATE must stay
      // uncorrupted, not every individual commit succeed.
      final futures = <Future<ProcessResult>>[
        for (var w = 0; w < workerCount; w++)
          () async {
            final path = 'worker_$w.txt';
            await repo.writeFile(path, 'seed $seed worker $w\n');
            await repo.git(['add', '--', path]);
            return repo.git(['commit', '-m', 'worker $w (seed $seed)']);
          }(),
      ];
      // Deliberately not asserting every result's exitCode — a lost
      // index.lock race is an expected, tolerated outcome per the task
      // spec. Only the post-race object store integrity is a law.
      await Future.wait(futures);

      final fsck = await repo.git(['fsck', '--full', '--no-dangling']);
      expect(fsck.exitCode, 0,
          reason: 'seed $seed: `git fsck --full --no-dangling` must exit '
              'clean after concurrent mutation racing, got exit '
              '${fsck.exitCode}: ${fsck.stderr}');

      final head = await repo.head();
      expect(head, isNotNull,
          reason: 'seed $seed: HEAD must still resolve to a real commit '
              'after the concurrent mutation race');
    }

    for (final seed in [11, 47, 103]) {
      test(
        'seed $seed: fsck stays clean and HEAD resolves after '
        '6-way concurrent write+stage+commit racing',
        () => raceConcurrentCommits(seed),
        timeout: const Timeout(Duration(minutes: 5)),
      );
    }
  });

  // -------------------------------------------------------------------
  // Law 4: a read racing a mutation on the same ref stays consistent.
  // -------------------------------------------------------------------
  group('law 4: a read racing a ref-moving mutation stays consistent', () {
    tearDown(GitSpawn.reset);

    test(
      'repeated concurrent rev-parse HEAD never observes a torn/garbage '
      'value while a commit sequence moves HEAD',
      () async {
        final repo = await ScratchRepo.create(name: 'read_write_race');
        addTearDown(repo.dispose);

        const readerIterations = 60;
        const writerCommits = 20;
        final shaPattern = RegExp(r'^[0-9a-f]{40}$');

        final readResults = <ProcessResult>[];
        Future<void> readerLoop() async {
          for (var i = 0; i < readerIterations; i++) {
            // Bare runGit — models the app's background refresh reading
            // HEAD while the user's terminal (modeled by the writer
            // lane below) commits concurrently.
            readResults
                .add(await runGit(repo.dir.path, const ['rev-parse', 'HEAD']));
          }
        }

        Future<void> writerLoop() async {
          for (var i = 0; i < writerCommits; i++) {
            await repo.writeFile('mover.txt', 'revision $i\n');
            await repo.git(['add', '--', 'mover.txt']);
            await repo.git(['commit', '-m', 'move HEAD ($i)']);
          }
        }

        // Real concurrency: both lanes are in flight together, not
        // sequential-awaits-in-disguise. Neither lane awaits the other.
        await Future.wait([readerLoop(), writerLoop()]);

        expect(readResults.length, readerIterations);
        for (final result in readResults) {
          if (result.exitCode == 0) {
            final sha = result.stdout.toString().trim();
            expect(shaPattern.hasMatch(sha), isTrue,
                reason: 'a successful `rev-parse HEAD` must return a '
                    'well-formed 40-hex sha, got: "$sha"');
            final catFile = await repo.git(['cat-file', '-t', sha]);
            expect(catFile.exitCode, 0,
                reason: 'sha "$sha" returned by a racing rev-parse HEAD '
                    'must resolve to a real object in the store');
            expect(catFile.stdout.toString().trim(), 'commit',
                reason: 'sha "$sha" returned by rev-parse HEAD must be a '
                    'commit object — never a torn or garbage read');
          } else {
            // A clean failure is acceptable; a torn read that dumps
            // partial bytes to stdout while still exiting nonzero is not.
            expect(result.stdout.toString().trim(), isEmpty,
                reason: 'a failed rev-parse HEAD must never leak partial '
                    'stdout bytes — clean failure only, never garbage');
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // -------------------------------------------------------------------
  // Law 5: resolver single-flight dedups a stampede.
  // -------------------------------------------------------------------
  group('law 5: resolver single-flight dedups a stampede', () {
    setUp(() {
      GitSpawn.reset();
      invalidateAllLogosGit();
    });
    tearDown(() {
      GitSpawn.reset();
      invalidateAllLogosGit();
    });

    test(
      'K=6 concurrent resolveLogosGit calls for the same repo, fired '
      'without an intervening await, share ONE built engine and spawn '
      'far fewer than K× the git work of a solo build',
      () async {
        final repo = await _oneCommitRepo('resolver_stampede');
        addTearDown(repo.dispose);

        GitSpawn.reset(); // exclude the repo-creation spawns above.

        const k = 6;
        // No await between calls — this is the actual stampede, not a
        // relabeled sequential fetch.
        final futures = <Future<Object?>>[
          for (var i = 0; i < k; i++) resolveLogosGit(repo.dir.path),
        ];
        final results = await Future.wait(futures);
        final stampedeSpawnCount = GitSpawn.runCount + GitSpawn.startCount;

        expect(results, everyElement(isNotNull),
            reason: 'every stampede resolve must succeed');
        final first = results.first;
        for (final engine in results) {
          expect(identical(engine, first), isTrue,
              reason: 'K=$k concurrent resolveLogosGit calls for the same '
                  'repo, fired without an intervening await, must all '
                  'share the exact same built engine instance');
        }

        // Baseline: the git-spawn cost of one independent, uncontended
        // build for the same repo — proves the stampede did roughly ONE
        // build's worth of work, not K times that.
        invalidateLogosGit(repo.dir.path);
        GitSpawn.reset();
        final solo = await resolveLogosGit(repo.dir.path);
        expect(solo, isNotNull);
        final soloSpawnCount = GitSpawn.runCount + GitSpawn.startCount;

        expect(
          stampedeSpawnCount,
          lessThanOrEqualTo(soloSpawnCount + 5),
          reason: 'stampede of $k concurrent resolves spawned '
              '$stampedeSpawnCount git processes vs $soloSpawnCount for a '
              'single independent resolve — single-flight must collapse '
              'the stampede onto ~one build, not duplicate the git-log '
              'walk per caller',
        );
        expect(
          stampedeSpawnCount,
          lessThan(k * soloSpawnCount),
          reason: 'stampede spawn count ($stampedeSpawnCount) must be far '
              'below $k× a solo build\'s spawn count ($soloSpawnCount)',
        );

        // A 7th call after everything has settled returns the cached
        // instance rather than rebuilding again.
        final seventh = await resolveLogosGit(repo.dir.path);
        expect(identical(seventh, solo), isTrue,
            reason: 'a resolve after the stampede has settled must return '
                'the cached engine, not trigger yet another rebuild');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // -------------------------------------------------------------------
  // Law 6: concurrent resolves of DIFFERENT repos respect the LRU bound
  // without deadlock.
  // -------------------------------------------------------------------
  group('law 6: concurrent cross-repo resolves respect the LRU bound', () {
    setUp(invalidateAllLogosGit);
    tearDown(invalidateAllLogosGit);

    test(
      '8 distinct repos resolved concurrently (LRU cap is 5) all complete '
      'without throwing or deadlocking',
      () async {
        final repos = <ScratchRepo>[];
        addTearDown(() async {
          for (final r in repos) {
            await r.dispose();
          }
        });
        for (var i = 0; i < 8; i++) {
          repos.add(await _oneCommitRepo('resolver_lru_race_$i'));
        }

        final results = await Future.wait(<Future<Object?>>[
          for (final r in repos) resolveLogosGit(r.dir.path),
        ]);

        expect(results.length, 8);
        expect(results, everyElement(isNotNull),
            reason: 'every distinct-repo concurrent resolve must complete '
                'cleanly, even though the engine LRU is bounded at 5 and '
                'must evict/rebuild rather than deadlock under concurrent '
                'pressure');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
