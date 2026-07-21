// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Witnesses for the ABSORPTION LAW — existential over history: a branch is
// absorbed into its base iff SOME first-parent base commit c since the fork
// satisfies `git merge-tree --write-tree <c> <branch>` == c's own tree.
// Judge by content, not ancestry; once witnessed, permanent — base evolving
// afterwards cannot revoke delivery. These run against REAL scratch git
// repos (Directory.systemTemp + git init — the repo fixture pattern from
// test/backend and test/features/history/worldline_field_test).
//
// Each case pins one shape the law must get exactly right:
//   * (a) squash-merge    — flattened history; `--merged` misses it, the law
//                           catches it because the merged TREE equals base.
//   * (b) transplant      — Manifold's move-changes flow: identical content
//                           arrives on base via an UNRELATED commit. Ancestry
//                           says "1 ahead"; the tree says absorbed.
//   * (c) diverged        — genuine unique work must NOT read absorbed, and
//                           the exact outstanding file must be named.
//   * (d) conflict        — overlapping edits: conflicted, never absorbed.
//   * (e) unsupported git — the < 2.38 gate returns null (unknown) and the
//                           batch pass falls back to legacy squash detection.
//   * (f) THE ORRERY CASE — squash-merged, then base REWROTE the same files
//                           (tip merge-tree conflicts): still absorbed, with
//                           the squash commit as the witness. The historical
//                           law's raison d'etre.
//   * (g) transplant + later base evolution rewriting the same file →
//                           absorbed via the patch-id fast path, witness =
//                           the transplant commit.
//   * (h) split transplant— branch content applied as TWO separate base
//                           commits (patch-id misses); the linear scan finds
//                           the second application commit as witness (by
//                           then all content is in).
//   * (i) deep fork       — a long unrelated stretch before the delivery:
//                           the UNCAPPED scan still proves the verdict.
//   * (j) permanence cache— a witnessed verdict for a fixed branch tip is
//                           served from cache (proved by disabling the
//                           support gate: recomputation impossible).
//   * (k) frontier        — proven-no re-probes are incremental and FLIP
//                           when a new base commit delivers the content.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> git(Directory repo, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
  }

  Future<String> gitOut(Directory repo, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: repo.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  Future<Directory> makeRepo() async {
    final repo = await Directory.systemTemp.createTemp('absorb_test');
    await git(repo, ['init', '-q', '-b', 'main']);
    await git(repo, ['config', 'user.name', 'test']);
    await git(repo, ['config', 'user.email', 'test@local']);
    // Keep line endings byte-stable across platforms so trees compare cleanly.
    await git(repo, ['config', 'core.autocrlf', 'false']);
    return repo;
  }

  /// Write [files], stage everything, commit, return the new HEAD hash.
  Future<String> commit(
    Directory repo,
    String message,
    Map<String, String> files,
  ) async {
    for (final e in files.entries) {
      final f = File('${repo.path}${Platform.pathSeparator}${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-q', '-m', message]);
    return gitOut(repo, ['rev-parse', 'HEAD']);
  }

  Future<void> deleteRepo(Directory repo) async {
    if (await repo.exists()) {
      try {
        await repo.delete(recursive: true);
      } on FileSystemException {
        // Windows can hold transient locks on .git; a leaked temp dir
        // must not fail the witness.
      }
    }
  }

  // Every case needs a real git that answers the law. If the host git is too
  // old we can't witness the positive cases at all — skip them loudly rather
  // than pass vacuously. (The dedicated fallback test still runs.)
  Future<bool> lawSupported(Directory repo) {
    resetMergeTreeAbsorptionSupportCache();
    return mergeTreeAbsorptionSupported(repo.path);
  }

  tearDown(() {
    // Never let one test's forced caches leak into the next.
    resetMergeTreeAbsorptionSupportCache();
    resetAbsorptionCaches();
  });

  test('(a) squash-merge → absorbed, no outstanding files', () async {
    final repo = await makeRepo();
    try {
      if (!await lawSupported(repo)) {
        markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
        return;
      }
      await commit(repo, 'base', {'a.txt': 'one\n'});
      await git(repo, ['checkout', '-q', '-b', 'feature']);
      await commit(repo, 'step 1', {'a.txt': 'one\ntwo\n'});
      await commit(repo, 'step 2', {'a.txt': 'one\ntwo\nthree\n'});
      // Squash-merge the whole branch into main as a single flattened commit.
      await git(repo, ['checkout', '-q', 'main']);
      await git(repo, ['merge', '--squash', 'feature']);
      await git(repo, ['commit', '-q', '-m', 'squash feature']);

      final r = await branchAbsorption(repo.path, 'feature', 'main');
      expect(r, isNotNull);
      expect(r!.absorbed, isTrue);
      expect(
        r.via,
        AbsorptionWitnessVia.tip,
        reason: 'nothing landed after the squash → tip is the witness',
      );
      expect(r.witness, await gitOut(repo, ['rev-parse', 'main']));
      expect(r.conflicted, isFalse);
      expect(r.outstandingFiles, isEmpty);
    } finally {
      await deleteRepo(repo);
    }
  });

  test(
    '(b) transplant (identical content, unrelated commit) → absorbed',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\ntwo\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature adds three', {
          'a.txt': 'one\ntwo\nthree\n',
        });
        // TRANSPLANT: main independently reaches the SAME content via its own
        // unrelated commit (no cherry-pick, no shared commit — Manifold's
        // move-changes flow). Ancestry will report 1-ahead / 1-behind ghosts.
        await git(repo, ['checkout', '-q', 'main']);
        await commit(repo, 'transplant three onto main', {
          'a.txt': 'one\ntwo\nthree\n',
        });

        // Ancestry lies: the branch reads ahead of a ghost.
        final counts = await gitOut(repo, [
          'rev-list',
          '--left-right',
          '--count',
          'main...feature',
        ]);
        expect(
          counts.split(RegExp(r'\s+')).map(int.parse).toList(),
          [1, 1],
          reason: 'transplant must look 1-ahead/1-behind by ancestry',
        );

        // The law judges by content: absorbed.
        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(
          r!.absorbed,
          isTrue,
          reason: 'identical content already in main → merging is a no-op',
        );
        expect(r.conflicted, isFalse);
        expect(r.outstandingFiles, isEmpty);
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test(
    '(c) genuinely diverged → not absorbed, names the outstanding file',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'unique work', {'unique.txt': 'only on feature\n'});

        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(r!.absorbed, isFalse);
        expect(r.conflicted, isFalse);
        expect(
          r.outstandingFiles,
          ['unique.txt'],
          reason: 'the exact file the branch still uniquely holds',
        );
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test('(d) overlapping edits → conflicted, not absorbed', () async {
    final repo = await makeRepo();
    try {
      if (!await lawSupported(repo)) {
        markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
        return;
      }
      await commit(repo, 'base', {'a.txt': 'one\ntwo\nthree\n'});
      await git(repo, ['checkout', '-q', '-b', 'feature']);
      await commit(repo, 'branch edits line one', {
        'a.txt': 'BRANCH\ntwo\nthree\n',
      });
      await git(repo, ['checkout', '-q', 'main']);
      await commit(repo, 'main edits line one', {
        'a.txt': 'MAIN\ntwo\nthree\n',
      });

      final r = await branchAbsorption(repo.path, 'feature', 'main');
      expect(r, isNotNull);
      expect(r!.conflicted, isTrue);
      expect(
        r.absorbed,
        isFalse,
        reason: 'a conflicted merge is never a no-op',
      );
      expect(
        r.outstandingFiles,
        contains('a.txt'),
        reason: 'the contended file is surfaced',
      );
    } finally {
      await deleteRepo(repo);
    }
  });

  test(
    '(f) THE ORRERY CASE: squash then base rewrites the same files',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature work', {'a.txt': 'one\ntwo\nthree\n'});
        await git(repo, ['checkout', '-q', 'main']);
        await git(repo, ['merge', '--squash', 'feature']);
        await git(repo, ['commit', '-q', '-m', 'squash feature']);
        final squash = await gitOut(repo, ['rev-parse', 'HEAD']);
        // Base MOVES ON, rewriting the very file the branch delivered — the
        // tip merge-tree now conflicts. History cannot be revoked: at the
        // squash commit, merging was a no-op. Absorbed, permanently.
        await commit(repo, 'main rewrites the file', {
          'a.txt': 'REWRITTEN\nENTIRELY\n',
        });

        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(
          r!.conflicted,
          isTrue,
          reason: 'tip merge-tree must conflict (precondition of the case)',
        );
        expect(
          r.absorbed,
          isTrue,
          reason: 'delivery happened at the squash; evolution cannot revoke',
        );
        expect(r.witness, squash, reason: 'the squash commit is the exhibit');
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test(
    '(g) transplant + later base evolution → absorbed via patch-id',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\ntwo\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature adds three', {
          'a.txt': 'one\ntwo\nthree\n',
        });
        // Transplant onto main (identical content, unrelated commit), then
        // main rewrites the file so the tip check fails.
        await git(repo, ['checkout', '-q', 'main']);
        await commit(repo, 'transplant', {'a.txt': 'one\ntwo\nthree\n'});
        final transplant = await gitOut(repo, ['rev-parse', 'HEAD']);
        await commit(repo, 'main rewrites', {'a.txt': 'DIFFERENT\n'});

        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(r!.absorbed, isTrue);
        expect(
          r.via,
          AbsorptionWitnessVia.patchId,
          reason: 'cumulative branch patch == transplant commit patch',
        );
        expect(r.witness, transplant);
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test(
    '(h) split transplant → absorbed via linear scan at second commit',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\n', 'b.txt': 'x\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature edits both', {
          'a.txt': 'one\ntwo\n',
          'b.txt': 'x\ny\n',
        });
        // Main applies the SAME content as TWO separate commits (no single
        // commit's patch matches the branch's cumulative patch), then rewrites
        // a.txt to defeat the tip check.
        await git(repo, ['checkout', '-q', 'main']);
        await commit(repo, 'split part 1', {'a.txt': 'one\ntwo\n'});
        await commit(repo, 'split part 2', {'b.txt': 'x\ny\n'});
        final part2 = await gitOut(repo, ['rev-parse', 'HEAD']);
        await commit(repo, 'main rewrites a', {'a.txt': 'CHANGED\n'});

        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(
          r!.absorbed,
          isTrue,
          reason: 'at split part 2 all branch content is in → merge no-op',
        );
        expect(
          r.via,
          AbsorptionWitnessVia.scan,
          reason: 'patch-id misses split applications; the walk finds it',
        );
        expect(
          r.witness,
          part2,
          reason: 'the second application commit is the first witness',
        );
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test(
    '(i) deep fork → uncapped scan still proves the verdict',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\n', 'b.txt': 'x\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature edits both', {
          'a.txt': 'one\ntwo\n',
          'b.txt': 'x\ny\n',
        });
        // A LONG stretch of unrelated main history between the fork and the
        // delivery — the scan has no cap, so the witness deep in the range
        // must still be found (and the unrelated commits must all be pruned
        // in memory, never merge-tree'd).
        await git(repo, ['checkout', '-q', 'main']);
        for (var i = 0; i < 40; i++) {
          await commit(repo, 'noise $i', {'noise.txt': 'tick $i\n'});
        }
        // Split transplant at the far end (defeats patch-id), then a rewrite
        // (defeats tip).
        await commit(repo, 'split part 1', {'a.txt': 'one\ntwo\n'});
        await commit(repo, 'split part 2', {'b.txt': 'x\ny\n'});
        final part2 = await gitOut(repo, ['rev-parse', 'HEAD']);
        await commit(repo, 'main rewrites a', {'a.txt': 'CHANGED\n'});

        final r = await branchAbsorption(repo.path, 'feature', 'main');
        expect(r, isNotNull);
        expect(
          r!.absorbed,
          isTrue,
          reason: 'no cap: the deep witness must be found',
        );
        expect(r.witness, part2);
        expect(r.via, AbsorptionWitnessVia.scan);
      } finally {
        await deleteRepo(repo);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '(j) permanence cache: witnessed verdict never re-probes a fixed tip',
    () async {
      final repo = await makeRepo();
      try {
        if (!await lawSupported(repo)) {
          markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
          return;
        }
        await commit(repo, 'base', {'a.txt': 'one\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'feature work', {'a.txt': 'one\ntwo\n'});
        await git(repo, ['checkout', '-q', 'main']);
        await git(repo, ['merge', '--squash', 'feature']);
        await git(repo, ['commit', '-q', '-m', 'squash feature']);

        final cold = await branchAbsorption(repo.path, 'feature', 'main');
        expect(cold, isNotNull);
        expect(cold!.absorbed, isTrue);

        // Force the support gate OFF. A recomputation is now impossible —
        // so a second identical answer PROVES the permanence cache served it.
        resetMergeTreeAbsorptionSupportCache(false);
        final warm = await branchAbsorption(repo.path, 'feature', 'main');
        expect(
          warm,
          isNotNull,
          reason: 'cache hit precedes the support gate: no git needed',
        );
        expect(warm!.absorbed, isTrue);
        expect(warm.witness, cold.witness);
        expect(warm.via, cold.via);
      } finally {
        await deleteRepo(repo);
      }
    },
  );

  test('(k) frontier: proven-no re-probe is incremental and flips on a '
      'late transplant', () async {
    final repo = await makeRepo();
    try {
      if (!await lawSupported(repo)) {
        markTestSkipped('git < 2.38: merge-tree --write-tree unavailable');
        return;
      }
      await commit(repo, 'base', {'a.txt': 'one\n'});
      await git(repo, ['checkout', '-q', '-b', 'feature']);
      await commit(repo, 'feature adds two', {'a.txt': 'one\ntwo\n'});
      await git(repo, ['checkout', '-q', 'main']);
      await commit(repo, 'main other work', {'other.txt': 'z\n'});

      final first = await branchAbsorption(repo.path, 'feature', 'main');
      expect(first, isNotNull);
      expect(first!.absorbed, isFalse, reason: 'nothing delivered yet');

      // Same tips → the frontier answers without rescanning (same verdict).
      final same = await branchAbsorption(repo.path, 'feature', 'main');
      expect(same!.absorbed, isFalse);

      // NEW base commit transplants the content. The incremental walk only
      // examines this one commit — and must flip the verdict with it as
      // the witness. This is the frontier's correctness contract: proven-no
      // is a statement about examined history, never a sticky state.
      await commit(repo, 'late transplant', {'a.txt': 'one\ntwo\n'});
      final transplant = await gitOut(repo, ['rev-parse', 'HEAD']);
      final flipped = await branchAbsorption(repo.path, 'feature', 'main');
      expect(flipped, isNotNull);
      expect(
        flipped!.absorbed,
        isTrue,
        reason: 'the new commit is examined and witnesses absorption',
      );
      expect(flipped.witness, transplant);
    } finally {
      await deleteRepo(repo);
    }
  });

  test(
    '(e) unsupported git → branchAbsorption unknown; batch falls back',
    () async {
      final repo = await makeRepo();
      try {
        await commit(repo, 'base', {'a.txt': 'one\n'});
        await git(repo, ['checkout', '-q', '-b', 'feature']);
        await commit(repo, 'step', {'a.txt': 'one\ntwo\n'});
        // Squash-merge so the LEGACY fallback (git cherry) has something to find.
        await git(repo, ['checkout', '-q', 'main']);
        await git(repo, ['merge', '--squash', 'feature']);
        await git(repo, ['commit', '-q', '-m', 'squash feature']);

        // Force the support gate OFF to simulate git < 2.38 without needing an
        // ancient binary on the host.
        resetMergeTreeAbsorptionSupportCache(false);

        // The single-branch primitive reports null (unknown) — everything the
        // caller does downstream then falls back to legacy behaviour.
        final unknown = await branchAbsorption(repo.path, 'feature', 'main');
        expect(unknown, isNull, reason: 'no verdict on unsupported git');

        // The batch pass folds cleanly to the legacy squash check: absorbed
        // stays null, squashMerged carries the (fallback) truth.
        const seed = [
          BranchInfo(name: 'main', current: true, ahead: 0, behind: 0),
          BranchInfo(name: 'feature', current: false, ahead: 0, behind: 0),
        ];
        final batched = await detectAbsorbedBranches(
          repo.path,
          seed,
          baseRef: 'main',
        );
        final feature = batched.firstWhere((b) => b.name == 'feature');
        expect(
          feature.absorbed,
          isNull,
          reason: 'absorption law not consulted on unsupported git',
        );
        expect(
          feature.squashMerged,
          isTrue,
          reason: 'legacy git cherry fallback still detects the squash',
        );
      } finally {
        resetMergeTreeAbsorptionSupportCache();
        await deleteRepo(repo);
      }
    },
  );
}
