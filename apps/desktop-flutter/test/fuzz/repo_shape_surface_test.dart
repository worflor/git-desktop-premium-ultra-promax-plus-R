// Repo-shape × surface sweep.
//
// The line-oriented git parsers in lib/backend were only ever exercised in a
// vanilla repo (one worktree, a born branch, HEAD on a branch tip). The shapes
// real clients actually break on — a linked worktree whose `.git` is a FILE,
// a submodule parent, a detached HEAD, an orphan branch, an UNBORN HEAD — were
// never driven through them. test/support/repo_topology.dart already builds
// those shapes deterministically; this suite runs EVERY read surface against
// each and asserts the production contract holds.
//
// LAW per cell (shape × surface):
//   • the surface returns a well-formed result — `ok` with sane/anchored
//     parsed output where cheap (status inside a linked worktree sees the
//     worktree's OWN branch; history in a detached HEAD stops at the detached
//     commit; unborn status reports hasHeadCommit=false), OR
//   • a DOCUMENTED clean error (`ok==false`, no throw) for a genuinely
//     inapplicable cell (history/blame/reflog/coupling in an UNBORN repo have
//     no HEAD to walk — git exits 128, the function must surface that as a
//     clean GitResult.err, never an exception or a garbage parse).
// A genuine parse failure would be skip-pinned as `_knownFinding…Skip` with a
// lib file:line root cause; this sweep found none — every born-repo surface is
// armed, every unborn-inapplicable surface asserts the clean-error contract.
//
// The linked-worktree cleanup contract (repo_topology.dart: `worktree remove
// --force` BEFORE dispose) and the submodule contract (dispose the inner repo)
// are followed in tearDownAll — a leaked worktree corrupts later runs.
//
// OS-portable: no Windows-only path assumptions; package:path everywhere. The
// linked-worktree path handling is exactly where OS differences bite, so every
// join goes through `p.join`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:path/path.dart' as p;

import '../support/repo_topology.dart';
import '../support/scratch_repo.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// ScratchRepo-style global/system config isolation for a raw dir (the unborn
/// repo and the linked worktree, neither of which is a ScratchRepo). Points
/// GIT_CONFIG_GLOBAL/SYSTEM at never-created paths so the host's ~/.gitconfig
/// can't perturb setup ops (identity, stash creation).
Map<String, String> _isoEnv(String dir) => {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': p.join(dir, '.no-global-gitconfig'),
      'GIT_CONFIG_SYSTEM': p.join(dir, '.no-system-gitconfig'),
    };

/// Drive a git op in [dir] with isolation — for test SETUP only (creating a
/// stash, staging). The surfaces under test run through their production
/// functions, which deliberately do NOT get this isolation.
Future<ProcessResult> _gitIn(String dir, List<String> args) =>
    runGit(dir, args, extraEnv: _isoEnv(dir));

/// Overwrites [absPath] with [content], preserving exact bytes.
Future<void> _write(String absPath, String content) =>
    File(absPath).writeAsString(content, flush: true);

Future<String> _read(String absPath) => File(absPath).readAsString();

/// Asserts getFileDiff→parseUnifiedDiff on a MODIFIED tracked [relPath] under
/// [repoPath] yields the real filePath and the expected added/deleted texts,
/// then restores the original bytes so later cells see the pristine tree.
Future<void> _assertDiffCell(
  String repoPath,
  String relPath, {
  required List<String> expectAdded,
  required List<String> expectDeleted,
}) async {
  final abs = p.join(repoPath, relPath);
  final original = await _read(abs);
  try {
    // Mutate line 0 to the caller's expected added text (the caller pairs it
    // with the matching deleted text — the file's original line 0). This turns
    // a one-line edit into a deterministic single -/+ hunk.
    final lines = original.split('\n');
    lines[0] = expectAdded.first.substring(1); // strip the leading '+'
    await _write(abs, lines.join('\n'));

    final r = await getFileDiff(repoPath, relPath);
    expect(r.ok, isTrue, reason: 'getFileDiff($relPath) failed: ${r.error}');
    final parsed = parseUnifiedDiff(r.data ?? '');
    expect(
      parsed.where((l) => l.kind == LineKind.added).map((l) => l.text).toList(),
      expectAdded,
      reason: 'added texts mismatch for $relPath in $repoPath',
    );
    expect(
      parsed
          .where((l) => l.kind == LineKind.deleted)
          .map((l) => l.text)
          .toList(),
      expectDeleted,
      reason: 'deleted texts mismatch for $relPath in $repoPath',
    );
    expect(
      parsed
          .where((l) => l.kind != LineKind.meta)
          .every((l) => l.filePath == relPath),
      isTrue,
      reason: 'diff filePath not the real name: '
          '${parsed.map((l) => l.filePath).toSet()}',
    );
  } finally {
    await _write(abs, original);
  }
}

/// Creates a one-line edit to [relPath], stashes it (reverting the tree), and
/// asserts stashFiles surfaces exactly that file. [gitDir] is where the git op
/// runs (the worktree path for the linked-worktree shape, else the repo dir).
Future<void> _assertStashCell(
  String repoPath,
  String gitDir,
  String relPath,
) async {
  final abs = p.join(repoPath, relPath);
  final original = await _read(abs);
  final firstLine = original.split('\n').first;
  await _write(abs, original.replaceFirst(firstLine, '$firstLine-EDIT'));
  final push =
      await _gitIn(gitDir, ['stash', 'push', '-m', 'shape-sweep-stash']);
  expect(push.exitCode, 0,
      reason: 'stash push failed in $gitDir: ${push.stderr}');
  final r = await stashFiles(repoPath);
  expect(r.ok, isTrue, reason: 'stashFiles failed: ${r.error}');
  expect(r.data!.map((s) => s.path).toList(), contains(relPath),
      reason: 'stash did not surface $relPath: '
          '${r.data!.map((s) => s.path).toList()}');
}

/// The reflog surface is broken repo-wide by the `%09`-vs-`%x09` format bug
/// (see hostile_gitconfig_differential_test.dart :_fReflogTabEscape): git's
/// pretty-format has no `%09` escape, so listReflog parses zero entries and
/// ALWAYS returns []. The shape LAW here is only the contract that survives
/// that bug: a born repo yields `ok` (an empty list is still well-formed),
/// an unborn repo yields a clean error. Content is NOT asserted — that witness
/// lives in the differential's ground-truth anchor.
Future<void> _assertReflogOkOnBornRepo(String repoPath) async {
  final r = await listReflog(repoPath, limit: 50);
  expect(r.ok, isTrue, reason: 'listReflog errored on a born repo: ${r.error}');
}

// ---------------------------------------------------------------------------
// Unborn-HEAD repo — a raw `git init` with zero commits (ScratchRepo.create
// always seeds a root commit, so the unborn case is built by hand).
// ---------------------------------------------------------------------------

class _UnbornRepo {
  final Directory sandbox;
  final Directory dir;
  _UnbornRepo._(this.sandbox, this.dir);

  Future<ProcessResult> git(List<String> args) => _gitIn(dir.path, args);

  static Future<_UnbornRepo> create() async {
    final sandbox =
        await Directory.systemTemp.createTemp('scratch_repo_unborn_');
    final dir = Directory(p.join(sandbox.path, 'repo'));
    await dir.create();
    final r = _UnbornRepo._(sandbox, dir);
    final init = await r.git(['init', '-q', '-b', 'main']);
    if (init.exitCode != 0) {
      throw StateError('git init failed: ${init.stderr}');
    }
    // Repo-local identity so any op that needs one works; NO commit is made,
    // so HEAD stays unborn (points at refs/heads/main which does not exist).
    final cfg = File(p.join(dir.path, '.git', 'config'));
    final existing = await cfg.readAsString();
    final buf = StringBuffer(existing);
    if (!existing.endsWith('\n')) buf.write('\n');
    buf
      ..writeln('[user]')
      ..writeln('\tname = Scratch Repo')
      ..writeln('\temail = scratch@example.invalid')
      ..writeln('[commit]')
      ..writeln('\tgpgsign = false');
    await cfg.writeAsString(buf.toString(), flush: true);
    return r;
  }

  Future<void> dispose() async {
    try {
      await sandbox.delete(recursive: true);
    } catch (_) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- worktree
  group('law 1 — linked worktree (.git is a FILE), surfaces run FROM the '
      'worktree path', () {
    late ScratchRepo repo;
    late String wt; // the linked worktree path
    const target = 'worktree-branch-only.txt';

    setUpAll(() async {
      repo = await ScratchRepo.create(name: 'shape_worktree');
      final built = await buildLinkedWorktree(repo);
      wt = built.worktreePath;
      await assertFsckClean(repo, because: 'buildLinkedWorktree');
      // Sanity: the linked worktree's `.git` really is a FILE (the classic
      // broken assumption is that it is a directory).
      expect(await FileSystemEntity.isFile(p.join(wt, '.git')), isTrue,
          reason: 'linked worktree .git should be a gitdir FILE, not a dir');
    });

    tearDownAll(() async {
      // Cleanup contract: remove the linked worktree BEFORE disposing repo.
      await repo.gitOk(['worktree', 'remove', '--force', wt]);
      await repo.dispose();
    });

    test('status sees the worktree OWN branch', () async {
      final r = await getRepositoryStatus(wt);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.branch, 'linked-worktree-branch');
      expect(r.data!.hasHeadCommit, isTrue);
    });

    test('history + bulk from the worktree', () async {
      final h = await listCommitHistory(wt, limit: 50);
      expect(h.ok, isTrue, reason: h.error);
      final subjects = h.data!.map((c) => c.subject).toList();
      expect(subjects, contains('branch-only content'));
      expect(subjects, contains('main content'));
      final b = await bulkGetCommitDetails(wt, h.data!, limit: 50);
      expect(b.ok, isTrue, reason: b.error);
      expect(b.data!.length, h.data!.length);
    });

    test('branches — worktree branch is current', () async {
      final r = await listBranches(wt);
      expect(r.ok, isTrue, reason: r.error);
      final names = r.data!.map((b) => b.name).toSet();
      expect(names, containsAll(['main', 'linked-worktree-branch']));
      final current = r.data!.where((b) => b.current).map((b) => b.name);
      expect(current, ['linked-worktree-branch']);
    });

    test('blame a worktree file', () async {
      final r = await getFileBlame(wt, target);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.map((l) => l.lineContent).toList(), ['branch-only']);
    });

    test('coupling from the worktree', () async {
      final r = await computeFileCoupling(wt, halfLifeCommits: 0);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.paths, contains('worktree-main.txt'));
    });

    test('reflog (ok; empty by the %09 bug)',
        () => _assertReflogOkOnBornRepo(wt));

    test('diff a modified worktree file', () async {
      await _assertDiffCell(wt, target,
          expectAdded: ['+branch-EDITED'], expectDeleted: ['-branch-only']);
    });

    test('stash from the worktree', () => _assertStashCell(wt, wt, target));
  });

  // --------------------------------------------------------------- submodule
  group('law 2 — submodule parent', () {
    late ScratchRepo repo;
    late ScratchRepo inner;
    const target = 'probe.txt';

    setUpAll(() async {
      repo = await ScratchRepo.create(name: 'shape_submodule');
      final built = await buildSubmodule(repo);
      inner = built.inner;
      // A committed multi-line regular file to blame/diff/stash (the parent
      // otherwise only tracks .gitmodules + the gitlink).
      await repo.writeFile(target, 'l1\nl2\nl3\n');
      await repo.commitAll('probe commit');
      await assertFsckClean(repo, because: 'buildSubmodule');
    });

    tearDownAll(() async {
      // Submodule contract: dispose the independent inner repo too.
      await inner.dispose();
      await repo.dispose();
    });

    test('status', () async {
      final r = await getRepositoryStatus(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.hasHeadCommit, isTrue);
      expect(r.data!.branch, 'main');
    });

    test('history + bulk includes the submodule-add commit', () async {
      final h = await listCommitHistory(repo.dir.path, limit: 50);
      expect(h.ok, isTrue, reason: h.error);
      expect(h.data!.map((c) => c.subject),
          contains('add vendor/inner submodule'));
      final b = await bulkGetCommitDetails(repo.dir.path, h.data!, limit: 50);
      expect(b.ok, isTrue, reason: b.error);
      expect(b.data!.length, h.data!.length);
    });

    test('branches', () async {
      final r = await listBranches(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.where((b) => b.current).map((b) => b.name), ['main']);
    });

    test('blame the probe file', () async {
      final r = await getFileBlame(repo.dir.path, target);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.map((l) => l.lineContent).toList(), ['l1', 'l2', 'l3']);
    });

    test('coupling', () async {
      final r = await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
      expect(r.ok, isTrue, reason: r.error);
    });

    test('reflog (ok; empty by the %09 bug)',
        () => _assertReflogOkOnBornRepo(repo.dir.path));

    test('diff a modified probe file', () async {
      await _assertDiffCell(repo.dir.path, target,
          expectAdded: ['+l1-EDITED'], expectDeleted: ['-l1']);
    });

    test('stash', () =>
        _assertStashCell(repo.dir.path, repo.dir.path, target));
  });

  // ------------------------------------------------------------ detached HEAD
  group('law 3 — detached HEAD', () {
    late ScratchRepo repo;
    late String detachedAt;
    const target = 'detached-1.txt';

    setUpAll(() async {
      repo = await ScratchRepo.create(name: 'shape_detached');
      final built = await buildDetachedHead(repo);
      detachedAt = built.detachedAt;
      await assertFsckClean(repo, because: 'buildDetachedHead');
    });

    tearDownAll(() => repo.dispose());

    test('status reports empty branch (detached)', () async {
      final r = await getRepositoryStatus(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.branch, '', reason: 'detached HEAD → no branch name');
      expect(r.data!.hasHeadCommit, isTrue);
    });

    test('history stops at the detached commit', () async {
      final h = await listCommitHistory(repo.dir.path, limit: 50);
      expect(h.ok, isTrue, reason: h.error);
      final subjects = h.data!.map((c) => c.subject).toList();
      expect(subjects, contains('commit 1'));
      expect(subjects, isNot(contains('commit 2')),
          reason: 'commit 2 is ahead of the detached HEAD; must not appear');
      expect(h.data!.first.commitHash, detachedAt);
      final b = await bulkGetCommitDetails(repo.dir.path, h.data!, limit: 50);
      expect(b.ok, isTrue, reason: b.error);
    });

    test('branches — main present, none of the real branches current',
        () async {
      final r = await listBranches(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      final names = r.data!.map((b) => b.name).toSet();
      expect(names, contains('main'));
      // git emits a synthetic `(HEAD detached at …)` pseudo-entry marked
      // current; the real branch `main` is NOT current.
      final mainRow = r.data!.firstWhere((b) => b.name == 'main');
      expect(mainRow.current, isFalse);
    });

    test('blame the detached-commit file', () async {
      final r = await getFileBlame(repo.dir.path, target);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.map((l) => l.lineContent).toList(), ['1']);
    });

    test('coupling from detached HEAD', () async {
      final r = await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.paths, contains(target));
    });

    test('reflog (ok; empty by the %09 bug)',
        () => _assertReflogOkOnBornRepo(repo.dir.path));

    test('diff a modified detached-commit file', () async {
      await _assertDiffCell(repo.dir.path, target,
          expectAdded: ['+1-EDITED'], expectDeleted: ['-1']);
    });

    test('stash', () =>
        _assertStashCell(repo.dir.path, repo.dir.path, target));
  });

  // ----------------------------------------------------------- orphan branch
  group('law 4 — orphan branch checked out', () {
    late ScratchRepo repo;
    const target = 'orphan-only.txt';

    setUpAll(() async {
      repo = await ScratchRepo.create(name: 'shape_orphan');
      await buildOrphanBranch(repo);
      // buildOrphanBranch leaves `main` checked out; the LAW is the orphan
      // branch ITSELF checked out.
      await repo.gitOk(['checkout', 'orphan-branch']);
      await assertFsckClean(repo, because: 'buildOrphanBranch');
    });

    tearDownAll(() => repo.dispose());

    test('status on the orphan branch', () async {
      final r = await getRepositoryStatus(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.branch, 'orphan-branch');
      expect(r.data!.hasHeadCommit, isTrue);
    });

    test('history — only the orphan commit (no shared root)', () async {
      final h = await listCommitHistory(repo.dir.path, limit: 50);
      expect(h.ok, isTrue, reason: h.error);
      expect(h.data!.map((c) => c.subject).toList(), ['orphan commit']);
      final b = await bulkGetCommitDetails(repo.dir.path, h.data!, limit: 50);
      expect(b.ok, isTrue, reason: b.error);
    });

    test('branches — orphan branch is current', () async {
      final r = await listBranches(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      final names = r.data!.map((b) => b.name).toSet();
      expect(names, containsAll(['main', 'orphan-branch']));
      expect(r.data!.where((b) => b.current).map((b) => b.name),
          ['orphan-branch']);
    });

    test('blame the orphan file', () async {
      final r = await getFileBlame(repo.dir.path, target);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.map((l) => l.lineContent).toList(), ['orphan']);
    });

    test('coupling on the orphan branch', () async {
      final r = await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
      expect(r.ok, isTrue, reason: r.error);
    });

    test('reflog (ok; empty by the %09 bug)',
        () => _assertReflogOkOnBornRepo(repo.dir.path));

    test('diff a modified orphan file', () async {
      await _assertDiffCell(repo.dir.path, target,
          expectAdded: ['+orphan-EDITED'], expectDeleted: ['-orphan']);
    });

    test('stash', () =>
        _assertStashCell(repo.dir.path, repo.dir.path, target));
  });

  // ------------------------------------------------------------- unborn HEAD
  group('law 5 — unborn HEAD (git init, zero commits)', () {
    late _UnbornRepo repo;

    setUpAll(() async {
      repo = await _UnbornRepo.create();
      // Stage a file so the diff surface has a --cached diff to parse, while
      // HEAD stays unborn.
      await _write(p.join(repo.dir.path, 'f.txt'), 'a\nb\n');
      final add = await repo.git(['add', 'f.txt']);
      expect(add.exitCode, 0, reason: 'git add failed: ${add.stderr}');
    });

    tearDownAll(() => repo.dispose());

    test('status reports hasHeadCommit=false (armed)', () async {
      final r = await getRepositoryStatus(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data!.hasHeadCommit, isFalse,
          reason: 'unborn HEAD → branch.oid (initial)');
      expect(r.data!.branch, 'main');
    });

    test('history — clean error (no HEAD to walk); bulk of [] is ok-empty',
        () async {
      final h = await listCommitHistory(repo.dir.path, limit: 50);
      expect(h.ok, isFalse,
          reason: 'unborn HEAD: git log exits 128 → GitResult.err');
      // The natural downstream call with an empty commit list must not throw.
      final b = await bulkGetCommitDetails(repo.dir.path, const [], limit: 50);
      expect(b.ok, isTrue, reason: b.error);
      expect(b.data, isEmpty);
    });

    test('branches — ok, empty (no branch exists until first commit)',
        () async {
      final r = await listBranches(repo.dir.path);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.data, isEmpty);
    });

    test('blame — clean error (no such ref: HEAD)', () async {
      final r = await getFileBlame(repo.dir.path, 'f.txt');
      expect(r.ok, isFalse, reason: 'unborn blame must be a clean GitResult.err');
    });

    test('coupling — clean error (log exits 128)', () async {
      final r = await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
      expect(r.ok, isFalse);
    });

    test('reflog — clean error (no commits yet)', () async {
      final r = await listReflog(repo.dir.path, limit: 50);
      expect(r.ok, isFalse,
          reason: 'unborn reflog exits 128 → GitResult.err');
    });

    test('diff — staged --cached addition parses (armed)', () async {
      final r = await getFileDiff(repo.dir.path, 'f.txt', staged: true);
      expect(r.ok, isTrue, reason: r.error);
      final parsed = parseUnifiedDiff(r.data ?? '');
      expect(
        parsed.where((l) => l.kind == LineKind.added).map((l) => l.text),
        ['+a', '+b'],
      );
      expect(
        parsed
            .where((l) => l.kind != LineKind.meta)
            .every((l) => l.filePath == 'f.txt'),
        isTrue,
      );
    });

    test('stash — clean error (no stash / no initial commit)', () async {
      final r = await stashFiles(repo.dir.path);
      expect(r.ok, isFalse,
          reason: 'unborn stash must surface a clean GitResult.err');
    });
  });
}
