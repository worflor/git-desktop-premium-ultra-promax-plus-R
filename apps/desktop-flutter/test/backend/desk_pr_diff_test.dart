// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Integration tests for local desk-PR diff materialisation.
//
// Each test spins up a real temp git repo, wires the branch topology by
// hand with plain `git` shell-outs, and drives `fetchLocalDeskPrDetail`
// against it — no mocks. The contract under test is that a desk PR's
// diff is scoped to the *merge base* of base and head (three-dot), so a
// base ref that has advanced past the fork point never leaks upstream
// commit reversals into the PR, and that renames / binaries / non-ASCII
// paths survive the numstat parse byte-exactly.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_diff.dart';

Future<Directory> _newRepo() async {
  final dir = await Directory.systemTemp.createTemp('manifold_diff_test_');
  await Process.run('git', ['init', '-q', '-b', 'main'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dir.path);
  // Keep line endings verbatim so byte-exact path/diff assertions hold
  // identically on Windows (where autocrlf would otherwise rewrite blobs).
  await Process.run('git', ['config', 'core.autocrlf', 'false'],
      workingDirectory: dir.path);
  return dir;
}

/// Tolerant cleanup — Windows briefly holds file handles after spawned
/// `git` processes exit, which can race with our `delete(recursive:)`
/// call and throw PathAccessException for ~100ms. The handles drop on
/// their own; swallowing the error keeps the test signal honest (the
/// assertions ran; the tmp dir is the OS's problem).
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see _safeCleanup docstring.
  }
}

Future<void> _git(Directory repo, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: repo.path);
  expect(r.exitCode, 0,
      reason: 'git ${args.join(' ')} failed: ${r.stderr}');
}

Future<void> _write(Directory repo, String path, String contents) async {
  final f = File('${repo.path}${Platform.pathSeparator}$path');
  await f.parent.create(recursive: true);
  await f.writeAsString(contents);
}

Future<void> _writeBytes(Directory repo, String path, List<int> bytes) async {
  final f = File('${repo.path}${Platform.pathSeparator}$path');
  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes);
}

/// A minimal DeskPr carrying only the fields the diff path reads
/// (head/base refs); everything else is inert placeholder metadata.
DeskPr _pr({required String base, required String head}) => DeskPr(
      deskId: 1,
      title: 't',
      body: '',
      headRef: head,
      baseRef: base,
      state: 'OPEN',
      isDraft: false,
      authorIdentity: 'tester',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('base advancing past the fork shows only the branch changes', () async {
    final repo = await _newRepo();
    try {
      // Fork point: both files exist on main.
      await _write(repo, 'branch_file.txt', 'a\nb\nc\n');
      await _write(repo, 'upstream_file.txt', 'orig\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'base']);

      // Branch changes ONLY branch_file.txt.
      await _git(repo, ['checkout', '-q', '-b', 'feat']);
      await _write(repo, 'branch_file.txt', 'a\nb\nc\nd\n');
      await _git(repo, ['commit', '-q', '-am', 'branch work']);

      // Base (main) advances past the fork with an unrelated change to
      // upstream_file.txt — the exact scenario that made the old two-dot
      // `base..head` diff report a reversal of upstream_file.txt.
      await _git(repo, ['checkout', '-q', 'main']);
      await _write(repo, 'upstream_file.txt', 'orig\nupstream change\n');
      await _git(repo, ['commit', '-q', '-am', 'upstream moves on']);
      await _git(repo, ['checkout', '-q', 'feat']);

      final res = await fetchLocalDeskPrDetail(
        repoPath: repo.path,
        pr: _pr(base: 'main', head: 'feat'),
      );
      expect(res.ok, isTrue, reason: res.error);
      final paths = res.data!.files.map((f) => f.path).toList();

      // The branch's own file is present...
      expect(paths, contains('branch_file.txt'));
      // ...and the upstream file the branch never touched is ABSENT.
      // Two-dot would have listed it as a 0/1 reversal.
      expect(paths, isNot(contains('upstream_file.txt')));
      expect(res.data!.diff, isNot(contains('upstream_file.txt')));
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('a rename on the branch parses to the new path with counts',
      () async {
    final repo = await _newRepo();
    try {
      await _write(repo, 'old_name.txt', 'a\nb\nc\nd\ne\nf\ng\nh\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'base']);

      await _git(repo, ['checkout', '-q', '-b', 'feat']);
      await _git(repo, ['mv', 'old_name.txt', 'new_name.txt']);
      // A small edit keeps similarity high enough that git records a
      // rename rather than an add/delete pair, and gives a nonzero count.
      await _write(repo, 'new_name.txt', 'a\nb\nc\nd\ne\nf\ng\nh\ni\n');
      await _git(repo, ['commit', '-q', '-am', 'rename with tweak']);

      final res = await fetchLocalDeskPrDetail(
        repoPath: repo.path,
        pr: _pr(base: 'main', head: 'feat'),
      );
      expect(res.ok, isTrue, reason: res.error);
      final paths = res.data!.files.map((f) => f.path).toList();

      // Surfaced as the NEW path (what parseUnifiedDiff/sliceDiffByFile
      // key the hunks on), never the old path or a mangled `old => new`.
      expect(paths, contains('new_name.txt'));
      expect(paths, isNot(contains('old_name.txt')));
      expect(paths.any((p) => p.contains('=>')), isFalse);

      final entry =
          res.data!.files.firstWhere((f) => f.path == 'new_name.txt');
      expect(entry.additions, 1);
      expect(entry.deletions, 0);
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('binary file yields a 0/0 entry and does not crash', () async {
    final repo = await _newRepo();
    try {
      await _write(repo, 'seed.txt', 'seed\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'base']);

      await _git(repo, ['checkout', '-q', '-b', 'feat']);
      await _writeBytes(repo, 'blob.bin', [0, 1, 2, 3, 0, 255, 4]);
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'add binary']);

      final res = await fetchLocalDeskPrDetail(
        repoPath: repo.path,
        pr: _pr(base: 'main', head: 'feat'),
      );
      expect(res.ok, isTrue, reason: res.error);
      final entry = res.data!.files.firstWhere((f) => f.path == 'blob.bin');
      // Binary numstat is `-`/`-` → normalised to 0/0 with the path kept.
      expect(entry.additions, 0);
      expect(entry.deletions, 0);
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('unrelated histories fall back to two-dot without throwing',
      () async {
    final repo = await _newRepo();
    try {
      // main has its own root commit.
      await _write(repo, 'main_file.txt', 'main\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'main root']);

      // An orphan branch with a disjoint root → no merge base with main.
      await _git(repo, ['checkout', '-q', '--orphan', 'stranger']);
      await _git(repo, ['rm', '-rf', '--quiet', '.']);
      await _write(repo, 'stranger_file.txt', 'hello\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'stranger root']);

      final res = await fetchLocalDeskPrDetail(
        repoPath: repo.path,
        pr: _pr(base: 'main', head: 'stranger'),
      );
      // Must not throw / must not err; graceful two-dot degradation.
      expect(res.ok, isTrue, reason: res.error);
      final paths = res.data!.files.map((f) => f.path).toList();
      // The two-dot diff of two unrelated trees names both files.
      expect(paths, contains('stranger_file.txt'));
    } finally {
      await _safeCleanup(repo);
    }
  });

  test('non-ASCII filename parses to the correct path', () async {
    final repo = await _newRepo();
    try {
      await _write(repo, 'seed.txt', 'seed\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'base']);

      await _git(repo, ['checkout', '-q', '-b', 'feat']);
      // Non-ASCII, and a space, to prove the -z NUL walk keeps the path
      // whole where the old whitespace-trim + TAB-split would corrupt it.
      const fancy = 'héllo wörld.txt';
      await _write(repo, fancy, 'ünïcödé\n');
      await _git(repo, ['add', '-A']);
      await _git(repo, ['commit', '-q', '-m', 'add unicode file']);

      final res = await fetchLocalDeskPrDetail(
        repoPath: repo.path,
        pr: _pr(base: 'main', head: 'feat'),
      );
      expect(res.ok, isTrue, reason: res.error);
      final paths = res.data!.files.map((f) => f.path).toList();
      expect(paths, contains(fancy));
    } finally {
      await _safeCleanup(repo);
    }
  });
}
