// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Property-based (seeded random) tests for local desk-PR diff
// materialisation. Where desk_pr_diff_test.dart pins hand-built
// topologies, this file fuzzes small-repo topologies against git itself
// as the oracle: it builds a real temp repo, drives
// `fetchLocalDeskPrDetail`, and compares the reported file set / rename
// representation / fallback behaviour against an *independent* shell-out
// to git (never the engine's own parser).
//
// All randomness is drawn from `Random(seed)` with FIXED literal seeds
// (`_seeds`), so every case is deterministic and reproducible. Each
// generated test carries its seed + topology parameters in its name and
// in every `reason:`, so a red case is diagnosable without a rerun.
//
// Ground truth always comes from `git diff --name-only -z ...` (NUL
// separated, the only rename/unicode-robust format) parsed here in the
// test, so the tool is never checked against itself.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_diff.dart';

/// Fixed literal seeds — reproducible failures. ~10 cases per property.
const List<int> _seeds = [1, 7, 13, 42, 101, 777, 2024, 31337, 90210, 555];

/// NUL, the field separator emitted by `git ... -z`. Kept as an escape
/// (never a literal NUL in source — that byte is invisible in diffs and
/// binary to grep).
final String _nul = String.fromCharCode(0); // NUL field sep from git -z

// ---------------------------------------------------------------------------
// Temp-repo scaffolding (mirrors desk_pr_diff_test.dart, kept local so this
// file is self-contained and does not depend on another test's helpers).
// ---------------------------------------------------------------------------

Future<Directory> _newRepo() async {
  final dir =
      await Directory.systemTemp.createTemp('manifold_diff_prop_test_');
  await Process.run('git', ['init', '-q', '-b', 'main'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.name', 'test'],
      workingDirectory: dir.path);
  await Process.run('git', ['config', 'user.email', 'test@local'],
      workingDirectory: dir.path);
  // Verbatim line endings so byte-exact path/diff assertions hold on Windows
  // (autocrlf would otherwise rewrite blobs).
  await Process.run('git', ['config', 'core.autocrlf', 'false'],
      workingDirectory: dir.path);
  return dir;
}

/// Tolerant cleanup — Windows briefly holds file handles after spawned
/// `git` processes exit, racing our recursive delete for ~100ms. The
/// handles drop on their own; swallowing the error keeps the signal honest.
Future<void> _safeCleanup(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    // Ignored — see docstring.
  }
}

Future<void> _git(Directory repo, List<String> args, {String? reason}) async {
  final r = await Process.run('git', args, workingDirectory: repo.path);
  expect(r.exitCode, 0,
      reason: 'git ${args.join(' ')} failed: ${r.stderr}'
          '${reason == null ? '' : '  [$reason]'}');
}

/// Capture stdout of a git command as UTF-8 (byte-faithful for the -z
/// ground-truth queries).
Future<String> _capture(Directory repo, List<String> args) async {
  final r = await Process.run('git', args,
      workingDirectory: repo.path, stdoutEncoding: utf8, stderrEncoding: utf8);
  return r.stdout as String;
}

/// Ground-truth file set from git itself: `git diff --name-only -z <spec>`,
/// split on NUL. `--find-renames` mirrors the flag the tool passes so a
/// moved file collapses to its single new path on both sides.
Future<Set<String>> _nameOnly(Directory repo, String spec) async {
  final out = await _capture(
      repo, ['diff', '--name-only', '-z', '--find-renames', spec]);
  return out.split(_nul).where((s) => s.isNotEmpty).toSet();
}

/// True iff git can find a merge base for [base] and [head].
Future<bool> _hasMergeBase(Directory repo, String base, String head) async {
  final r = await Process.run('git', ['merge-base', base, head],
      workingDirectory: repo.path);
  return r.exitCode == 0;
}

Future<void> _writeLines(
    Directory repo, String path, List<String> lines) async {
  final f = File('${repo.path}${Platform.pathSeparator}$path');
  await f.parent.create(recursive: true);
  await f.writeAsString('${lines.join('\n')}\n');
}

Future<void> _append(Directory repo, String path, String line) async {
  final f = File('${repo.path}${Platform.pathSeparator}$path');
  await f.parent.create(recursive: true);
  final existing = await f.exists() ? await f.readAsString() : '';
  await f.writeAsString('$existing$line\n');
}

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

/// Drive the tool and return the reported path set. Fails loudly (with the
/// caller's [reason]) if the tool errored.
Future<Set<String>> _toolPaths(Directory repo,
    {required String base,
    required String head,
    required String reason}) async {
  final res = await fetchLocalDeskPrDetail(
      repoPath: repo.path, pr: _pr(base: base, head: head));
  expect(res.ok, isTrue, reason: 'tool errored: ${res.error}  [$reason]');
  return res.data!.files.map((f) => f.path).toSet();
}

/// A non-empty random subset of [pool].
List<T> _subset<T>(Random rng, List<T> pool) {
  final shuffled = [...pool]..shuffle(rng);
  final k = 1 + rng.nextInt(pool.length);
  return shuffled.take(k).toList();
}

/// Seed ASCII working files with multi-line content (long enough that a
/// one-line edit keeps rename similarity well above git's 50% default).
List<String> _asciiFiles(Random rng) {
  final count = 5 + rng.nextInt(8); // 5..12
  return [
    for (var i = 0; i < count; i++) 'file_${i.toString().padLeft(2, '0')}.txt'
  ];
}

Future<void> _commitAll(Directory repo, String message) async {
  await _git(repo, ['add', '-A']);
  await _git(repo, ['commit', '-q', '-m', message]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Property 1 — file-set correctness.
  //
  // For a random topology (random fork point, base advanced 0-5 commits with
  // overlapping touched files), the tool's reported file set must EQUAL, as a
  // set, `git diff --name-only base...head` (three-dot, merge-base scoped).
  // This includes the case where a file is independently modified on both the
  // advanced base and the branch: three-dot must reflect branch-relative
  // changes only, never base's post-fork edits — which is exactly what the
  // git oracle encodes.
  // -------------------------------------------------------------------------
  for (final seed in _seeds) {
    test('P1 file-set == git three-dot [seed=$seed]', () async {
      final rng = Random(seed);
      final files = _asciiFiles(rng);
      final forkCommits = 2 + rng.nextInt(5); // 2..6 (random fork point)
      final headCommits = 3 + rng.nextInt(6); // 3..8
      final baseAdvance = rng.nextInt(6); // 0..5
      final desc = 'seed=$seed files=${files.length} fork=$forkCommits '
          'head=$headCommits base=$baseAdvance';

      final repo = await _newRepo();
      try {
        // Root: every file exists at the fork ancestry.
        for (final f in files) {
          await _writeLines(repo, f, [for (var i = 0; i < 20; i++) '$f L$i']);
        }
        await _commitAll(repo, 'init');

        // Fork-point walk on main.
        for (var c = 0; c < forkCommits; c++) {
          for (final f in _subset(rng, files)) {
            await _append(repo, f, 'main-pre-$c');
          }
          await _git(repo, ['commit', '-q', '-am', 'pre$c'], reason: desc);
        }

        await _git(repo, ['checkout', '-q', '-b', 'feat'], reason: desc);

        // Head-side commits.
        for (var c = 0; c < headCommits; c++) {
          for (final f in _subset(rng, files)) {
            await _append(repo, f, 'head-$c');
          }
          await _git(repo, ['commit', '-q', '-am', 'head$c'], reason: desc);
        }

        // Base advances past the fork, deliberately overlapping the branch's
        // touched files.
        await _git(repo, ['checkout', '-q', 'main'], reason: desc);
        for (var c = 0; c < baseAdvance; c++) {
          for (final f in _subset(rng, files)) {
            await _append(repo, f, 'base-$c');
          }
          await _git(repo, ['commit', '-q', '-am', 'base$c'], reason: desc);
        }
        await _git(repo, ['checkout', '-q', 'feat'], reason: desc);

        final tool =
            await _toolPaths(repo, base: 'main', head: 'feat', reason: desc);
        final oracle = await _nameOnly(repo, 'main...feat');
        expect(tool, equals(oracle),
            reason: 'three-dot file-set mismatch  [$desc]');
      } finally {
        await _safeCleanup(repo);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Property 2 — rename representation.
  //
  // Contract per desk_pr_diff.dart: a rename is surfaced as its NEW path
  // carrying the numstat counts; never the old path, never a mangled
  // `old => new` token. Forces both a PURE rename (git mv, no content change)
  // and a RENAME+EDIT (small edit on a long file, staying above git's 50%
  // similarity default so -M detects it) in randomized topologies. Ground
  // truth: `git diff --name-only -z` (single new path) plus `--name-status`
  // to confirm git genuinely classified it R (not add+delete).
  // -------------------------------------------------------------------------
  for (final seed in _seeds) {
    test('P2 rename -> new path [seed=$seed]', () async {
      final rng = Random(seed);
      final files = _asciiFiles(rng);
      final forkCommits = rng.nextInt(3); // 0..2
      final baseAdvance = rng.nextInt(4); // 0..3
      final desc = 'seed=$seed files=${files.length} fork=$forkCommits '
          'base=$baseAdvance';

      final repo = await _newRepo();
      try {
        for (final f in files) {
          await _writeLines(repo, f, [for (var i = 0; i < 20; i++) '$f L$i']);
        }
        await _commitAll(repo, 'init');

        for (var c = 0; c < forkCommits; c++) {
          for (final f in _subset(rng, files)) {
            await _append(repo, f, 'main-pre-$c');
          }
          await _git(repo, ['commit', '-q', '-am', 'pre$c'], reason: desc);
        }

        await _git(repo, ['checkout', '-q', '-b', 'feat'], reason: desc);

        // Pick two distinct files to rename.
        final pool = [...files]..shuffle(rng);
        final pureOld = pool[0];
        final editOld = pool[1];
        final pureNew = 'renamed_pure_$pureOld';
        final editNew = 'renamed_edit_$editOld';

        // Pure rename: identical content -> git records R100.
        await _git(repo, ['mv', pureOld, pureNew], reason: desc);
        // Rename + small edit on a 20-line file (~95% similar): still R.
        await _git(repo, ['mv', editOld, editNew], reason: desc);
        await _append(repo, editNew, 'one extra line');
        await _git(repo, ['commit', '-q', '-am', 'renames'], reason: desc);

        // Base advances (may touch the renamed old paths — irrelevant to a
        // three-dot branch-relative diff).
        await _git(repo, ['checkout', '-q', 'main'], reason: desc);
        for (var c = 0; c < baseAdvance; c++) {
          for (final f in _subset(rng, files)) {
            await _append(repo, f, 'base-$c');
          }
          await _git(repo, ['commit', '-q', '-am', 'base$c'], reason: desc);
        }
        await _git(repo, ['checkout', '-q', 'feat'], reason: desc);

        final tool =
            await _toolPaths(repo, base: 'main', head: 'feat', reason: desc);

        // Set equality vs the git oracle (renames collapse to new path there).
        final oracle = await _nameOnly(repo, 'main...feat');
        expect(tool, equals(oracle),
            reason: 'rename file-set mismatch  [$desc]');

        // New paths present; old paths gone; no `=>` mangling anywhere.
        expect(tool, contains(pureNew),
            reason: 'pure new path missing  [$desc]');
        expect(tool, contains(editNew),
            reason: 'edit new path missing  [$desc]');
        expect(tool, isNot(contains(pureOld)),
            reason: 'pure old path leaked  [$desc]');
        expect(tool, isNot(contains(editOld)),
            reason: 'edit old path leaked  [$desc]');
        expect(tool.any((p) => p.contains('=>')), isFalse,
            reason: 'mangled `old => new` token  [$desc]');

        // Confirm git actually classified them as renames (R\d+), so the
        // above is testing rename handling, not an accidental add/delete.
        final statusZ = await _capture(repo,
            ['diff', '--name-status', '-z', '--find-renames', 'main...feat']);
        final rStatuses = statusZ
            .split(_nul)
            .where((t) => RegExp(r'^R\d+$').hasMatch(t))
            .length;
        expect(rStatuses, greaterThanOrEqualTo(2),
            reason: 'git did not classify both moves as renames  [$desc]');

        // The rename+edit entry must carry a nonzero add count (the extra line).
        final res = await fetchLocalDeskPrDetail(
            repoPath: repo.path, pr: _pr(base: 'main', head: 'feat'));
        final editEntry = res.data!.files.firstWhere((f) => f.path == editNew);
        expect(editEntry.additions, greaterThan(0),
            reason: 'rename+edit lost its added line  [$desc]');
      } finally {
        await _safeCleanup(repo);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Property 3 — unrelated-histories fallback, engaged EXACTLY when there is
  // no merge base.
  //
  // Two halves per seed:
  //  (a) POSITIVE: two orphan roots (no common ancestor). merge-base absent →
  //      tool must degrade to the two-dot tree diff and match
  //      `git diff --name-only base..head`.
  //  (b) NEGATIVE CONTROL: a DEEP fork with the base advanced on a file the
  //      branch never touches. merge-base present → tool must stay three-dot
  //      (match base...head), and must NOT equal the two-dot set (which would
  //      leak the upstream-only file as a reversal). This proves the fallback
  //      does not fire merely because the fork is distant.
  // -------------------------------------------------------------------------
  for (final seed in _seeds) {
    test('P3 fallback iff no merge-base [seed=$seed]', () async {
      final rng = Random(seed);

      // (a) Orphan / unrelated histories.
      final repoA = await _newRepo();
      try {
        final mainFiles = _asciiFiles(rng);
        for (final f in mainFiles) {
          await _writeLines(repoA, f, ['main $f']);
        }
        await _commitAll(repoA, 'main root');

        await _git(repoA, ['checkout', '-q', '--orphan', 'stranger']);
        await _git(repoA, ['rm', '-rf', '--quiet', '.']);
        final strangerFiles = [
          for (var i = 0; i < 3 + rng.nextInt(5); i++) 'stranger_$i.txt'
        ];
        for (final f in strangerFiles) {
          await _writeLines(repoA, f, ['stranger $f']);
        }
        await _commitAll(repoA, 'stranger root');

        final descA = 'seed=$seed orphan main=${mainFiles.length} '
            'stranger=${strangerFiles.length}';
        expect(await _hasMergeBase(repoA, 'main', 'stranger'), isFalse,
            reason: 'expected NO merge base  [$descA]');

        final tool = await _toolPaths(repoA,
            base: 'main', head: 'stranger', reason: descA);
        final twoDot = await _nameOnly(repoA, 'main..stranger');
        expect(tool, equals(twoDot),
            reason: 'fallback did not match two-dot oracle  [$descA]');
        expect(tool, contains(strangerFiles.first),
            reason: 'fallback dropped a stranger file  [$descA]');
      } finally {
        await _safeCleanup(repoA);
      }

      // (b) Deep-fork negative control.
      final repoB = await _newRepo();
      try {
        final shared = [
          for (var i = 0; i < 3 + rng.nextInt(4); i++) 'shared_$i.txt'
        ];
        const branchOnly = 'branch_only.txt';
        const upstreamOnly = 'upstream_only.txt';
        for (final f in [branchOnly, upstreamOnly, ...shared]) {
          await _writeLines(repoB, f, [for (var i = 0; i < 8; i++) '$f L$i']);
        }
        await _commitAll(repoB, 'init');

        // DEEP fork: many pre-fork commits on main.
        final deep = 5 + rng.nextInt(4); // 5..8
        for (var c = 0; c < deep; c++) {
          for (final f in _subset(rng, shared)) {
            await _append(repoB, f, 'main-pre-$c');
          }
          await _git(repoB, ['commit', '-q', '-am', 'pre$c']);
        }

        await _git(repoB, ['checkout', '-q', '-b', 'feat']);
        // Branch touches ONLY branch_only.txt.
        final headCommits = 1 + rng.nextInt(3);
        for (var c = 0; c < headCommits; c++) {
          await _append(repoB, branchOnly, 'head-$c');
          await _git(repoB, ['commit', '-q', '-am', 'head$c']);
        }

        // Base advances touching ONLY upstream_only.txt.
        await _git(repoB, ['checkout', '-q', 'main']);
        final baseAdvance = 1 + rng.nextInt(4);
        for (var c = 0; c < baseAdvance; c++) {
          await _append(repoB, upstreamOnly, 'base-$c');
          await _git(repoB, ['commit', '-q', '-am', 'base$c']);
        }
        await _git(repoB, ['checkout', '-q', 'feat']);

        final descB = 'seed=$seed deepFork deep=$deep head=$headCommits '
            'base=$baseAdvance';
        expect(await _hasMergeBase(repoB, 'main', 'feat'), isTrue,
            reason: 'deep fork must still HAVE a merge base  [$descB]');

        final tool =
            await _toolPaths(repoB, base: 'main', head: 'feat', reason: descB);
        final threeDot = await _nameOnly(repoB, 'main...feat');
        final twoDot = await _nameOnly(repoB, 'main..feat');

        expect(tool, equals(threeDot),
            reason: 'deep fork should stay three-dot  [$descB]');
        expect(tool, contains(branchOnly),
            reason: 'branch file missing  [$descB]');
        expect(tool, isNot(contains(upstreamOnly)),
            reason: 'upstream-only file leaked into three-dot  [$descB]');
        // The two-dot oracle DOES include the upstream reversal, proving the
        // tool did not silently fall back to it.
        expect(twoDot, contains(upstreamOnly),
            reason: 'sanity: two-dot must show the upstream reversal  [$descB]');
        expect(tool, isNot(equals(twoDot)),
            reason: 'tool must NOT equal two-dot on a deep fork  [$descB]');
      } finally {
        await _safeCleanup(repoB);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Property 4 — -z numstat fuzz for unusual filenames.
  //
  // Filenames with tabs are impossible on Windows (invalid char), so those
  // are skipped; but unicode, spaces, and parentheses are all valid. Creates
  // several such files in a randomized topology and asserts the reported
  // paths are BYTE-EXACT matches of what was created — no mangling, no
  // truncation at the space/paren, no encoding corruption — by comparing
  // against `git diff --name-only -z base...head` parsed independently here.
  // -------------------------------------------------------------------------
  const fancyPool = <String>[
    'café (final).txt',
    '日本語 report.md',
    'a (b) c.txt',
    'Ω (omega).log',
    'über (v2).md',
    'niño (1).txt',
    'Москва файл.txt',
    'ελληνικά (test).md',
    'naïve (draft).txt',
    'emoji space (x).md',
  ];

  for (final seed in _seeds) {
    test('P4 unicode/space/paren paths byte-exact [seed=$seed]', () async {
      final rng = Random(seed);
      final desc = 'seed=$seed';

      final repo = await _newRepo();
      try {
        await _writeLines(repo, 'seed.txt', ['seed']);
        await _commitAll(repo, 'base');

        await _git(repo, ['checkout', '-q', '-b', 'feat'], reason: desc);

        final pool = [...fancyPool]..shuffle(rng);
        final chosen = pool.take(3 + rng.nextInt(4)).toList(); // 3..6 names
        for (final name in chosen) {
          await _writeLines(repo, name, ['content of $name']);
        }
        await _git(repo, ['add', '-A'], reason: desc);
        await _git(repo, ['commit', '-q', '-m', 'add fancy files'],
            reason: desc);

        final tool =
            await _toolPaths(repo, base: 'main', head: 'feat', reason: desc);

        // Oracle: NUL-split name-only (the only quoting-free format).
        final oracle = await _nameOnly(repo, 'main...feat');

        // Byte-exact: tool set, git oracle set, and the literal Dart strings
        // we created must all coincide.
        expect(tool, equals(oracle),
            reason: 'tool vs git oracle path mismatch  [$desc]');
        for (final name in chosen) {
          expect(oracle, contains(name),
              reason: 'git oracle lost/mangled "$name"  [$desc]');
          expect(tool, contains(name),
              reason: 'tool lost/mangled "$name"  [$desc]');
        }
        expect(tool.length, chosen.length,
            reason: 'unexpected extra/missing paths: $tool  [$desc]');
      } finally {
        await _safeCleanup(repo);
      }
    });
  }
}
