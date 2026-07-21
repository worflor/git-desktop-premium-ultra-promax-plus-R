// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// First-ever coverage for lib/backend/history_surgery.dart — an irreversible
// git-history-rewriting engine (HistorySurgeryEngine). A bug here can destroy
// a user's real history, so every assertion here reads independent `git`
// plumbing as the oracle (ls-tree, rev-list --objects, for-each-ref, fsck),
// never the engine's own return values, per the LAW behind
// test/backend/commit_staging_test.dart and test/fuzz/git_op_sequence_safety_test.dart.
//
// CONTRACTS asserted (see HistorySurgeryEngine dartdoc + surgery_state.dart /
// history_surgery_page.dart for how the UI drives it):
//   1. Rollback is exact: every refs/heads/* and refs/tags/* ref is restored
//      to its byte-identical pre-surgery object after execute()+rollback().
//   2. createBackupRefs() backs up every refs/heads/*, refs/tags/* ref with
//      its exact pre-surgery object BEFORE the destructive rewrite runs.
//   3. Purge is complete: after execute(), the target content is unreachable
//      from every production (non-backup) ref — proven via
//      `git rev-list --objects --branches --tags` and `git log --diff-filter`.
//   4. No collateral damage: every OTHER path's blob sha in the final trees
//      is byte-identical to its pre-surgery value; untouched refs (never
//      exposed to the target path anywhere in their history) keep their
//      EXACT original commit sha.
//   5. The repo stays valid: `git fsck --full` is clean after execute() and
//      after rollback(); HEAD always resolves.
//   6. Idempotence: purging a nonexistent path, or purging an already-purged
//      path again, is a safe true no-op; verifyPurge on untouched history is
//      true.
//   7. Fuzzed random histories (seeded, deterministic, MANIFOLD_FUZZ-scaled)
//      preserve 1/3/5 universally.
//
// verifyPurge() scopes its `git log` scan to `--branches --tags`, matching
// execute()'s own rev-list scope — it does not sweep up the surgery's own
// backup refs (refs/manifold-surgery-backup/<ts>/...), which deliberately
// still point at pre-purge history so rollback works. See the
// `verifyPurge scope` group below.

import 'dart:io' show ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/history_surgery.dart';

import '../support/prop.dart' show fuzzScale;
import '../support/scratch_repo.dart';

/// The well-known empty-tree sha every git repo has, hardcoded identically
/// inside history_surgery.dart's root-commit-graft path — used here to
/// verify that path independently.
const String _kEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

// ---------------------------------------------------------------------------
// Independent oracles — never call into HistorySurgeryEngine internals.
// ---------------------------------------------------------------------------

/// `refname -> objectname` for every ref under refs/heads/* and refs/tags/*
/// — deliberately excluding the surgery's own backup namespace, because
/// "restored to before" means the production refs, not the backups the
/// operation lays down as its own safety net. For an annotated tag,
/// `%(objectname)` is the TAG object's own sha (not dereferenced), matching
/// exactly what `createBackupRefs`/`rollback` store and restore.
Future<Map<String, String>> productionRefSnapshot(ScratchRepo repo) async {
  final String out = await repo.gitOk([
    'for-each-ref',
    '--format=%(refname) %(objectname)',
    'refs/heads/',
    'refs/tags/',
  ]);
  final Map<String, String> map = <String, String>{};
  if (out.isEmpty) return map;
  for (final String line in out.split('\n')) {
    if (line.trim().isEmpty) continue;
    final List<String> parts = line.trim().split(' ');
    if (parts.length < 2) continue;
    map[parts[0]] = parts[1];
  }
  return map;
}

/// `path -> blob sha` for every blob in [ref]'s tree, via `git ls-tree -r`.
Future<Map<String, String>> treeSnapshot(ScratchRepo repo, String ref) async {
  final ProcessResult r = await repo.git(['ls-tree', '-r', ref]);
  final Map<String, String> map = <String, String>{};
  if (r.exitCode != 0) return map;
  final String out = r.stdout.toString().trim();
  if (out.isEmpty) return map;
  for (final String line in out.split('\n')) {
    if (line.isEmpty) continue;
    final int tab = line.indexOf('\t');
    if (tab < 0) continue;
    final List<String> meta = line.substring(0, tab).split(RegExp(r'\s+'));
    if (meta.length < 3) continue;
    map[line.substring(tab + 1)] = meta[2];
  }
  return map;
}

/// Every ref currently living under [prefix] (a `createBackupRefs()` /
/// `execute()` result's `backupPrefix`).
Future<List<String>> backupRefsUnder(ScratchRepo repo, String prefix) async {
  final ProcessResult r =
      await repo.git(['for-each-ref', '--format=%(refname)', prefix]);
  if (r.exitCode != 0) return <String>[];
  return r.stdout
      .toString()
      .trim()
      .split('\n')
      .where((String l) => l.isNotEmpty)
      .toList();
}

/// The purge-completeness oracle scoped to PRODUCTION refs only
/// (`--branches --tags`, never `--all`) — this is what "no trace remains in
/// the repo's real history" actually means, since the surgery's own backup
/// refs are deliberately kept around (unpurged) for rollback.
Future<bool> purgedAccordingToPlumbing(
    ScratchRepo repo, Set<String> targetPaths) async {
  final ProcessResult r = await repo.git([
    'log',
    '--branches',
    '--tags',
    '--oneline',
    '--diff-filter=ACDMR',
    '--',
    ...targetPaths,
  ]);
  return r.exitCode == 0 && r.stdout.toString().trim().isEmpty;
}

Future<bool> fsckClean(ScratchRepo repo) async {
  final ProcessResult r = await repo.git(['fsck', '--full', '--no-dangling']);
  return r.exitCode == 0;
}

/// True if [path] exists in the tree of the currently checked-out commit
/// (`HEAD`), checked directly against the object database via
/// `git cat-file -e HEAD:<path>` — independent of the engine's own return
/// values, and independent of whatever the working-tree FILE happens to
/// contain.
Future<bool> pathExistsAtHead(ScratchRepo repo, String path) async {
  final ProcessResult r = await repo.git(['cat-file', '-e', 'HEAD:$path']);
  return r.exitCode == 0;
}

/// Commits [path] on a throwaway branch, detaches `HEAD` directly onto
/// that commit, then deletes the branch — so the commit is reachable from
/// nothing but `HEAD` itself, not from any branch or tag. Returns the
/// commit sha. Callers must confirm the precondition via
/// [assertDetachedAndUnreachable] before trusting the scenario.
Future<String> buildUnreachableDetachedHead(
    ScratchRepo repo, String path, String content) async {
  await repo.gitOk(['checkout', '-b', '_tmp_unreachable']);
  await repo.writeFile(path, content);
  final String sha =
      await repo.commitAll('add $path (about to become unreachable)');
  await repo.gitOk(['checkout', sha]); // detach HEAD directly onto it
  await repo.gitOk(['branch', '-D', '_tmp_unreachable']);
  return sha;
}

/// Independently (never via the engine) proves that `HEAD` is detached
/// exactly at [sha], and that [sha] is reachable from no branch and no
/// tag — the precondition every "detached HEAD" test below depends on.
Future<void> assertDetachedAndUnreachable(ScratchRepo repo, String sha) async {
  expect(await repo.gitOk(['rev-parse', 'HEAD']), sha,
      reason: 'precondition: HEAD must be detached exactly at the target '
          'commit');
  expect((await repo.git(['symbolic-ref', '-q', 'HEAD'])).exitCode, isNot(0),
      reason: 'precondition: HEAD must be detached (no symbolic ref) — '
          "the exact branch of execute()'s \"Update HEAD if detached\" "
          'check');
  // NOTE: `git branch --contains <sha>` / `git tag --contains <sha>` are
  // the wrong oracle here — `branch --contains` prints a synthetic
  // `* (HEAD detached at <sha>)` pseudo-line for the detached HEAD itself
  // (a commit trivially "contains" itself), which is not a real branch
  // and would make this precondition check false-negative on every
  // detached HEAD. `for-each-ref --contains` only ever lists real refs.
  expect(await repo.gitOk(['for-each-ref', '--contains', sha, 'refs/heads/']),
      isEmpty,
      reason: 'precondition: no branch may reach the target commit');
  expect(await repo.gitOk(['for-each-ref', '--contains', sha, 'refs/tags/']),
      isEmpty,
      reason: 'precondition: no tag may reach the target commit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // createBackupRefs — property 2
  // ---------------------------------------------------------------------
  group('createBackupRefs', () {
    test(
        'creates one backup ref for every existing heads/tags ref, storing '
        'the exact pre-surgery object, before any rewrite happens', () async {
      final ScratchRepo repo = await ScratchRepo.create(name: 'backup_unit');
      try {
        await repo.writeFile('a.txt', '1\n');
        await repo.commitAll('a');
        await repo.gitOk(['checkout', '-b', 'topic']);
        await repo.writeFile('b.txt', '2\n');
        await repo.commitAll('b');
        await repo.gitOk(['checkout', 'main']);
        await repo.gitOk(['tag', '-a', 'v1', '-m', 'v1 release']);

        final Map<String, String> before = await productionRefSnapshot(repo);
        // root (from ScratchRepo.create), main tip, topic tip, and the tag.
        expect(before.length, 3, reason: before.toString());

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final String prefix = await engine.createBackupRefs();
        expect(prefix, isNotEmpty);

        final List<String> backups = await backupRefsUnder(repo, prefix);
        expect(backups.length, before.length,
            reason: 'every pre-surgery head/tag ref must get a backup');

        for (final MapEntry<String, String> e in before.entries) {
          final String expected =
              '$prefix/${e.key.replaceFirst('refs/', '')}';
          expect(backups, contains(expected),
              reason: 'missing backup for ${e.key}');
          final String storedRaw = await repo.gitOk(
              ['for-each-ref', '--format=%(objectname)', expected]);
          expect(storedRaw, e.value,
              reason: 'backup for ${e.key} must store the exact '
                  'pre-surgery object, not a dereferenced/rewritten one');
        }

        // Merely creating backups must never itself move a production ref.
        expect(await productionRefSnapshot(repo), equals(before));
      } finally {
        await repo.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------
  // dirty working tree guard
  // ---------------------------------------------------------------------
  group('dirty working tree guard', () {
    test(
        'execute() refuses to run and creates NO backups when the working '
        'tree is dirty', () async {
      final ScratchRepo repo = await ScratchRepo.create(name: 'dirty_guard');
      try {
        await repo.writeFile('a.txt', '1\n');
        await repo.commitAll('a');
        await repo.writeFile('untracked.txt', 'oops\n');

        final Map<String, String> beforeRefs =
            await productionRefSnapshot(repo);

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult result =
            await engine.execute(<String>{'a.txt'}, (SurgeryProgress p) {});

        expect(result.success, isFalse);
        expect(result.error, contains('uncommitted'));
        expect(result.backupPrefix, isEmpty);
        expect(result.commitsRewritten, 0);

        final List<String> allRefs = await repo.allRefs();
        expect(
            allRefs.where((String r) => r.contains('manifold-surgery-backup')),
            isEmpty,
            reason: 'a rejected dirty-tree surgery must not create any '
                'backup refs');
        expect(await productionRefSnapshot(repo), equals(beforeRefs));
      } finally {
        await repo.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------
  // The big integration test: rollback exactness, backup completeness,
  // purge completeness, no collateral damage, repo validity — all against
  // one realistic multi-branch/tag/merge history.
  // ---------------------------------------------------------------------
  group('execute() — full contract', () {
    test(
        'rollback is byte-exact; purge is complete on production refs; no '
        'collateral damage to unrelated paths/refs; repo stays valid '
        'throughout', () async {
      final ScratchRepo repo = await ScratchRepo.create(name: 'surgery_main');
      try {
        // ---- build a realistic multi-branch/tag/merge history ----
        await repo.writeFile('safe.txt', 'v1\n');
        await repo.writeFile('secret.txt', 'TOP SECRET v1\n');
        final String commitA = await repo.commitAll('add safe and secret v1');

        await repo.writeFile('safe.txt', 'v2\n');
        await repo.writeFile('secret.txt', 'TOP SECRET v2\n');
        final String commitB =
            await repo.commitAll('update safe and secret v2');

        await repo.gitOk(['tag', '-a', 'v1.0', '-m', 'release 1.0', commitB]);
        await repo.gitOk(['tag', 'v0.9-lw', commitA]);

        await repo.gitOk(['checkout', '-b', 'feature']);
        await repo.writeFile('feature.txt', 'feature work\n');
        await repo.commitAll('add feature.txt');

        await repo.gitOk(['checkout', 'main']);
        await repo.writeFile('safe.txt', 'v3 on main\n');
        await repo.commitAll('advance main independently');

        final ProcessResult mergeR =
            await repo.git(['merge', '--no-edit', 'feature']);
        expect(mergeR.exitCode, 0, reason: mergeR.stderr.toString());

        expect(await repo.isClean(), isTrue);

        // ---- capture full BEFORE state ----
        final Map<String, String> beforeRefs =
            await productionRefSnapshot(repo);
        expect(beforeRefs.length, 4, reason: beforeRefs.toString());
        final Map<String, Map<String, String>> beforeTrees =
            <String, Map<String, String>>{
          for (final String ref in beforeRefs.keys)
            ref: await treeSnapshot(repo, ref),
        };
        expect(await fsckClean(repo), isTrue);

        // ---- run the surgery ----
        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final List<SurgeryProgress> progressEvents = <SurgeryProgress>[];
        final SurgeryResult result = await engine
            .execute(<String>{'secret.txt'}, progressEvents.add);

        expect(result.success, isTrue, reason: result.error ?? '');
        expect(result.backupPrefix, isNotEmpty);
        expect(progressEvents, isNotEmpty);
        // feature (commitC) never touched secret.txt anywhere in its
        // ancestry up to the branch point, main+tags did — some rewrite
        // must have happened.
        expect(result.commitsRewritten, greaterThan(0));

        // ---- property 2: backups cover every pre-surgery ref exactly ----
        final List<String> backups =
            await backupRefsUnder(repo, result.backupPrefix);
        expect(backups.length, beforeRefs.length);
        for (final MapEntry<String, String> e in beforeRefs.entries) {
          final String expected =
              '${result.backupPrefix}/${e.key.replaceFirst('refs/', '')}';
          expect(backups, contains(expected));
          final String storedRaw = await repo.gitOk(
              ['for-each-ref', '--format=%(objectname)', expected]);
          expect(storedRaw, e.value);
        }

        // ---- property 4a: every ref's TIP moved (each one's own tree is a
        // full snapshot that included secret.txt, inherited unchanged from
        // commitB, so every tip legitimately gets a new sha here — a git
        // tree is a full snapshot, not a diff, so "never touched the file
        // in a diff sense" does not imply "sha survives pruning") ----
        final Map<String, String> afterRefs =
            await productionRefSnapshot(repo);
        for (final String ref in beforeRefs.keys) {
          expect(afterRefs[ref], isNot(beforeRefs[ref]),
              reason: '$ref\'s tree included secret.txt (inherited from '
                  'commitB), so its sha must change when secret.txt is '
                  'pruned');
        }
        expect(await repo.gitOk(['show', 'feature:feature.txt']),
            'feature work');
        expect((await repo.git(['show', 'feature:secret.txt'])).exitCode,
            isNot(0));

        // ---- property 4b: no collateral damage — every OTHER path's blob
        // sha is byte-identical; the target path is gone ----
        for (final String ref in beforeRefs.keys) {
          final Map<String, String> beforeTree = beforeTrees[ref]!;
          final Map<String, String> afterTree = await treeSnapshot(repo, ref);
          expect(afterTree.containsKey('secret.txt'), isFalse,
              reason: '$ref still contains secret.txt after purge');
          for (final MapEntry<String, String> pathEntry
              in beforeTree.entries) {
            if (pathEntry.key == 'secret.txt') continue;
            expect(afterTree[pathEntry.key], pathEntry.value,
                reason: '$ref path ${pathEntry.key} blob sha changed — '
                    'collateral damage from purging secret.txt');
          }
          expect(
              afterTree.keys.toSet(),
              equals(beforeTree.keys.toSet()
                ..remove('secret.txt')),
              reason: '$ref gained or lost an unrelated path');
        }

        // ---- property 3: purge is complete on every production ref,
        // proven at the OBJECT level (not just diff-based) ----
        expect(await purgedAccordingToPlumbing(repo, <String>{'secret.txt'}),
            isTrue);
        final String secretV1Sha = beforeTrees['refs/tags/v0.9-lw']!['secret.txt']!;
        final String secretV2Sha = beforeTrees['refs/tags/v1.0']!['secret.txt']!;
        final String reachableObjects = await repo
            .gitOk(['rev-list', '--objects', '--branches', '--tags']);
        expect(reachableObjects, isNot(contains(secretV1Sha)),
            reason: 'the v1 secret.txt blob must be unreachable from every '
                'production ref');
        expect(reachableObjects, isNot(contains(secretV2Sha)),
            reason: 'the v2 secret.txt blob must be unreachable from every '
                'production ref');

        // ---- content sanity, straight from the object database ----
        expect((await repo.git(['show', 'main:secret.txt'])).exitCode,
            isNot(0));
        expect(await repo.gitOk(['show', 'main:safe.txt']), 'v3 on main');
        expect(await repo.gitOk(['show', 'main:feature.txt']), 'feature work');
        expect(await repo.gitOk(['show', 'v1.0:safe.txt']), 'v2');
        expect((await repo.git(['show', 'v1.0:secret.txt'])).exitCode,
            isNot(0));
        expect(await repo.gitOk(['show', 'v0.9-lw:safe.txt']), 'v1');
        expect((await repo.git(['show', 'v0.9-lw:secret.txt'])).exitCode,
            isNot(0));

        // The annotated tag must still exist and still be annotated (its
        // message preserved) even though its underlying commit changed.
        final String tagList = await repo.gitOk(['tag', '-l', 'v1.0']);
        expect(tagList, 'v1.0');
        final String tagMsg =
            await repo.gitOk(['for-each-ref', '--format=%(contents)', 'refs/tags/v1.0']);
        expect(tagMsg.trim(), 'release 1.0');

        // ---- property 5 (part 1): repo valid after execute() ----
        expect(await fsckClean(repo), isTrue);
        expect(await repo.head(), isNotNull);

        // ---- property 1: rollback restores every production ref to its
        // EXACT pre-surgery object, byte-for-byte ----
        await engine.rollback(result.backupPrefix);

        expect(await productionRefSnapshot(repo), equals(beforeRefs),
            reason: 'rollback did not restore every ref to its exact '
                'pre-surgery object');
        expect(await repo.currentBranch(), 'main');
        expect(await repo.head(), beforeRefs['refs/heads/main']);
        expect(await repo.gitOk(['show', 'main:secret.txt']), 'TOP SECRET v2');
        expect(await repo.gitOk(['show', 'v0.9-lw:secret.txt']),
            'TOP SECRET v1');

        // ---- property 5 (part 2): repo valid after rollback ----
        expect(await fsckClean(repo), isTrue);
        expect(await repo.head(), isNotNull);
      } finally {
        await repo.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------
  // True passthrough — a git tree is a full snapshot, not a diff, so only a
  // ref whose tip commit's tree NEVER contained the target path (i.e. it
  // forked before the target path was ever introduced, and never received
  // it) can keep its EXACT original sha across the rewrite.
  // ---------------------------------------------------------------------
  group('no collateral damage — true passthrough', () {
    test(
        'a branch forked before the target path ever existed, and never '
        'touching it since, keeps its EXACT original commit sha across the '
        'whole rewrite', () async {
      final ScratchRepo repo = await ScratchRepo.create(name: 'passthrough');
      try {
        await repo.writeFile('shared.txt', 'shared v1\n');
        await repo.commitAll('add shared.txt');

        // Fork here — BEFORE secret.txt is ever introduced anywhere.
        await repo.gitOk(['branch', 'untouched-side']);
        await repo.gitOk(['checkout', 'untouched-side']);
        await repo.writeFile('side.txt', 'side-only content\n');
        final String sideCommit = await repo.commitAll('side-only work');

        await repo.gitOk(['checkout', 'main']);
        await repo.writeFile('secret.txt', 'shh\n');
        await repo.commitAll('add secret.txt on main only');

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult result = await engine
            .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
        expect(result.success, isTrue, reason: result.error ?? '');

        expect(await repo.gitOk(['rev-parse', 'untouched-side']), sideCommit,
            reason: 'untouched-side never had secret.txt in any commit\'s '
                'tree and must keep the EXACT original sha — a real git '
                'object, not a re-created lookalike');
        expect(
            await repo.gitOk(['rev-parse', 'main']), isNot(sideCommit));
      } finally {
        await repo.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------
  // idempotence / no-op safety — property 6
  // ---------------------------------------------------------------------
  group('idempotence / no-op safety', () {
    test('purging a path that never existed anywhere in history is a safe '
        'true no-op', () async {
      final ScratchRepo repo =
          await ScratchRepo.create(name: 'noop_nonexistent');
      try {
        await repo.writeFile('a.txt', '1\n');
        await repo.commitAll('a');
        await repo.writeFile('a.txt', '2\n');
        await repo.commitAll('a2');

        final Map<String, String> beforeRefs =
            await productionRefSnapshot(repo);
        expect(await fsckClean(repo), isTrue);

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult result = await engine.execute(
            <String>{'nonexistent-file.bin'}, (SurgeryProgress p) {});

        expect(result.success, isTrue, reason: result.error ?? '');
        expect(result.commitsRewritten, 0);
        expect(result.refsUpdated, 0);
        // Backups are still created defensively even though nothing will
        // actually change — the backup-first policy is unconditional.
        expect(result.backupPrefix, isNotEmpty);
        expect(await backupRefsUnder(repo, result.backupPrefix), isNotEmpty);

        expect(await productionRefSnapshot(repo), equals(beforeRefs),
            reason: 'a no-op purge must not move any production ref');
        expect(await fsckClean(repo), isTrue);
        expect(await engine.verifyPurge(<String>{'nonexistent-file.bin'}),
            isTrue);
      } finally {
        await repo.dispose();
      }
    });

    test('verifyPurge is true for a path that never appeared in history '
        '(no backup-ref pollution to contend with)', () async {
      final ScratchRepo repo =
          await ScratchRepo.create(name: 'noop_verify_clean');
      try {
        await repo.writeFile('a.txt', 'hi\n');
        await repo.commitAll('a');
        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        expect(await engine.verifyPurge(<String>{'never-was-here.txt'}),
            isTrue);
      } finally {
        await repo.dispose();
      }
    });

    test('running execute() a second time after a real purge touches '
        'nothing', () async {
      final ScratchRepo repo =
          await ScratchRepo.create(name: 'noop_second_run');
      try {
        await repo.writeFile('safe.txt', 'v1\n');
        await repo.writeFile('secret.txt', 'shh\n');
        await repo.commitAll('v1');

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult first = await engine
            .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
        expect(first.success, isTrue, reason: first.error ?? '');
        expect(first.commitsRewritten, greaterThan(0));

        final Map<String, String> afterFirst =
            await productionRefSnapshot(repo);
        final SurgeryResult second = await engine
            .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
        expect(second.success, isTrue, reason: second.error ?? '');
        expect(second.commitsRewritten, 0,
            reason: 'the content is already gone; a second purge of the '
                'same path must touch nothing');
        expect(second.refsUpdated, 0);
        expect(await productionRefSnapshot(repo), equals(afterFirst));
      } finally {
        await repo.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------
  // Fully-pruned commits — the "graft"/"empty root" branches in _pruneTree.
  // ---------------------------------------------------------------------
  group('fully-pruned commits (a commit whose entire tree is target content)',
      () {
    test('a fully-pruned commit with a real parent vanishes; its child '
        'grafts directly onto the grandparent, byte-identical sha', () async {
      final ScratchRepo repo =
          await ScratchRepo.create(name: 'mid_prune_graft');
      try {
        final String root = (await repo.head())!;

        await repo.writeFile('secret.txt', 'only secret here\n');
        await repo.commitAll('adds ONLY secret.txt');

        await repo.writeFile('safe.txt', 'safe content\n');
        await repo.commitAll('adds safe.txt too');

        expect(await repo.gitOk(['rev-list', '--count', 'main']), '3');

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult result = await engine
            .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
        expect(result.success, isTrue, reason: result.error ?? '');

        expect(await repo.gitOk(['rev-list', '--count', 'main']), '2',
            reason: 'the fully-pruned commit must be elided entirely, not '
                'kept as a hollow shell');
        expect(await repo.gitOk(['rev-parse', 'main^']), root,
            reason: 'the child of a fully-pruned commit must graft '
                'directly onto the grandparent, with the EXACT original '
                'grandparent sha');
        expect(await repo.gitOk(['ls-tree', 'main', '--name-only']),
            'safe.txt');
        expect(
            (await repo.git(['show', 'main:secret.txt'])).exitCode, isNot(0));
        expect(await fsckClean(repo), isTrue);
      } finally {
        await repo.dispose();
      }
    });

  });

  // ---------------------------------------------------------------------
  // Root-commit grafting and verifyPurge scope: two contracts that were
  // regressions in earlier revisions, now pinned as passing behavior.
  // ---------------------------------------------------------------------
  group('root-commit purge and verifyPurge scope contracts', () {
    test(
      'a fully-pruned commit that is the graph root grafts onto a '
      'synthetic empty-tree commit using the real git empty-tree sha',
      () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'orphan_prune_bug');
        try {
          await repo.gitOk(['checkout', '--orphan', 'orphan-secret']);
          await repo.writeFile('secret.txt', 'orphan secret\n');
          final String orphanCommit =
              await repo.commitAll('orphan: secret only');
          expect(
              await repo.gitOk(['rev-list', '--count', 'orphan-secret']),
              '1');

          await repo.gitOk(['checkout', 'main']);

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          // The "0-parent" branch of _executeInner builds a commit-tree on
          // the well-known empty-tree sha: the secret-only root commit must
          // be replaced by a synthetic empty-tree commit, not left as-is.
          final String newTip =
              await repo.gitOk(['rev-parse', 'orphan-secret']);
          expect(newTip, isNot(orphanCommit),
              reason: 'the secret-only root commit must be replaced by a '
                  'synthetic commit on the real empty-tree sha '
                  '($_kEmptyTreeSha), not left in place');
          expect(await repo.gitOk(['rev-parse', 'orphan-secret^{tree}']),
              _kEmptyTreeSha);
          expect((await repo.git(['rev-parse', 'orphan-secret^'])).exitCode,
              isNot(0),
              reason:
                  'the synthetic root commit must still have zero parents');

          final String reachable =
              await repo.gitOk(['rev-list', '--branches', '--tags']);
          expect(reachable, isNot(contains(orphanCommit)),
              reason: 'the original secret-bearing commit must not remain '
                  'reachable from any production ref after the purge');
        } finally {
          await repo.dispose();
        }
      },
    );

    test(
      'verifyPurge reports true after a fully successful purge, unaffected '
      "by the surgery's own backup refs which deliberately still hold "
      'pre-purge history for rollback',
      () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'verify_purge_bug');
        try {
          await repo.writeFile('safe.txt', 'v1\n');
          await repo.writeFile('secret.txt', 'TOP SECRET\n');
          await repo.commitAll('add secret');
          await repo.writeFile('safe.txt', 'v2\n');
          await repo.commitAll('advance safe.txt');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          // Sanity, independent of verifyPurge: the purge really did fully
          // succeed on every production ref.
          expect(
              await purgedAccordingToPlumbing(
                  repo, <String>{'secret.txt'}),
              isTrue,
              reason: 'sanity check — if THIS is false the purge itself '
                  'is broken, which is a different (and worse) bug');

          // The documented contract ("Verify no trace of target paths
          // remains in history.") must hold.
          final bool verified =
              await engine.verifyPurge(<String>{'secret.txt'});
          expect(verified, isTrue,
              reason: 'verifyPurge scans --branches --tags, not --all, so '
                  "the surgery's own refs/manifold-surgery-backup/<ts>/... "
                  'refs (which still point at pre-purge history for '
                  'rollback) must not make it report traces remaining');
        } finally {
          await repo.dispose();
        }
      },
    );
  });

  // ---------------------------------------------------------------------
  // Fuzz: rollback exactness + purge completeness + validity, universally.
  // ---------------------------------------------------------------------
  group('fuzz: rollback exactness + purge completeness + validity hold '
      'universally', () {
    final int seedCount = 5 * fuzzScale();
    for (int i = 0; i < seedCount; i++) {
      final int seed = 7000 + i * 131;
      test('seed $seed', () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'surgery_fuzz_$seed');
        try {
          final List<RepoOp> ops = genRepoOpSequence(seed, maxOps: 24);
          final List<RepoOpResult> results = <RepoOpResult>[];
          for (final RepoOp op in ops) {
            results.add(await applyOp(repo, op));
          }
          final String repro = 'seed=$seed\nops:\n${ops.join('\n')}\n'
              'results:\n${results.join('\n')}';

          // Force a clean, deterministic starting point: whether the
          // fuzzed sequence left a dirty tree (an in-progress merge, an
          // unpopped stash, ...) is the FUZZER's business, not this
          // property's — execute() legitimately refuses a dirty tree.
          await repo.git(['checkout', '-f', 'main']);
          await repo.git(['reset', '--hard', 'main']);
          await repo.git(['clean', '-fdx']);
          await repo.git(['stash', 'clear']);

          expect(await repo.isClean(), isTrue,
              reason: 'harness failed to reach a clean state\n$repro');
          expect(await fsckClean(repo), isTrue,
              reason: 'repo already corrupt before surgery\n$repro');

          // Pick a real target: any path ever touched by any commit
          // reachable from any ref, discovered independently of the
          // engine (never hardcode the fuzzer's own path pool here).
          final String touchedRaw = await repo
              .gitOk(['log', '--all', '--name-only', '--pretty=format:']);
          final Set<String> touched = touchedRaw
              .split('\n')
              .map((String l) => l.trim())
              .where((String l) => l.isNotEmpty)
              .toSet();
          final Set<String> target =
              touched.isEmpty ? <String>{'never-existed.txt'} : <String>{
            touched.first
          };

          final Map<String, String> beforeRefs =
              await productionRefSnapshot(repo);

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result =
              await engine.execute(target, (SurgeryProgress p) {});

          expect(result.success, isTrue,
              reason: 'target=$target error=${result.error}\n$repro');

          expect(await purgedAccordingToPlumbing(repo, target), isTrue,
              reason: 'purge incomplete for target=$target\n$repro');
          expect(await fsckClean(repo), isTrue,
              reason: 'fsck failed after surgery for target=$target\n$repro');

          await engine.rollback(result.backupPrefix);

          final Map<String, String> afterRefs =
              await productionRefSnapshot(repo);
          expect(afterRefs, equals(beforeRefs),
              reason: 'rollback was not exact for target=$target\n$repro');
          expect(await fsckClean(repo), isTrue,
              reason:
                  'fsck failed after rollback for target=$target\n$repro');
          expect(await repo.head(), isNotNull,
              reason: 'HEAD did not resolve after rollback\n$repro');
        } finally {
          await repo.dispose();
        }
      });
    }
  });

  // ---------------------------------------------------------------------
  // Scope of what execute()/verifyPurge check: HEAD (including a detached
  // HEAD), refs/heads/*, and refs/tags/*. Out of scope by documented
  // design: the surgery's own backup refs, refs/stash, and refs/remotes/*
  // (a remote purge needs a server-side purge plus re-fetch/re-clone).
  // ---------------------------------------------------------------------
  group('detached HEAD & verifyPurge scope', () {
    test(
      'a detached, unreachable HEAD no longer keeps its target-bearing '
      'commit checked out after execute(), and verifyPurge does not '
      'falsely report success',
      () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'detached_head_root_hole');
        try {
          await repo.writeFile('safe.txt', 'safe v1\n');
          await repo.commitAll('add safe.txt on main');

          final String secretSha = await buildUnreachableDetachedHead(
              repo, 'secret.txt', 'TOP SECRET — unreachable\n');

          // ---- precondition, proven via independent git plumbing ----
          await assertDetachedAndUnreachable(repo, secretSha);
          expect(await pathExistsAtHead(repo, 'secret.txt'), isTrue,
              reason: 'precondition: secret.txt must be present in the '
                  'currently checked-out (detached) commit');
          expect(await repo.isClean(), isTrue,
              reason: 'precondition: execute() requires a clean working '
                  'tree to even start');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          final bool verifyResult =
              await engine.verifyPurge(<String>{'secret.txt'});
          final bool headStillHasSecret =
              await pathExistsAtHead(repo, 'secret.txt');

          // ---- THE ROOT SAFETY LAW: it must never be the case that
          // verifyPurge reports success while the live checkout is still
          // contaminated ----
          expect(verifyResult && headStillHasSecret, isFalse,
              reason: 'execute() folds HEAD into its `git rev-list '
                  '--glob=refs/heads/* --glob=refs/tags/* HEAD` rewrite '
                  'set, so a commit reachable only via detached HEAD is '
                  'rewritten and remapped like any other; verifyPurge '
                  'scans `HEAD` alongside `--branches --tags`, so it '
                  'cannot report success while HEAD is still contaminated '
                  'either way');
        } finally {
          await repo.dispose();
        }
      },
    );

    group('verifyPurge scope matrix', () {
      test(
          'branch-only (control): P purged from the one branch that had '
          'it — verifyPurge true, HEAD:P gone', () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'scope_branch_only');
        try {
          await repo.writeFile('safe.txt', 'v1\n');
          await repo.writeFile('secret.txt', 'branch-only secret\n');
          await repo.commitAll('add safe+secret on main');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue);
          expect(await pathExistsAtHead(repo, 'secret.txt'), isFalse);
        } finally {
          await repo.dispose();
        }
      });

      test(
          'backup-only (control, guards the backup-ref exclusion): P '
          'survives only in refs/manifold-surgery-backup/*, and '
          'verifyPurge correctly still reports true', () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'scope_backup_only');
        try {
          await repo.writeFile('safe.txt', 'v1\n');
          await repo.writeFile('secret.txt', 'backed-up secret\n');
          await repo.commitAll('add safe+secret on main');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');
          expect(result.backupPrefix, isNotEmpty);

          // Sanity, independent of the engine: the backup really does
          // still hold secret.txt, or this control proves nothing.
          final List<String> backups =
              await backupRefsUnder(repo, result.backupPrefix);
          expect(backups, isNotEmpty);
          bool backupHasSecret = false;
          for (final String backupRef in backups) {
            final ProcessResult r =
                await repo.git(['cat-file', '-e', '$backupRef:secret.txt']);
            if (r.exitCode == 0) {
              backupHasSecret = true;
              break;
            }
          }
          expect(backupHasSecret, isTrue,
              reason: 'sanity: the backup ref must genuinely still hold '
                  'the pre-purge secret.txt blob');

          expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue,
              reason: "verifyPurge must correctly EXCLUDE the surgery's "
                  'own backup refs (refs/manifold-surgery-backup/*) — '
                  'they are intentionally kept around for rollback, not a '
                  'leak. This guards against a regression of that '
                  'exclusion.');
        } finally {
          await repo.dispose();
        }
      });

      test(
        'detached-HEAD-only (control): P purged from a detached, '
        'unreachable HEAD — verifyPurge true, HEAD:P independently '
        'confirmed gone',
        () async {
          final ScratchRepo repo =
              await ScratchRepo.create(name: 'scope_detached_head_only');
          try {
            await repo.writeFile('safe.txt', 'v1\n');
            await repo.commitAll('add safe.txt on main');
            final String secretSha = await buildUnreachableDetachedHead(
                repo, 'secret.txt', 'detached-only secret\n');
            await assertDetachedAndUnreachable(repo, secretSha);

            final HistorySurgeryEngine engine =
                HistorySurgeryEngine(repo.dir.path);
            final SurgeryResult result = await engine
                .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
            expect(result.success, isTrue, reason: result.error ?? '');

            // HEAD is folded into execute()'s rewrite set, so the detached
            // commit is genuinely rewritten and remapped, leaving nothing
            // for verifyPurge's HEAD scan to catch — confirmed
            // independently of the engine's own self-report, via plumbing.
            expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue,
                reason: 'verifyPurge scans HEAD, and execute() rewrites '
                    'even a detached-only commit, so there is nothing left '
                    'to miss');
            expect(await pathExistsAtHead(repo, 'secret.txt'), isFalse,
                reason: 'independent plumbing check: the detached HEAD '
                    'itself must no longer contain the purged path, not '
                    'just verifyPurge\'s self-report of it');
          } finally {
            await repo.dispose();
          }
        },
      );

      test(
          'stash-only (documented scope — intentionally excluded): P '
          'planted only in a stash entry is invisible to verifyPurge',
          () async {
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'scope_stash_only');
        try {
          await repo.writeFile('safe.txt', 'v1\n');
          await repo.commitAll('add safe.txt on main');

          await repo.writeFile('secret.txt', 'stashed secret\n');
          await repo
              .gitOk(['stash', 'push', '-u', '-m', 'holds secret.txt']);
          expect(await repo.isClean(), isTrue);

          // Independent plumbing: secret.txt really is reachable from the
          // full ref graph (via refs/stash). `--full-history` is required
          // here (not just `--all`) because `stash push -u` stores the
          // untracked file on stash's THIRD parent (the "untracked files"
          // commit) — plain `git log`'s default history simplification
          // prunes that octopus branch entirely and reports nothing even
          // though the blob is genuinely reachable (confirmed independently
          // via `git rev-list --objects refs/stash`, which walks every
          // parent regardless of log's diff-based simplification).
          final String allLog = await repo.gitOk([
            'log', '--all', '--full-history', '--oneline', '--', 'secret.txt'
          ]);
          expect(allLog, isNotEmpty,
              reason: 'precondition: secret.txt must be reachable via '
                  'refs/stash');
          final String stashObjects =
              await repo.gitOk(['rev-list', '--objects', 'refs/stash']);
          final String secretBlob =
              await repo.gitOk(['rev-parse', 'refs/stash^3:secret.txt']);
          expect(stashObjects, contains(secretBlob),
              reason: 'precondition (object-level, immune to log history '
                  'simplification): the stash\'s untracked-files commit '
                  'must really contain the secret.txt blob');
          final String branchTagLog = await repo.gitOk([
            'log', '--branches', '--tags', '--oneline', '--', 'secret.txt'
          ]);
          expect(branchTagLog, isEmpty,
              reason: 'precondition: secret.txt must NOT be reachable '
                  'from any branch or tag');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          // verifyPurge's scope is HEAD + branches + tags — stashes are
          // deliberately not checked (see the dartdoc on verifyPurge): a
          // stash must be dropped separately.
          expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue,
              reason: 'verifyPurge scans HEAD, --branches, and --tags, '
                  'never refs/stash, so a stash entry holding the purged '
                  'path is invisible to it by documented design; callers '
                  'must drop stashes themselves');
        } finally {
          await repo.dispose();
        }
      });

      test(
          'remotes-only (documented scope — intentionally excluded): P '
          'planted only under refs/remotes/* is invisible to verifyPurge',
          () async {
        final ScratchRepo remoteRepo =
            await ScratchRepo.create(name: 'scope_remote_only_origin');
        final ScratchRepo repo =
            await ScratchRepo.create(name: 'scope_remote_only_local');
        try {
          await remoteRepo.writeFile('secret.txt', 'remote-only secret\n');
          await remoteRepo.commitAll('remote: add secret.txt');

          await repo.writeFile('safe.txt', 'v1\n');
          await repo.commitAll('add safe.txt on main');
          await repo
              .gitOk(['remote', 'add', 'origin', remoteRepo.dir.path]);
          await repo.gitOk(['fetch', 'origin']);

          // Independent plumbing: secret.txt is reachable via
          // refs/remotes/origin/main, but from no local branch or tag.
          final String remoteLog = await repo.gitOk([
            'log',
            '--oneline',
            'refs/remotes/origin/main',
            '--',
            'secret.txt',
          ]);
          expect(remoteLog, isNotEmpty,
              reason: 'precondition: secret.txt must be reachable via '
                  'refs/remotes/origin/main');
          final String branchTagLog = await repo.gitOk([
            'log', '--branches', '--tags', '--oneline', '--', 'secret.txt'
          ]);
          expect(branchTagLog, isEmpty,
              reason: 'precondition: secret.txt must NOT be reachable '
                  'from any local branch or tag');

          final HistorySurgeryEngine engine =
              HistorySurgeryEngine(repo.dir.path);
          final SurgeryResult result = await engine
              .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
          expect(result.success, isTrue, reason: result.error ?? '');

          expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue,
              reason: 'verifyPurge never queries refs/remotes/*, so a '
                  'remote-tracking ref holding the purged path is '
                  'invisible to it by documented design; a real purge of a '
                  'shared remote needs a server-side purge plus a '
                  're-fetch/re-clone by every collaborator');
        } finally {
          await repo.dispose();
          await remoteRepo.dispose();
        }
      });
    });

    // verifyPurge's documented scope is HEAD (including a detached HEAD)
    // plus all branches and tags, deliberately excluding its own backup
    // refs, refs/stash, and refs/remotes/*. This test pins all three
    // exclusions side by side against one purge.
    test(
        'verifyPurge==true while P is still concretely reachable via a '
        'backup ref, a stash entry, AND a remote-tracking ref — HEAD, '
        'branches, and tags are the only things checked',
        () async {
      final ScratchRepo remoteRepo =
          await ScratchRepo.create(name: 'doc_scope_origin');
      final ScratchRepo repo =
          await ScratchRepo.create(name: 'doc_scope_local');
      try {
        // The remote holds secret.txt too, never merged locally.
        await remoteRepo.writeFile('secret.txt', 'remote copy\n');
        await remoteRepo.commitAll('remote: add secret.txt');
        await repo.gitOk(['remote', 'add', 'origin', remoteRepo.dir.path]);

        // Local main gets secret.txt, which is then purged for real.
        await repo.writeFile('safe.txt', 'v1\n');
        await repo.writeFile('secret.txt', 'local copy\n');
        await repo.commitAll('local: add safe+secret');
        await repo.gitOk(['fetch', 'origin']);

        // A stash entry holds a separate edit to it too.
        await repo.writeFile('secret.txt', 'stashed edit\n');
        await repo.gitOk(['stash', 'push', '-m', 'holds a secret edit']);
        expect(await repo.isClean(), isTrue);

        final HistorySurgeryEngine engine =
            HistorySurgeryEngine(repo.dir.path);
        final SurgeryResult result = await engine
            .execute(<String>{'secret.txt'}, (SurgeryProgress p) {});
        expect(result.success, isTrue, reason: result.error ?? '');

        // ---- independent plumbing: P really is still reachable via
        // three separate non-branch/tag routes ----
        bool backupHasSecret = false;
        for (final String backupRef
            in await backupRefsUnder(repo, result.backupPrefix)) {
          final ProcessResult r =
              await repo.git(['cat-file', '-e', '$backupRef:secret.txt']);
          if (r.exitCode == 0) {
            backupHasSecret = true;
            break;
          }
        }
        expect(backupHasSecret, isTrue,
            reason: 'sanity: backup ref must genuinely still hold '
                'secret.txt');

        final String stashLog = await repo
            .gitOk(['log', '--oneline', 'refs/stash', '--', 'secret.txt']);
        expect(stashLog, isNotEmpty,
            reason: 'sanity: stash entry must genuinely still hold '
                'secret.txt');

        final String remoteLog = await repo.gitOk([
          'log',
          '--oneline',
          'refs/remotes/origin/main',
          '--',
          'secret.txt',
        ]);
        expect(remoteLog, isNotEmpty,
            reason: 'sanity: remote-tracking ref must genuinely still '
                'hold secret.txt');

        // ---- and yet, per the documented scope ----
        expect(await engine.verifyPurge(<String>{'secret.txt'}), isTrue,
            reason: 'verifyPurge checks HEAD plus all branches and tags in '
                'the local reachable history. secret.txt is concretely '
                'reachable via a backup ref, a stash entry, and a '
                'remote-tracking ref, and verifyPurge still reports true — '
                'backups are intentionally excluded (see the backup-only '
                'control above, and rollback()); stash entries must be '
                'dropped separately; remote-tracking refs need a '
                'server-side purge plus a re-fetch/re-clone by every '
                'collaborator');
      } finally {
        await repo.dispose();
        await remoteRepo.dispose();
      }
    });
  });
}
