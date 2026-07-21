// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Deterministic DAG-shape builders on top of [ScratchRepo].
//
// `genRepoOpSequence` (scratch_repo.dart) only ever produces a *random walk*
// of ops — it has no way to target a specific, named shape (a criss-cross
// merge, an octopus, an orphan branch, a submodule, ...). Those are exactly
// the shapes real git clients break on, and a random walk finds them by
// accident at best. Every function here instead builds one exact, named DAG
// deterministically, so a test can assert precisely against the shas/refs it
// produced.
//
// Contract for every builder below:
//   - takes a **fresh** [ScratchRepo] (one real commit already exists — the
//     `root` empty commit `ScratchRepo.create()` always seeds — nothing else
//     assumed);
//   - is itself deterministic: commit content/messages never depend on the
//     wall clock or any other non-reproducible input (git commit
//     *timestamps* are fine — nothing here asserts on them);
//   - returns a record of the interesting shas/refs it created;
//   - never leaves the repo in a state `git fsck --full --no-dangling`
//     rejects (call [assertFsckClean] after any of these in a test);
//   - only ever talks to git through [ScratchRepo.git]/[ScratchRepo.gitOk] —
//     never a raw `Process.run`.

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

import 'scratch_repo.dart';

// ---------------------------------------------------------------------------
// Shared assertions / introspection helpers
// ---------------------------------------------------------------------------

/// Runs `git fsck --full --no-dangling` against [r] and fails the current
/// test (via `expect`) if it reports any corruption. [because] is folded
/// into the failure reason to say which builder/step produced the state
/// under test.
Future<void> assertFsckClean(ScratchRepo r, {String? because}) async {
  final result = await r.git(['fsck', '--full', '--no-dangling']);
  expect(
    result.exitCode,
    0,
    reason: 'git fsck --full reported corruption'
        '${because == null ? '' : ' ($because)'}.\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
  );
}

/// The parent shas of [sha], via `git rev-list --parents -n 1 <sha>`
/// (a root commit yields an empty list, a merge commit yields 2+ entries).
///
/// NOTE: the task prose that specified this helper's signature said
/// `Future<String>` but described the result as "parsed into a
/// `List<String>`" in the same sentence — a self-contradiction. The list
/// form is what every caller (including the octopus/diamond assertions)
/// actually needs, so that is what is implemented; flagged here rather than
/// silently picking one reading.
Future<List<String>> parentsOf(ScratchRepo r, String sha) async {
  final out = await r.gitOk(['rev-list', '--parents', '-n', '1', sha]);
  final tokens = out.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  // tokens[0] is `sha` itself; the rest are its parents, in parent order.
  return tokens.skip(1).toList();
}

/// `git merge-base --all a b` — every *best* common ancestor. Returns more
/// than one entry exactly when `a` and `b` were merged criss-cross (see
/// [buildCrissCross]).
Future<List<String>> mergeBases(ScratchRepo r, String a, String b) async {
  final result = await r.git(['merge-base', '--all', a, b]);
  if (result.exitCode != 0) {
    // No common ancestor (e.g. buildOrphanBranch) — `merge-base` exits
    // non-zero with empty stdout. Callers who expect this call [ScratchRepo]
    // directly instead so they can assert the *exit code*; this helper is
    // for the shapes that do have a base.
    return const [];
  }
  final out = result.stdout.toString().trim();
  if (out.isEmpty) return const [];
  return out.split('\n').where((l) => l.trim().isNotEmpty).toList();
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

/// A ── B ── D   (main)
///  \        /
///   ── C ──     (feature)   -- a diamond: one merge, two parents
///
/// `feature` branches off at `A` (not at `B`) — `B` and `C` are the two
/// divergent single commits, `D` is their merge. That is what makes
/// `mergeBase(B, C) == [A]` exactly, per the caller's contract.
Future<({String a, String b, String c, String merge})> buildDiamond(
    ScratchRepo r) async {
  await r.writeFile('diamond.txt', 'a\n');
  final a = await r.commitAll('A');

  await r.gitOk(['branch', 'diamond-feature']);

  await r.writeFile('diamond.txt', 'b\n');
  final b = await r.commitAll('B');

  await r.gitOk(['checkout', 'diamond-feature']);
  await r.writeFile('diamond-feature.txt', 'c\n');
  final c = await r.commitAll('C');

  await r.gitOk(['checkout', 'main']);
  await r.gitOk(['merge', '--no-edit', 'diamond-feature']);
  final merge = (await r.head())!;

  return (a: a, b: b, c: c, merge: merge);
}

/// The classic criss-cross:
///
///        O
///       / \
///     A1    B1
///      \\  //     (each side later merges the OTHER side's ORIGINAL tip,
///       \\//        not the other side's own merge result)
///     leftMerge  rightMerge
///     (A1,B1)    (B1,A1)
///
/// `leftMerge` (on `main`) has parents `[A1, B1]`; `rightMerge` (on
/// `criss-cross-right`) has parents `[B1, A1]`. Neither `A1` nor `B1` is an
/// ancestor of the other, so `mergeBases(leftMerge, rightMerge)` returns
/// BOTH of them — the merge base is genuinely ambiguous. Order matters: if
/// the right side merged `leftMerge` (instead of the bare `A1` sha) the
/// result degenerates to a single, unambiguous base (`leftMerge` itself,
/// since it would then be a direct parent of `rightMerge`) — not a
/// criss-cross at all.
Future<({String leftMerge, String rightMerge})> buildCrissCross(
    ScratchRepo r) async {
  await r.writeFile('cross-base.txt', 'o\n');
  await r.commitAll('O');
  await r.gitOk(['branch', 'criss-cross-right']);

  await r.writeFile('cross-left.txt', 'a1\n');
  final a1 = await r.commitAll('A1');

  await r.gitOk(['checkout', 'criss-cross-right']);
  await r.writeFile('cross-right.txt', 'b1\n');
  await r.commitAll('B1');

  await r.gitOk(['checkout', 'main']);
  await r.gitOk(['merge', '--no-edit', 'criss-cross-right']);
  final leftMerge = (await r.head())!;

  await r.gitOk(['checkout', 'criss-cross-right']);
  // Merge the ORIGINAL `A1` sha, not `main` (which is now `leftMerge`) —
  // merging `leftMerge` here would make it a direct parent of `rightMerge`,
  // collapsing the two candidate bases into one.
  await r.gitOk(['merge', '--no-edit', a1]);
  final rightMerge = (await r.head())!;

  await r.gitOk(['checkout', 'main']);
  return (leftMerge: leftMerge, rightMerge: rightMerge);
}

/// One commit with THREE parents, via `git merge oct-a oct-b` (an octopus
/// merge — only possible because the two side branches touch disjoint files,
/// so the octopus strategy resolves it with no manual step):
///
///        ┌── oct-a
///  base ─┼── oct-b
///        └── mainTip ──▶ octopus (3 parents: mainTip, oct-a, oct-b)
///
/// `main` gets its OWN extra commit (`mainTip`) after branching — without
/// it, `main` sits exactly at `base`, and git's octopus strategy silently
/// fast-forwards onto the first named branch before doing a plain two-way
/// merge with the second, collapsing the result to 2 parents instead of 3
/// (verified empirically: `git merge oct-a oct-b` from an unmodified `base`
/// prints "Fast-forwarding to: oct-a" and drops `base` as an explicit
/// parent entirely). Diverging `main` first makes a fast-forward
/// impossible, forcing a genuine three-way octopus commit.
Future<({String octopus, List<String> parents})> buildOctopus(
    ScratchRepo r) async {
  await r.writeFile('octopus-base.txt', 'base\n');
  await r.commitAll('octopus base');

  await r.gitOk(['branch', 'octopus-a']);
  await r.gitOk(['branch', 'octopus-b']);

  await r.gitOk(['checkout', 'octopus-a']);
  await r.writeFile('octopus-a.txt', 'a\n');
  final aSha = await r.commitAll('octopus A');

  await r.gitOk(['checkout', 'octopus-b']);
  await r.writeFile('octopus-b.txt', 'b\n');
  final bSha = await r.commitAll('octopus B');

  await r.gitOk(['checkout', 'main']);
  await r.writeFile('octopus-main.txt', 'main-only\n');
  final mainTip = await r.commitAll('octopus main advance');

  final mergeResult =
      await r.git(['merge', '--no-edit', 'octopus-a', 'octopus-b']);
  if (mergeResult.exitCode != 0) {
    throw StateError('octopus merge failed: ${mergeResult.stderr}');
  }
  final octopus = (await r.head())!;
  final parents = await parentsOf(r, octopus);
  // Sanity for the builder itself — mainTip/aSha/bSha are exactly the 3.
  if (parents.length != 3 ||
      !parents.contains(mainTip) ||
      !parents.contains(aSha) ||
      !parents.contains(bSha)) {
    throw StateError(
        'buildOctopus produced unexpected parents $parents (expected '
        '$mainTip, $aSha, $bSha)');
  }
  return (octopus: octopus, parents: parents);
}

/// A branch with no common ancestor with `main`, via
/// `git checkout --orphan`. `git rm -rf .` clears both the index AND the
/// working tree of whatever `main`'s files were (`--orphan` alone only
/// detaches history — it leaves the current working tree/index in place),
/// so the orphan's first commit is genuinely unrelated content.
Future<({String orphanHead, String mainHead})> buildOrphanBranch(
    ScratchRepo r) async {
  await r.writeFile('orphan-main.txt', 'main\n');
  final mainHead = await r.commitAll('main commit');

  await r.gitOk(['checkout', '--orphan', 'orphan-branch']);
  await r.gitOk(['rm', '-rf', '.']);
  await r.writeFile('orphan-only.txt', 'orphan\n');
  final orphanHead = await r.commitAll('orphan commit');

  await r.gitOk(['checkout', 'main']);
  return (orphanHead: orphanHead, mainHead: mainHead);
}

/// Two independent root commits merged with `--allow-unrelated-histories`.
/// `main`'s root is the `root` empty commit [ScratchRepo.create] always
/// seeds; `unrelated`'s root is a second `--orphan` branch. So the final
/// merge commit's history contains exactly 2 commits with no parents.
Future<({String merge})> buildUnrelatedHistories(ScratchRepo r) async {
  await r.writeFile('unrelated-main.txt', 'main\n');
  await r.commitAll('main root work');

  await r.gitOk(['checkout', '--orphan', 'unrelated-history']);
  await r.gitOk(['rm', '-rf', '.']);
  await r.writeFile('unrelated-only.txt', 'unrelated\n');
  await r.commitAll('unrelated root work');

  await r.gitOk(['checkout', 'main']);
  final mergeResult = await r.git(
      ['merge', '--no-edit', '--allow-unrelated-histories', 'unrelated-history']);
  if (mergeResult.exitCode != 0) {
    throw StateError(
        'merge --allow-unrelated-histories failed: ${mergeResult.stderr}');
  }
  final merge = (await r.head())!;
  return (merge: merge);
}

/// `HEAD` detached at an older commit, with `main` left one commit ahead.
Future<({String detachedAt, String branchTip})> buildDetachedHead(
    ScratchRepo r) async {
  await r.writeFile('detached-1.txt', '1\n');
  final detachedAt = await r.commitAll('commit 1');
  await r.writeFile('detached-2.txt', '2\n');
  final branchTip = await r.commitAll('commit 2');

  await r.gitOk(['checkout', detachedAt]);
  return (detachedAt: detachedAt, branchTip: branchTip);
}

/// An annotated tag on one commit, a lightweight tag on a later one. Returns
/// the tag *names* (not shas) — `git cat-file -t <name>` resolves a tag name
/// through git's own ref lookup, which is exactly what distinguishes the two
/// kinds: an annotated tag's ref points at a tag object (`cat-file -t` ⇒
/// `tag`), a lightweight tag's ref points directly at the commit (⇒
/// `commit`).
Future<({String annotated, String lightweight})> buildTags(
    ScratchRepo r) async {
  await r.writeFile('tag-1.txt', '1\n');
  final c1 = await r.commitAll('for annotated tag');
  await r.gitOk(['tag', '-a', 'topology-annotated', '-m', 'annotated tag', c1]);

  await r.writeFile('tag-2.txt', '2\n');
  final c2 = await r.commitAll('for lightweight tag');
  await r.gitOk(['tag', 'topology-lightweight', c2]);

  return (annotated: 'topology-annotated', lightweight: 'topology-lightweight');
}

/// A linked worktree at a sibling temp directory, checked out onto a branch
/// whose tip is one commit ahead of `main` (so `main`'s and the worktree's
/// `HEAD` genuinely differ, not just alias the same commit).
///
/// Ownership: the returned `worktreePath` is NOT covered by
/// `ScratchRepo.dispose()` — that only deletes `r.dir` (the *main*
/// worktree); the linked worktree's directory is a sibling, outside it. The
/// caller MUST, before disposing `r`:
///   1. `await r.gitOk(['worktree', 'remove', '--force', worktreePath]);`
///   2. best-effort delete the directory if step 1 didn't already remove it.
/// (`git worktree remove` deletes the directory itself when it succeeds;
/// the manual delete is only a backstop for a failed/partial remove.)
Future<({String worktreePath, String branch})> buildLinkedWorktree(
    ScratchRepo r) async {
  await r.writeFile('worktree-main.txt', 'main\n');
  await r.commitAll('main content');

  const branch = 'linked-worktree-branch';
  await r.gitOk(['checkout', '-b', branch]);
  await r.writeFile('worktree-branch-only.txt', 'branch-only\n');
  await r.commitAll('branch-only content');
  await r.gitOk(['checkout', 'main']);

  final worktreePath =
      p.join(r.dir.parent.path, '${p.basename(r.dir.path)}_linked_wt');
  await r.gitOk(['worktree', 'add', worktreePath, branch]);

  return (worktreePath: worktreePath, branch: branch);
}

/// A committed submodule pointing at a second, independent [ScratchRepo].
///
/// Uses `-c protocol.file.allow=always` because modern git (>= 2.38.1,
/// CVE-2022-39253) refuses to clone/fetch a `file://` remote via a
/// submodule operation by default — exactly what `git submodule add` does
/// internally against a local path. Without the override this call fails
/// with `fatal: transport 'file' not allowed`.
///
/// Ownership: the returned `inner` [ScratchRepo] is a real, independent repo
/// the caller must `dispose()` itself — disposing `r` only removes `r`'s own
/// directory, and does not touch wherever the submodule's separate `.git`
/// (inside `r`'s `.git/modules/`) points its working copy back to.
Future<({String subPath, ScratchRepo inner})> buildSubmodule(
    ScratchRepo r) async {
  final inner = await ScratchRepo.create(name: 'submodule_inner');
  await inner.writeFile('inner.txt', 'inner content\n');
  await inner.commitAll('inner root commit');

  const subPath = 'vendor/inner';
  final url = Uri.file(inner.dir.path).toString();
  final addResult = await r.git([
    '-c',
    'protocol.file.allow=always',
    'submodule',
    'add',
    url,
    subPath,
  ]);
  if (addResult.exitCode != 0) {
    throw StateError('git submodule add failed: ${addResult.stderr}');
  }
  await r.gitOk(['commit', '-m', 'add vendor/inner submodule']);

  return (subPath: subPath, inner: inner);
}

/// A rename with an edit: `from` is committed, then deleted and re-created
/// as `to` with `similarityPercent`% of its line content unchanged (the rest
/// mutated to unrelated text) — exercises git's rename-detection threshold
/// (`-M<n>%`) rather than a pure, byte-identical rename.
Future<({String from, String to, int similarity})> buildRenameWithEdit(
  ScratchRepo r, {
  int similarityPercent = 80,
}) async {
  const from = 'rename_from.txt';
  const to = 'rename_to.txt';

  // Git's rename-similarity index is computed over raw BYTES, not lines —
  // so "mutate (100-similarity)% of the lines" only tracks the requested
  // percentage when every line is the same byte length (otherwise a longer
  // mutated line eats a disproportionate share of the byte budget and the
  // score undershoots). Empirically verified against the installed git
  // (2.52): 50 fixed-width lines with N mutated to a same-length but
  // wholly different filler produces a similarity score of exactly
  // `100 - 2*N` (i.e. mutating 10/50 lines ⇒ R080, 15/50 ⇒ R070, ...),
  // matching the line-fraction formula below to the percentage point.
  final lines = List.generate(50, (i) {
    final idx = i.toString().padLeft(3, '0');
    return 'L$idx ${'x' * 40}\n';
  });
  await r.writeFile(from, lines.join());
  await r.commitAll('add $from');

  final mutateCount =
      ((100 - similarityPercent) / 100 * lines.length).ceil();
  final mutated = List<String>.of(lines);
  for (var i = 0; i < mutateCount && i < mutated.length; i++) {
    final idx = i.toString().padLeft(3, '0');
    mutated[i] = 'L$idx ${'Y' * 40}\n';
  }

  await r.deleteFile(from);
  await r.writeFile(to, mutated.join());
  await r.commitAll('rename $from -> $to with edit');

  return (from: from, to: to, similarity: similarityPercent);
}

/// A file staged with content X, then further modified in the working tree
/// to Y — the "partial staging" state the app's commit path must preserve
/// rather than collapse (a naive `git add -A; git commit` would silently
/// commit Y and lose the fact that the user had staged X specifically).
Future<({String staged, String worktree})> buildStagedVsWorktreeSkew(
    ScratchRepo r) async {
  const path = 'staged-vs-worktree.txt';
  await r.writeFile(path, 'base content\n');
  await r.commitAll('base for staged-vs-worktree skew');

  const stagedContent = 'staged content X\n';
  const worktreeContent = 'worktree content Y (newer than staged)\n';
  await r.writeFile(path, stagedContent);
  await r.stage([path]);
  await r.writeFile(path, worktreeContent);

  return (staged: stagedContent, worktree: worktreeContent);
}

/// A commit whose message AND file content are both hostile: a lone CR (not
/// part of a CRLF pair), a CRLF pair, control characters adjacent to (but
/// NOT) NUL (U+0001/U+0002 — a literal NUL byte is not usable as a
/// process argument: it would truncate the command line on both POSIX
/// `exec` and Windows `CreateProcess`, so it is out of scope for something
/// passed via `-m`), an astral-plane emoji (a UTF-16 surrogate pair / 4
/// UTF-8 bytes), and RTL marks (U+200F RIGHT-TO-LEFT MARK, U+202E
/// RIGHT-TO-LEFT OVERRIDE).
Future<({String sha, String message})> buildHostileContentCommit(
    ScratchRepo r) async {
  const message = 'hostile: lone CR\r here, CRLF\r\n'
      'here, ctl\u0001\u0002ctl, emoji \u{1F9EA}, rtl \u200F\u202Eend';
  await r.writeFile(
    'hostile-content.txt',
    'hostile file: CRLF\r\nlone CR\rhere\nctl\u0001\u0002ctl\n'
        'emoji \u{1F9EA}\nrtl \u200F\u202Eend\n',
  );
  await r.stageAll();
  final commitResult = await r.git(['commit', '-m', message]);
  if (commitResult.exitCode != 0) {
    throw StateError('hostile-content commit failed: ${commitResult.stderr}');
  }
  final sha = await r.gitOk(['rev-parse', 'HEAD']);
  return (sha: sha, message: message);
}
