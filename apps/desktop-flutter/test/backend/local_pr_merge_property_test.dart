// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/backend/merge_session.dart';

/// Randomized property-based tests for the local-PR merge engine
/// ([mergeBranchIntoBase]). Each property is exercised over a fixed list of
/// literal seeds so any failure reproduces exactly from the seed alone; the
/// generated topology parameters are attached to every assertion via `reason:`
/// and echoed with [printOnFailure], so a red build is diagnosable without a
/// rerun.
///
/// GROUND TRUTH is always an INDEPENDENT git computation — a throwaway
/// `git clone` in which a REAL `git merge` (recursive/ort in a working tree)
/// is run — never the engine's own Dart helpers. The engine's landed tree /
/// conflict set is compared against that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixed literal seeds — reproducible. ~10 cases per property.
  const seeds = <int>[1, 2, 3, 5, 8, 13, 21, 34, 55, 89];

  // Every temp root we mint, torn down at the end (Windows-safe: swallow
  // locks, retry). Mirrors the existing suite's cleanup idiom.
  final roots = <Directory>[];

  Future<void> safeDelete(Directory d) async {
    for (var i = 0; i < 4; i++) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  tearDownAll(() async {
    for (final d in roots) {
      await safeDelete(d);
    }
  });

  // ---- raw git plumbing (ground truth speaks only to the git binary) ----
  Future<ProcessResult> git(String at, List<String> args) => Process.run(
        'git',
        args,
        workingDirectory: at,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

  Future<String> out(String at, List<String> args) async =>
      (await git(at, args)).stdout.toString().trim();

  Future<void> configure(String at) async {
    await git(at, ['config', 'user.email', 'a@b.c']);
    await git(at, ['config', 'user.name', 'test']);
    await git(at, ['config', 'core.autocrlf', 'false']);
    await git(at, ['config', 'commit.gpgsign', 'false']);
    await git(at, ['config', 'merge.conflictStyle', 'merge']);
  }

  String sep(String repo, String rel) =>
      '$repo${Platform.pathSeparator}$rel';

  Future<void> writeLines(String repo, String f, List<String> lines) =>
      File(sep(repo, f)).writeAsString('${lines.join('\n')}\n');

  Future<String> tip(String repo, String ref) => out(repo, ['rev-parse', ref]);

  Future<int> parentCount(String repo, String ref) async {
    final r = await out(repo, ['rev-list', '--parents', '-n', '1', ref]);
    return r.split(' ').length - 1;
  }

  Future<bool> isAncestor(String repo, String a, String b) async =>
      (await git(repo, ['merge-base', '--is-ancestor', a, b])).exitCode == 0;

  Future<Map<String, String>> refs(String repo) async {
    final r =
        await out(repo, ['for-each-ref', '--format=%(refname) %(objectname)']);
    final m = <String, String>{};
    for (final line in r.split('\n')) {
      if (line.trim().isEmpty) continue;
      final i = line.indexOf(' ');
      if (i < 0) continue;
      m[line.substring(0, i)] = line.substring(i + 1).trim();
    }
    return m;
  }

  Future<int> reflogCount(String repo, String ref) async {
    final r = await git(repo, ['reflog', 'show', '--format=%H', ref]);
    if (r.exitCode != 0) return 0;
    return (r.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length;
  }

  /// Byte-exact snapshot of a worktree (path -> base64 of file bytes),
  /// skipping the `.git` dir/file. Used to prove a worktree was untouched.
  Future<Map<String, String>> snapshot(String dir) async {
    final m = <String, String>{};
    final base = Directory(dir);
    if (!await base.exists()) return m;
    await for (final e in base.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.substring(dir.length);
      final segs = rel.split(Platform.pathSeparator);
      if (segs.contains('.git')) continue;
      m[rel] = base64.encode(await e.readAsBytes());
    }
    return m;
  }

  // ---- topology generator -------------------------------------------------
  // Files carry 30 lines. Feature edits the TOP zone (lines 1..8); base edits
  // the BOTTOM zone (lines 22..29) — disjoint, so overlapping FILES never
  // conflict on content. A conflict is forced only when [conflict] is set, by
  // both sides rewriting the SAME middle line (15) of a shared file to
  // different text. Line counts stay fixed (replace-in-place), keeping the
  // zones disjoint no matter the random draw.

  Future<({String repo, String diag})> build(
    int seed, {
    required bool conflict,
  }) async {
    final rng = Random(seed);
    final nFiles = 5 + rng.nextInt(8); // 5..12
    final forkDepth = 3 + rng.nextInt(4); // 3..6 pre-fork commits on main
    final featCount = 3 + rng.nextInt(4); // 3..6 feature commits
    final baseAdv =
        conflict ? 1 + rng.nextInt(5) : rng.nextInt(6); // 0..5 (>=1 if conflict)

    final root = await Directory.systemTemp.createTemp('gdpu_prop_');
    roots.add(root);
    final repo = sep(root.path, 'repo');
    await Directory(repo).create(recursive: true);
    await git(repo, ['init', '-q', '-b', 'main']);
    await configure(repo);

    final files = [for (var i = 0; i < nFiles; i++) 'f$i.txt'];
    final content = <String, List<String>>{
      for (final f in files) f: [for (var i = 0; i < 30; i++) '$f line $i v0'],
    };
    for (final f in files) {
      await writeLines(repo, f, content[f]!);
    }
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'root']);

    // Pre-fork history on main (middle-zone edits — these land in the shared
    // merge-base, so they never drive a conflict). Randomizes the fork point.
    for (var c = 0; c < forkDepth; c++) {
      final f = files[rng.nextInt(nFiles)];
      content[f]![14] = '$f line 14 prefork$c';
      await writeLines(repo, f, content[f]!);
      await git(repo, ['commit', '-qam', 'prefork $c']);
    }

    await git(repo, ['branch', 'base']);
    await git(repo, ['checkout', '-q', '-b', 'feature']);

    // Diverge feature/base from the shared fork-point content.
    final feat = {for (final f in files) f: [...content[f]!]};
    final baseC = {for (final f in files) f: [...content[f]!]};
    final cf = files[0]; // guaranteed-shared file for a forced conflict

    final featTouched = <String>{};
    for (var c = 0; c < featCount; c++) {
      final k = 1 + rng.nextInt(3);
      for (var j = 0; j < k; j++) {
        final f = files[rng.nextInt(nFiles)];
        final line = 1 + rng.nextInt(8); // top zone
        feat[f]![line] = '$f line $line feat$c';
        featTouched.add(f);
      }
      for (final f in files) {
        await writeLines(repo, f, feat[f]!);
      }
      await git(repo, ['commit', '-qam', 'feat $c']);
    }
    if (conflict) {
      feat[cf]![15] = '$cf line 15 FEATURE_CONFLICT';
      await writeLines(repo, cf, feat[cf]!);
      await git(repo, ['commit', '-qam', 'feat conflict']);
      featTouched.add(cf);
    }

    await git(repo, ['checkout', '-q', 'base']);
    final baseTouched = <String>{};
    for (var c = 0; c < baseAdv; c++) {
      final k = 1 + rng.nextInt(3);
      for (var j = 0; j < k; j++) {
        final f = files[rng.nextInt(nFiles)];
        final line = 22 + rng.nextInt(8); // bottom zone
        baseC[f]![line] = '$f line $line base$c';
        baseTouched.add(f);
      }
      for (final f in files) {
        await writeLines(repo, f, baseC[f]!);
      }
      await git(repo, ['commit', '-qam', 'base $c']);
    }
    if (conflict) {
      baseC[cf]![15] = '$cf line 15 BASE_CONFLICT';
      await writeLines(repo, cf, baseC[cf]!);
      await git(repo, ['commit', '-qam', 'base conflict']);
      baseTouched.add(cf);
    }

    await git(repo, ['checkout', '-q', 'main']);

    final total = 1 + forkDepth + featCount + baseAdv + (conflict ? 2 : 0);
    final diag = 'seed=$seed conflict=$conflict nFiles=$nFiles '
        'forkDepth=$forkDepth featCount=$featCount baseAdv=$baseAdv '
        'commits=$total featTouched=${featTouched.toList()..sort()} '
        'baseTouched=${baseTouched.toList()..sort()}';
    return (repo: repo, diag: diag);
  }

  /// A fresh, independently-mutable copy of a built topology with local
  /// `main`/`base`/`feature` branches, HEAD on `main`, base & feature checked
  /// out nowhere. A `--local` clone is near-instant (object hardlinks) and
  /// hands each engine run pristine state.
  Future<String> freshCopy(String src, String tag) async {
    final holder = File(src).parent; // .../gdpu_prop_X/repo -> gdpu_prop_X
    final dst = sep(holder.path, 'copy_$tag');
    // Pin autocrlf at clone time: the machine's GLOBAL core.autocrlf governs
    // the initial checkout, so on Windows a later `config` flip would leave
    // every file spuriously "modified" (CRLF worktree vs LF index).
    await git(holder.path,
        ['clone', '-q', '--local', '-c', 'core.autocrlf=false', src, dst]);
    await configure(dst);
    await git(dst, ['branch', '-f', 'base', 'origin/base']);
    await git(dst, ['branch', '-f', 'feature', 'origin/feature']);
    await git(dst, ['checkout', '-q', 'main']);
    return dst;
  }

  /// INDEPENDENT ground truth: clone the source, run a REAL `git merge` of
  /// feature into base in a working tree, and report the resulting tree SHA
  /// (clean) or the conflicted-path set (`diff --diff-filter=U`). This is a
  /// different git mechanism than the engine's `merge-tree`, so it can't be
  /// the engine grading its own homework.
  Future<({bool clean, String? tree, Set<String> conflicts})> groundTruth(
      String src, String tag) async {
    final holder = File(src).parent;
    final dst = sep(holder.path, 'gt_$tag');
    await git(holder.path,
        ['clone', '-q', '--local', '-c', 'core.autocrlf=false', src, dst]);
    await configure(dst);
    await git(dst, ['checkout', '-q', '-B', 'base', 'origin/base']);
    final mr = await git(dst, ['merge', '--no-ff', '--no-edit', 'origin/feature']);
    if (mr.exitCode == 0) {
      final tree = await out(dst, ['rev-parse', 'HEAD^{tree}']);
      return (clean: true, tree: tree, conflicts: <String>{});
    }
    final conf = await out(dst, ['diff', '--name-only', '--diff-filter=U']);
    final set = conf
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    return (clean: false, tree: null, conflicts: set);
  }

  // =======================================================================
  // PROPERTY 1 — correctness against git ground truth + ref/worktree honesty
  // =======================================================================
  test('property: clean merges match git ground truth; only base moves',
      () async {
    for (final seed in seeds) {
      final t = await build(seed, conflict: false);
      final repo = t.repo;
      printOnFailure('P1 ${t.diag}');
      final gt = await groundTruth(repo, 's${seed}gt');
      expect(gt.clean, isTrue,
          reason: 'P1 ${t.diag} :: disjoint-zone topology must merge clean');
      final gtTree = gt.tree!;

      // ---- zero-checkout mergeCommit: pure ref-level advance ----
      final zc = await freshCopy(repo, 's${seed}zcmc');
      final refsBefore = await refs(zc);
      final rlBefore = await reflogCount(zc, 'base');
      final wtBefore = await snapshot(zc); // main worktree, must not be touched
      final r1 = await mergeBranchIntoBase(
        repoPath: zc,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.mergeCommit,
      );
      expect(r1.outcome, isA<MergeClean>(), reason: 'P1 ${t.diag} :: zc mergeCommit');
      expect(r1.conflictWorktree, isNull, reason: 'P1 ${t.diag} :: zc no wt');
      final mergeTree = await tip(zc, 'base^{tree}');
      expect(mergeTree, gtTree,
          reason: 'P1 ${t.diag} :: merge tree must equal git ground truth');
      expect(await parentCount(zc, 'base'), 2,
          reason: 'P1 ${t.diag} :: mergeCommit is two-parent');
      expect(await isAncestor(zc, 'feature', 'base'), isTrue,
          reason: 'P1 ${t.diag} :: feature is an ancestor of base');
      expect(await reflogCount(zc, 'base'), rlBefore + 1,
          reason: 'P1 ${t.diag} :: base reflog moved exactly once');
      final refsAfter = await refs(zc);
      for (final k in {...refsBefore.keys, ...refsAfter.keys}) {
        if (k == 'refs/heads/base') continue;
        expect(refsAfter[k], refsBefore[k],
            reason: 'P1 ${t.diag} :: only base may move, not $k');
      }
      expect(refsAfter['refs/heads/base'], isNot(refsBefore['refs/heads/base']),
          reason: 'P1 ${t.diag} :: base actually advanced');
      expect(await snapshot(zc), wtBefore,
          reason: 'P1 ${t.diag} :: zero-checkout must not touch the worktree');

      // ---- zero-checkout squash: single-parent, same content as merge ----
      final zs = await freshCopy(repo, 's${seed}zcsq');
      final r2 = await mergeBranchIntoBase(
        repoPath: zs,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.squash,
      );
      expect(r2.outcome, isA<MergeClean>(), reason: 'P1 ${t.diag} :: zc squash');
      final squashTree = await tip(zs, 'base^{tree}');
      expect(squashTree, gtTree,
          reason: 'P1 ${t.diag} :: squash tree must equal git ground truth');
      expect(squashTree, mergeTree,
          reason: 'P1 ${t.diag} :: squash content IDENTICAL to mergeCommit');
      expect(await parentCount(zs, 'base'), 1,
          reason: 'P1 ${t.diag} :: squash is single-parent (no merge parent)');

      // ---- worktree-routed mergeCommit: other worktrees untouched ----
      final wr = await freshCopy(repo, 's${seed}wrmc');
      final wtBase = sep(File(wr).parent.path, 'wtb_s$seed');
      await git(wr, ['worktree', 'add', '-q', wtBase, 'base']);
      final mainWtBefore = await snapshot(wr); // NOT the target worktree
      final wrRefsBefore = await refs(wr);
      final r3 = await mergeBranchIntoBase(
        repoPath: wr,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.mergeCommit,
      );
      expect(r3.outcome, isA<MergeClean>(),
          reason: 'P1 ${t.diag} :: worktree-routed mergeCommit');
      expect(await tip(wr, 'base^{tree}'), gtTree,
          reason: 'P1 ${t.diag} :: routed merge tree equals ground truth');
      expect(await parentCount(wr, 'base'), 2,
          reason: 'P1 ${t.diag} :: routed mergeCommit two-parent');
      final wrRefsAfter = await refs(wr);
      for (final k in {...wrRefsBefore.keys, ...wrRefsAfter.keys}) {
        if (k == 'refs/heads/base') continue;
        expect(wrRefsAfter[k], wrRefsBefore[k],
            reason: 'P1 ${t.diag} :: routed merge moved a foreign ref $k');
      }
      expect(await snapshot(wr), mainWtBefore,
          reason: 'P1 ${t.diag} :: routed merge touched a foreign worktree');
      await git(wr, ['worktree', 'remove', '--force', wtBase]);

      // ---- rebase: needs both refs in worktrees; content still matches ----
      // (rebase rewrites `feature` and advances `base`, so the exclusive-
      //  ref-move invariant does NOT apply — only main must stay put.)
      final rb = await freshCopy(repo, 's${seed}rb');
      final rbBase = sep(File(rb).parent.path, 'rbb_s$seed');
      final rbFeat = sep(File(rb).parent.path, 'rbf_s$seed');
      await git(rb, ['worktree', 'add', '-q', rbBase, 'base']);
      await git(rb, ['worktree', 'add', '-q', rbFeat, 'feature']);
      final mainTipBefore = await tip(rb, 'main');
      final r4 = await mergeBranchIntoBase(
        repoPath: rb,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.rebase,
      );
      expect(r4.outcome, isA<MergeClean>(), reason: 'P1 ${t.diag} :: rebase');
      expect(await tip(rb, 'base^{tree}'), gtTree,
          reason: 'P1 ${t.diag} :: rebased base content equals ground truth');
      expect(await isAncestor(rb, 'feature', 'base'), isTrue,
          reason: 'P1 ${t.diag} :: rebase leaves feature an ancestor of base');
      expect(await tip(rb, 'main'), mainTipBefore,
          reason: 'P1 ${t.diag} :: rebase must not move main');
      await git(rb, ['worktree', 'remove', '--force', rbFeat]);
      await git(rb, ['worktree', 'remove', '--force', rbBase]);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  // =======================================================================
  // PROPERTY 2 — conflict honesty
  // =======================================================================
  test('property: conflicts match git ground truth; refs frozen; tree pristine',
      () async {
    for (final seed in seeds) {
      final t = await build(seed, conflict: true);
      final repo = t.repo;
      printOnFailure('P2 ${t.diag}');
      final gt = await groundTruth(repo, 's${seed}gtc');
      expect(gt.clean, isFalse,
          reason: 'P2 ${t.diag} :: forced same-line edit must conflict');
      final gtConflicts = gt.conflicts;

      // ---- zero-checkout: every ref frozen, every worktree byte-identical ----
      final zc = await freshCopy(repo, 's${seed}zcx');
      final refsBefore = await refs(zc);
      final wtBefore = await snapshot(zc);
      final r1 = await mergeBranchIntoBase(
        repoPath: zc,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.mergeCommit,
      );
      expect(r1.outcome, isA<MergeConflicted>(),
          reason: 'P2 ${t.diag} :: zc conflict must be reported');
      expect((r1.outcome as MergeConflicted).paths.toSet(), gtConflicts,
          reason: 'P2 ${t.diag} :: reported conflict set == git ground truth');
      expect(r1.conflictWorktree, isNull,
          reason: 'P2 ${t.diag} :: ref-level conflict names no worktree');
      expect(await refs(zc), refsBefore,
          reason: 'P2 ${t.diag} :: no ref may move on a ref-level conflict');
      expect(await snapshot(zc), wtBefore,
          reason: 'P2 ${t.diag} :: zero-checkout conflict left a worktree byte');

      // ---- worktree-routed: same conflict set, base ref frozen ----
      final wr = await freshCopy(repo, 's${seed}wrx');
      final wtBase = sep(File(wr).parent.path, 'wtbx_s$seed');
      await git(wr, ['worktree', 'add', '-q', wtBase, 'base']);
      final baseBefore = await tip(wr, 'base');
      final foreignBefore = await snapshot(wr); // the non-target worktree
      final r2 = await mergeBranchIntoBase(
        repoPath: wr,
        branch: 'feature',
        baseRef: 'base',
        method: BranchMergeMethod.mergeCommit,
      );
      expect(r2.outcome, isA<MergeConflicted>(),
          reason: 'P2 ${t.diag} :: routed conflict must be reported');
      expect((r2.outcome as MergeConflicted).paths.toSet(), gtConflicts,
          reason: 'P2 ${t.diag} :: routed conflict set == git ground truth');
      // The engine reports git's canonical worktree path (long name, forward
      // slashes); the local string is the systemTemp short-name form — compare
      // canonicalized so a valid path never fails on Windows path cosmetics.
      expect(r2.conflictWorktree, isNotNull,
          reason: 'P2 ${t.diag} :: routed conflict must name a worktree');
      expect(Directory(r2.conflictWorktree!).resolveSymbolicLinksSync(),
          Directory(wtBase).resolveSymbolicLinksSync(),
          reason: 'P2 ${t.diag} :: routed conflict names its own worktree');
      expect(await tip(wr, 'base'), baseBefore,
          reason: 'P2 ${t.diag} :: base ref must not move on conflict');
      expect(await snapshot(wr), foreignBefore,
          reason: 'P2 ${t.diag} :: routed conflict touched a foreign worktree');
      await git(wtBase, ['merge', '--abort']);
      await git(wr, ['worktree', 'remove', '--force', wtBase]);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  // Pinned minimized regression for the merge-tree parse bug the property
  // above uncovered. `git merge-tree --write-tree --name-only` prints the
  // conflicted file NAMES, then a blank line, then a prose "informational
  // messages" block ("Auto-merging conflict.txt", "CONFLICT (content): …",
  // "Auto-merging clean.txt"). The zero-checkout path used to slurp EVERY
  // non-empty line after the tree OID as a "path", so those message lines
  // leaked into MergeConflicted.paths. The minimal trigger: one file that
  // conflicts on both sides PLUS one file that auto-merges cleanly (its
  // "Auto-merging" line is what used to be misreported as a conflict path).
  test('regression: ref-level conflict list is EXACTLY the conflicted files',
      () async {
    final root = await Directory.systemTemp.createTemp('gdpu_mtparse_');
    roots.add(root);
    final repo = sep(root.path, 'repo');
    await Directory(repo).create(recursive: true);
    await git(repo, ['init', '-q', '-b', 'main']);
    await configure(repo);
    await writeLines(
        repo, 'conflict.txt', [for (var i = 0; i < 12; i++) 'conflict $i v0']);
    await writeLines(
        repo, 'clean.txt', [for (var i = 0; i < 12; i++) 'clean $i v0']);
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'root']);
    await git(repo, ['branch', 'base']);
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await writeLines(repo, 'conflict.txt',
        [for (var i = 0; i < 12; i++) i == 5 ? 'conflict 5 FEATURE' : 'conflict $i v0']);
    await writeLines(repo, 'clean.txt',
        [for (var i = 0; i < 12; i++) i == 1 ? 'clean 1 feat' : 'clean $i v0']);
    await git(repo, ['commit', '-qam', 'feature']);
    await git(repo, ['checkout', '-q', 'base']);
    await writeLines(repo, 'conflict.txt',
        [for (var i = 0; i < 12; i++) i == 5 ? 'conflict 5 BASE' : 'conflict $i v0']);
    await writeLines(repo, 'clean.txt',
        [for (var i = 0; i < 12; i++) i == 10 ? 'clean 10 base' : 'clean $i v0']);
    await git(repo, ['commit', '-qam', 'base']);
    await git(repo, ['checkout', '-q', 'main']);

    final r = await mergeBranchIntoBase(
      repoPath: repo,
      branch: 'feature',
      baseRef: 'base',
      method: BranchMergeMethod.mergeCommit,
    );
    expect(r.outcome, isA<MergeConflicted>());
    // EXACTLY {conflict.txt} — no "Auto-merging …"/"CONFLICT (content): …"
    // prose, and NOT clean.txt (which auto-merged).
    expect((r.outcome as MergeConflicted).paths, ['conflict.txt']);
    expect(r.conflictWorktree, isNull);
  });

  // =======================================================================
  // PROPERTY 3 — dirty-gate matrix (documented contract, not guessed)
  // =======================================================================
  // Fixture: `existing.txt` is tracked; feature ADDS `incoming.txt` and edits
  // existing.txt's bottom zone (a clean merge that introduces a new file).
  Future<String> buildGate() async {
    final root = await Directory.systemTemp.createTemp('gdpu_gate_');
    roots.add(root);
    final repo = sep(root.path, 'repo');
    await Directory(repo).create(recursive: true);
    await git(repo, ['init', '-q', '-b', 'main']);
    await configure(repo);
    await writeLines(
        repo, 'existing.txt', [for (var i = 0; i < 30; i++) 'existing $i v0']);
    await writeLines(repo, 'README.md', ['readme v0']);
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'root']);
    await git(repo, ['branch', 'base']);
    await git(repo, ['checkout', '-q', '-b', 'feature']);
    await writeLines(repo, 'incoming.txt', ['incoming payload from feature']);
    await writeLines(repo, 'existing.txt',
        [for (var i = 0; i < 30; i++) i == 27 ? 'existing 27 feat' : 'existing $i v0']);
    await git(repo, ['add', '-A']);
    await git(repo, ['commit', '-qm', 'feature adds incoming']);
    await git(repo, ['checkout', '-q', 'main']);
    return repo;
  }

  test('property: dirty-gate matrix follows the documented -uno contract',
      () async {
    // ---- worktree-routed cells: gate reads the base worktree ----
    // Cell (tracked modification): a modified tracked file blocks.
    {
      final repo = await buildGate();
      final wt = sep(File(repo).parent.path, 'wt_trk');
      await git(repo, ['worktree', 'add', '-q', wt, 'base']);
      await writeLines(wt, 'existing.txt', ['locally hand-edited']);
      final r = await mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit);
      expect(r.outcome, isA<MergeBlockedByLocalChanges>(),
          reason: 'gate/wt tracked-mod must block');
      expect((r.outcome as MergeBlockedByLocalChanges).paths,
          contains('existing.txt'),
          reason: 'gate/wt tracked-mod names the file');
      await git(repo, ['worktree', 'remove', '--force', wt]);
    }
    // Cell (untracked, non-colliding): rides along, merge is clean.
    {
      final repo = await buildGate();
      final wt = sep(File(repo).parent.path, 'wt_unt');
      await git(repo, ['worktree', 'add', '-q', wt, 'base']);
      await writeLines(wt, 'scratch.tmp', ['junk']);
      final r = await mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit);
      expect(r.outcome, isA<MergeClean>(),
          reason: 'gate/wt untracked-noncolliding must NOT block (-uno)');
      expect(await File(sep(wt, 'scratch.tmp')).exists(), isTrue,
          reason: 'gate/wt scratch file rode along');
      await git(repo, ['worktree', 'remove', '--force', wt]);
    }
    // Cell (untracked that the merge WOULD overwrite): git refuses → blocked.
    {
      final repo = await buildGate();
      final wt = sep(File(repo).parent.path, 'wt_ovr');
      await git(repo, ['worktree', 'add', '-q', wt, 'base']);
      await writeLines(wt, 'incoming.txt', ['squatter content']);
      final r = await mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit);
      expect(r.outcome, isA<MergeBlockedByLocalChanges>(),
          reason: 'gate/wt untracked-would-overwrite must block');
      expect((r.outcome as MergeBlockedByLocalChanges).paths,
          contains('incoming.txt'),
          reason: 'gate/wt overwrite-collision names the file');
      expect(await File(sep(wt, 'incoming.txt')).readAsString(),
          'squatter content\n',
          reason: 'gate/wt squatter file left intact');
      await git(repo, ['worktree', 'remove', '--force', wt]);
    }
    // Cell (staged change): a staged tracked edit is dirty (xy != '??') → block.
    {
      final repo = await buildGate();
      final wt = sep(File(repo).parent.path, 'wt_stg');
      await git(repo, ['worktree', 'add', '-q', wt, 'base']);
      await writeLines(wt, 'existing.txt', ['staged edit']);
      await git(wt, ['add', 'existing.txt']);
      final r = await mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit);
      expect(r.outcome, isA<MergeBlockedByLocalChanges>(),
          reason: 'gate/wt staged-change must block');
      expect((r.outcome as MergeBlockedByLocalChanges).paths,
          contains('existing.txt'),
          reason: 'gate/wt staged-change names the file');
      await git(repo, ['worktree', 'remove', '--force', wt]);
    }

    // ---- zero-checkout cells: base is checked out NOWHERE, so unrelated
    // worktree dirt is irrelevant and NO worktree byte may change. All four
    // dirt kinds land clean and leave the main worktree byte-identical.
    Future<void> zeroCell(
        String tag, Future<void> Function(String repo) dirty) async {
      final repo = await buildGate(); // main worktree on `main`
      await dirty(repo);
      final before = await snapshot(repo);
      final r = await mergeBranchIntoBase(
          repoPath: repo,
          branch: 'feature',
          baseRef: 'base',
          method: BranchMergeMethod.mergeCommit);
      expect(r.outcome, isA<MergeClean>(),
          reason: 'gate/zc $tag: unrelated dirt must not gate a ref-level merge');
      expect(r.conflictWorktree, isNull, reason: 'gate/zc $tag: no worktree');
      expect(await snapshot(repo), before,
          reason: 'gate/zc $tag: zero-checkout must leave every worktree byte');
      expect(await parentCount(repo, 'base'), 2,
          reason: 'gate/zc $tag: base advanced with a merge commit');
    }

    await zeroCell('tracked-mod',
        (repo) => writeLines(repo, 'existing.txt', ['dirty in main worktree']));
    await zeroCell(
        'untracked-noncolliding', (repo) => writeLines(repo, 'scratch.tmp', ['junk']));
    // The strong claim: even a file that WOULD be overwritten by a checkout is
    // untouched, because the ref-level path never materializes one.
    await zeroCell('untracked-would-overwrite',
        (repo) => writeLines(repo, 'incoming.txt', ['squatter in main worktree']));
    await zeroCell('staged-change', (repo) async {
      await writeLines(repo, 'existing.txt', ['staged in main worktree']);
      await git(repo, ['add', 'existing.txt']);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
