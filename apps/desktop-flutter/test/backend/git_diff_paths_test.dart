// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Unit + real-git coverage for the shared `diff --git` header parser.
//
// git_diff_paths.dart is the single source of truth for BOTH the backend
// hunk parser (logos_hunks.dart) and the canonical UI diff parser
// (diff_models.dart), so every edge of git's header grammar is pinned
// here: each side is INDEPENDENTLY raw or C-quoted, raw names may
// contain spaces (git never quotes for spaces alone), and renames repeat
// nothing. The rename-with-spaces cases exist because the shared parser
// replaced a greedy `^diff --git a/(.+) b/(.+)$` regex whose
// last-` b/`-split behavior renames relied on — losing it mis-keyed
// sliceDiffByFile and attached hunk evidence to path fragments.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/git_diff_paths.dart';

void main() {
  group('pathFromDiffGitHeader — unquoted', () {
    test('plain non-rename', () {
      expect(
        pathFromDiffGitHeader('diff --git a/lib/foo.dart b/lib/foo.dart'),
        'lib/foo.dart',
      );
    });

    test('non-rename with spaces (repeated-path scan)', () {
      expect(
        pathFromDiffGitHeader(
            'diff --git a/has space in it.txt b/has space in it.txt'),
        'has space in it.txt',
      );
    });

    test('non-rename containing a literal " b/" in the name', () {
      expect(
        pathFromDiffGitHeader('diff --git a/x b/y.txt b/x b/y.txt'),
        'x b/y.txt',
      );
    });

    test('rename without spaces', () {
      expect(
        pathFromDiffGitHeader('diff --git a/old.txt b/new.txt'),
        'new.txt',
      );
    });

    test('rename with spaces on both sides (old-regex parity)', () {
      expect(
        pathFromDiffGitHeader('diff --git a/old name.txt b/new name.txt'),
        'new name.txt',
      );
    });

    test('rename with space only in the new name', () {
      expect(
        pathFromDiffGitHeader('diff --git a/old.txt b/new name.txt'),
        'new name.txt',
      );
    });
  });

  group('pathFromDiffGitHeader — quoted', () {
    test('both sides quoted (unicode)', () {
      // "café.txt" — é C-quoted as \303\251 per UTF-8 byte.
      expect(
        pathFromDiffGitHeader(
            r'diff --git "a/caf\303\251.txt" "b/caf\303\251.txt"'),
        'café.txt',
      );
    });

    test('mixed: raw a-side, quoted b-side (rename gaining unicode)', () {
      expect(
        pathFromDiffGitHeader(r'diff --git a/plain.txt "b/caf\303\251.txt"'),
        'café.txt',
      );
    });

    test('mixed: quoted a-side, raw b-side (rename losing unicode)', () {
      expect(
        pathFromDiffGitHeader(r'diff --git "a/caf\303\251.txt" b/plain.txt'),
        'plain.txt',
      );
    });

    test('mixed: quoted a-side, raw b-side with spaces', () {
      expect(
        pathFromDiffGitHeader(
            r'diff --git "a/caf\303\251.txt" b/new name.txt'),
        'new name.txt',
      );
    });

    test('quoted with escaped quote inside', () {
      expect(
        pathFromDiffGitHeader(r'diff --git "a/we\"ird.txt" "b/we\"ird.txt"'),
        'we"ird.txt',
      );
    });
  });

  group('pathFromDiffGitHeader — degenerate', () {
    test('malformed header returns null', () {
      expect(pathFromDiffGitHeader('diff --git'), isNull);
      expect(pathFromDiffGitHeader('not a header'), isNull);
    });
  });

  group('real git ground truth', () {
    test('unquoted rename with spaces parses to the real new name',
        () async {
      final dir = await Directory.systemTemp.createTemp('gdp_rename_');
      try {
        Future<ProcessResult> git(List<String> args) =>
            Process.run('git', args, workingDirectory: dir.path);
        await git(['init', '-q', '-b', 'main']);
        await git(['config', 'user.name', 'test']);
        await git(['config', 'user.email', 'test@local']);
        final f = File('${dir.path}${Platform.pathSeparator}old name.txt');
        await f.writeAsString('one\ntwo\nthree\nfour\nfive\n');
        await git(['add', '.']);
        await git(['commit', '-q', '-m', 'add']);
        await git(['mv', 'old name.txt', 'new name.txt']);
        final diff = await git(['diff', '--cached', '-M', 'HEAD']);
        final raw = diff.stdout.toString();
        final header = raw
            .split('\n')
            .firstWhere((l) => l.startsWith('diff --git'), orElse: () => '');
        expect(header, isNotEmpty,
            reason: 'expected a diff --git header in:\n$raw');
        // Git does not quote spaces — pin the precondition this whole
        // test exists for, then the parse.
        expect(header.contains('"'), isFalse,
            reason: 'git unexpectedly quoted a space-only rename: $header');
        expect(pathFromDiffGitHeader(header), 'new name.txt');
      } finally {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // Windows handle-release race — best-effort cleanup only.
        }
      }
    });
  });
}
