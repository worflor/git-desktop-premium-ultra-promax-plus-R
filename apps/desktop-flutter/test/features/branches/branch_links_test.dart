// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Unit tests for the pure branch cross-link resolver and the desk-aware
// delete-failure classifier surfaced on the branches lens. Both live in
// branch_ops.dart — pure functions (no BuildContext / no git), so they're
// exercised directly without building a single widget. The last group
// closes the gap a code review flagged: unit coverage on the classifier
// alone doesn't prove it understands REAL git stderr, so it drives an
// actual `git worktree add` + failed delete through a temp repo.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git.dart';
import 'package:git_desktop/features/branches/branch_ops.dart';

WorktreeData _desk(String branch, {String path = ''}) => WorktreeData(
      path: path.isEmpty ? 'C:/repo/.manifold/worktrees/$branch' : path,
      head: 'deadbeef',
      branch: branch,
      isMain: false,
      isDetached: false,
      isLocked: false,
    );

DeskPr _pr(
  String headRef, {
  List<int> linkedIssues = const [],
  List<int> linkedRemoteIssues = const [],
  String state = 'OPEN',
  bool isDraft = true,
}) =>
    DeskPr(
      deskId: 7,
      title: headRef,
      body: '',
      headRef: headRef,
      baseRef: 'main',
      state: state,
      isDraft: isDraft,
      authorIdentity: 'tester',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
      linkedIssues: linkedIssues,
      linkedRemoteIssues: linkedRemoteIssues,
    );

void main() {
  group('resolveBranchLinks', () {
    test('no desk, no PR → empty, hasAny false', () {
      final links = resolveBranchLinks(
        'feature/x',
        desks: const [],
        deskPrsByBranch: const {},
      );
      expect(links.desk, isNull);
      expect(links.deskPr, isNull);
      expect(links.issueCount, 0);
      expect(links.hasAny, isFalse);
    });

    test('matches the desk holding the branch', () {
      final links = resolveBranchLinks(
        'feature/x',
        desks: [_desk('other'), _desk('feature/x')],
        deskPrsByBranch: const {},
      );
      expect(links.desk, isNotNull);
      expect(links.desk!.branch, 'feature/x');
      expect(links.hasAny, isTrue);
    });

    test('ignores a desk with an empty path (placeholder)', () {
      const placeholder = WorktreeData(
        path: '',
        head: '',
        branch: 'feature/x',
        isMain: false,
        isDetached: false,
        isLocked: false,
      );
      final links = resolveBranchLinks(
        'feature/x',
        desks: const [placeholder],
        deskPrsByBranch: const {},
      );
      expect(links.desk, isNull);
    });

    test('folds local + remote linked issue counts on the PR', () {
      final pr = _pr(
        'feature/x',
        linkedIssues: [1, 2],
        linkedRemoteIssues: [42],
      );
      final links = resolveBranchLinks(
        'feature/x',
        desks: const [],
        deskPrsByBranch: {'feature/x': pr},
      );
      expect(links.deskPr, isNotNull);
      expect(links.issueCount, 3);
      expect(links.hasAny, isTrue);
    });

    test('PR with no issues → issueCount 0 but hasAny (PR present)', () {
      final links = resolveBranchLinks(
        'feature/x',
        desks: const [],
        deskPrsByBranch: {'feature/x': _pr('feature/x')},
      );
      expect(links.issueCount, 0);
      expect(links.hasAny, isTrue);
    });
  });

  group('isWorktreeHoldsBranchError', () {
    test('detects git "already checked out at" phrasing', () {
      const raw =
          "error: Cannot delete branch 'feature/x' checked out at "
          "'C:/repo/.manifold/worktrees/feature/x'";
      expect(isWorktreeHoldsBranchError(raw), isTrue);
    });

    test('case-insensitive', () {
      expect(isWorktreeHoldsBranchError('CHECKED OUT AT /tmp/wt'), isTrue);
    });

    test('detects git 2.52+ "used by worktree at" phrasing', () {
      const raw =
          "error: cannot delete branch 'feature/x' used by worktree at "
          "'C:/repo/.manifold/worktrees/feature/x'";
      expect(isWorktreeHoldsBranchError(raw), isTrue);
    });

    test('unrelated errors do not match', () {
      expect(
        isWorktreeHoldsBranchError(
            "error: branch 'feature/x' not fully merged"),
        isFalse,
      );
      expect(isWorktreeHoldsBranchError(''), isFalse);
    });
  });

  group('classifyBranchDeleteFailure', () {
    test('not-fully-merged stderr on a safe delete → DeleteNotMerged', () {
      final outcome = classifyBranchDeleteFailure(
        "error: The branch 'feature/x' is not fully merged.\n"
        "hint: If you are sure you want to delete it, run 'git branch -D "
        "feature/x'.",
        branch: 'feature/x',
        desks: const [],
      );
      expect(outcome, isA<DeleteNotMerged>());
    });

    test('not-fully-merged stderr on a forced delete → DeleteFailed', () {
      // A force delete (-D) doesn't run git's merged check, so if this
      // text somehow still shows up the row shouldn't loop back into
      // "offer force" — it already tried that.
      final outcome = classifyBranchDeleteFailure(
        "error: The branch 'feature/x' is not fully merged.",
        branch: 'feature/x',
        desks: const [],
        force: true,
      );
      expect(outcome, isA<DeleteFailed>());
      expect(
        (outcome as DeleteFailed).message,
        "The branch 'feature/x' is not fully merged.",
      );
    });

    test('checked-out-at stderr with a matching desk → DeleteHeldByDesk',
        () {
      final desk = _desk('feature/x');
      final outcome = classifyBranchDeleteFailure(
        "error: Cannot delete branch 'feature/x' checked out at "
        "'${desk.path}'",
        branch: 'feature/x',
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.branch, 'feature/x');
    });

    test('checked-out-at stderr with NO matching desk → DeleteFailed', () {
      final outcome = classifyBranchDeleteFailure(
        "error: Cannot delete branch 'feature/x' checked out at "
        "'C:/repo/.manifold/worktrees/feature/x'",
        branch: 'feature/x',
        desks: const [],
      );
      expect(outcome, isA<DeleteFailed>());
    });

    test('arbitrary fatal error → DeleteFailed, humanized', () {
      final outcome = classifyBranchDeleteFailure(
        'error: unable to resolve HEAD',
        branch: 'feature/x',
        desks: const [],
      );
      expect(outcome, isA<DeleteFailed>());
      expect((outcome as DeleteFailed).message, 'unable to resolve HEAD');
    });

    test(
        'stderr path wins over name matching when the desk branch is '
        'spelled differently than the classifier receives', () {
      // The classifier is called with 'feature/x' (say, the branch row the
      // user clicked), but the desk list's branch field disagrees in
      // spelling (a rename mid-flight, a different ref rendering — doesn't
      // matter why). Name matching would miss this desk entirely; the
      // stderr's quoted path still identifies it exactly.
      final desk = _desk('feature-x-renamed',
          path: 'C:/repo/.manifold/worktrees/feature/x');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        "'${desk.path}'",
        branch: 'feature/x',
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.branch, 'feature-x-renamed');
    });

    test(
        'stderr path matches no desk, branch name matches one → '
        'name-match fallback still fires', () {
      final desk = _desk('feature/x',
          path: 'C:/repo/.manifold/worktrees/feature/x');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        "'C:/some/other/unrelated/path'",
        branch: 'feature/x',
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk.path);
    });

    test(
        'path match tolerates mixed separators between stderr and the '
        'desk list', () {
      final desk = _desk('feature/x', path: r'C:\x\desk');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        "'C:/x/desk'",
        branch: 'feature/x',
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk.path);
    });
  });

  group('normalizeWorktreePath', () {
    test('folds separators and trailing slashes regardless of platform', () {
      expect(normalizeWorktreePath(r'C:\x\desk\', caseFold: false),
          'C:/x/desk');
      expect(normalizeWorktreePath('C:/x/desk', caseFold: false), 'C:/x/desk');
    });

    test('caseFold: true collapses case (Windows/macOS semantics)', () {
      expect(normalizeWorktreePath('C:/X/Desk', caseFold: true),
          normalizeWorktreePath(r'c:\x\desk', caseFold: true));
    });

    test(
        'caseFold: false keeps case-distinct paths distinct '
        '(Linux semantics — two desks differing only by case are two desks)',
        () {
      expect(normalizeWorktreePath('/home/u/Desk', caseFold: false),
          isNot(normalizeWorktreePath('/home/u/desk', caseFold: false)));
    });

    test('legitimate leading/trailing whitespace is path identity, kept', () {
      expect(normalizeWorktreePath('/x/desk ', caseFold: false),
          isNot(normalizeWorktreePath('/x/desk', caseFold: false)));
      expect(normalizeWorktreePath(' /x/desk', caseFold: false),
          isNot(normalizeWorktreePath('/x/desk', caseFold: false)));
    });

    test('default fold follows the platform', () {
      final folded = normalizeWorktreePath('A/B') == normalizeWorktreePath('a/b');
      expect(folded, Platform.isWindows || Platform.isMacOS);
    });
  });

  group('apostrophe/unicode/space path fixtures (pinned, from real git)', () {
    // Pinned samples of ACTUAL stderr git 2.52.0 (windows) rendered on this
    // machine for `git branch -d` when a worktree holding the branch lives
    // at a path with an apostrophe, unicode, parens, or an ampersand.
    // Empirically observed: git does NOT shell-escape an embedded single
    // quote in the path — it splices the raw path between two literal `'`
    // characters, so a naive `[^']*` capture truncates at the FIRST
    // apostrophe inside the path itself. These fixtures pin the exact
    // rendering so a regression in the extractor's regex is caught even
    // without spawning git.
    test('apostrophe inside the worktree dir name is not truncated', () {
      const desk = "C:/repo/.manifold/worktrees/o'brien desk";
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        "'$desk'",
        branch: 'feature/x',
        desks: [_desk('feature/x', path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test('two embedded apostrophes in the same path', () {
      const desk = "C:/repo/o'brien's desk";
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        "'$desk'",
        branch: 'feature/x',
        desks: [_desk('feature/x', path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test('apostrophe in the BRANCH NAME as well as the path', () {
      // Observed verbatim: git renders the branch name's own apostrophe the
      // same un-escaped way inside its surrounding quotes.
      const desk = 'C:/repo/apos-branch-desk';
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'o'brien-branch' used by worktree at "
        "'$desk'",
        branch: "o'brien-branch",
        desks: [_desk("o'brien-branch", path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test('unicode path (CJK + accented Latin) renders and matches intact',
        () {
      const desk = 'C:/repo/.manifold/worktrees/日本語é';
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/y' used by worktree at "
        "'$desk'",
        branch: 'feature/y',
        desks: [_desk('feature/y', path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test('parens in path do not confuse the extractor', () {
      const desk = 'C:/repo/.manifold/worktrees/a(b)c';
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/z' used by worktree at "
        "'$desk'",
        branch: 'feature/z',
        desks: [_desk('feature/z', path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test('ampersand in path does not confuse the extractor', () {
      const desk = 'C:/repo/.manifold/worktrees/a&b';
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/w' used by worktree at "
        "'$desk'",
        branch: 'feature/w',
        desks: [_desk('feature/w', path: desk)],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk);
    });

    test(
        'held phrasing present but with no quoted path at all → path '
        'extraction yields null, falls back to name match', () {
      final desk = _desk('feature/x', path: 'C:/repo/worktrees/feature-x');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        'unknown location',
        branch: 'feature/x',
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.path, desk.path);
    });

    test(
        'held phrasing, no quoted path, AND no name-fallback match → '
        'DeleteFailed (never silently drops to raw stderr wrongly)', () {
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feature/x' used by worktree at "
        'unknown location',
        branch: 'feature/x',
        desks: const [],
      );
      expect(outcome, isA<DeleteFailed>());
    });
  });

  group('hostile branch names', () {
    test('deeply nested slashes', () {
      const branch = 'feature/x/y/z/deep';
      final desk = _desk(branch, path: 'C:/repo/worktrees/deep');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'",
        branch: branch,
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.branch, branch);
    });

    test('dotted release-style branch name', () {
      const branch = 'release/v1.2.3';
      final desk = _desk(branch);
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'",
        branch: branch,
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
    });

    test('unicode branch name', () {
      const branch = 'feature/日本語-é';
      final desk = _desk(branch);
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'",
        branch: branch,
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
    });

    test('100+ character branch name', () {
      final branch = 'feature/${'x' * 140}';
      final desk = _desk(branch);
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'",
        branch: branch,
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
      expect((outcome as DeleteHeldByDesk).desk.branch, branch);
    });

    test(
        'prefix-overlapping branch names: deleting "feat" must not match a '
        'desk on "feat-2"', () {
      final other = _desk('feat-2', path: 'C:/repo/worktrees/feat-2');
      final outcome = classifyBranchDeleteFailure(
        "error: The branch 'feat' is not fully merged.",
        branch: 'feat',
        desks: [other],
      );
      // No held phrasing at all here — not-fully-merged always wins on a
      // safe delete regardless of desks — but the name-fallback dimension
      // is exercised directly below with a held-phrasing stderr.
      expect(outcome, isA<DeleteNotMerged>());
    });

    test(
        'prefix-overlapping branch names under held phrasing: "feat" must '
        'not resolve to the desk on "feat-2" via name fallback or path', () {
      final other = _desk('feat-2', path: 'C:/repo/worktrees/feat-2');
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch 'feat' used by worktree at "
        "'C:/repo/worktrees/feat-solo'",
        branch: 'feat',
        desks: [other],
      );
      // stderr path matches no desk, and no desk is named exactly 'feat' —
      // 'feat-2' must not be picked by any prefix/substring shortcut.
      expect(outcome, isA<DeleteFailed>());
    });

    test(
        'branch name resembling the held-phrasing template (hyphenated, no '
        'spaces) does not falsely self-trigger the phrase sniff', () {
      const branch = 'checked-out-at-service';
      final outcome = classifyBranchDeleteFailure(
        "error: The branch '$branch' is not fully merged.",
        branch: branch,
        desks: const [],
      );
      expect(outcome, isA<DeleteNotMerged>());
    });

    test(
        'branch name resembling "not fully merged" (hyphenated, no spaces) '
        'does not falsely trigger DeleteNotMerged', () {
      const branch = 'not-fully-merged-fix';
      final desk = _desk(branch);
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'",
        branch: branch,
        desks: [desk],
      );
      expect(outcome, isA<DeleteHeldByDesk>());
    });

    test(
        'branch literally named "feature" containing "not fully merged" as '
        'a substring the moment it is embedded next to unrelated hint text '
        'does not survive a held-phrasing stderr', () {
      // Realistic-shaped adversarial stderr: a hint sentence that happens
      // to contain the literal substring "not fully merged" while the
      // actual failure is the desk-held one (force delete, so the
      // not-merged sniff is disabled by [force] regardless).
      const branch = 'feature/x';
      final desk = _desk(branch);
      final outcome = classifyBranchDeleteFailure(
        "error: cannot delete branch '$branch' used by worktree at "
        "'${desk.path}'\n"
        'hint: this row was previously not fully merged before the desk '
        'picked it up',
        branch: branch,
        desks: [desk],
        force: true,
      );
      expect(outcome, isA<DeleteHeldByDesk>());
    });
  });

  group('phrasing-mutation robustness', () {
    const heldTemplates = [
      "error: Cannot delete branch 'feature/x' checked out at '{PATH}'",
      "error: cannot delete branch 'feature/x' used by worktree at '{PATH}'",
    ];

    test('all phrasing mutations still resolve to the right desk', () {
      final desk = _desk('feature/x');
      for (final template in heldTemplates) {
        final base = template.replaceAll('{PATH}', desk.path);
        final mutations = <String, String>{
          'as-is': base,
          'fatal: prefix instead of error:':
              base.replaceFirst('error:', 'fatal:'),
          'leading whitespace': '   $base',
          'trailing hint line': "$base\nhint: use --force to override",
          'CRLF line endings': '$base\r\n',
          'CRLF with trailing hint':
              "$base\r\nhint: use --force to override\r\n",
          'doubled (same message twice, LF-joined)': '$base\n$base',
          'doubled (-d attempt then -D retry, distinct wrapper text)':
              "$base\n$base".replaceFirst(
            'used by worktree at',
            'STILL used by worktree at',
          ),
        };
        for (final entry in mutations.entries) {
          final outcome = classifyBranchDeleteFailure(
            entry.value,
            branch: 'feature/x',
            desks: [desk],
          );
          expect(
            outcome,
            isA<DeleteHeldByDesk>(),
            reason: 'template=$template mutation=${entry.key} '
                'stderr=${entry.value}',
          );
          expect(
            (outcome as DeleteHeldByDesk).desk.path,
            desk.path,
            reason: 'template=$template mutation=${entry.key}',
          );
        }
      }
    });

    test(
        'negative space: stderrs that merely MENTION a worktree from other '
        'git commands must NOT classify as held', () {
      const unrelated = [
        // git worktree prune / list chatter, git status hints, etc. — none
        // of these use the exact "checked out at '<path>'" / "used by
        // worktree at '<path>'" template this classifier keys on.
        "fatal: 'C:/repo/wt' is already a working tree",
        "warning: 'prune' encountered problems while pruning worktrees",
        'Removing worktrees/stale: gitdir file points to non-existent '
            'location',
        "hint: If you meant to create a worktree, run 'git worktree add'.",
        'On branch feature/x\n'
            'Your branch is checked out in another worktree, '
            'nothing to commit',
        "error: unable to lock ref 'refs/heads/feature/x': "
            'unable to resolve reference',
      ];
      for (final stderr in unrelated) {
        final outcome = classifyBranchDeleteFailure(
          stderr,
          branch: 'feature/x',
          desks: [_desk('feature/x')],
        );
        expect(
          outcome,
          isNot(isA<DeleteHeldByDesk>()),
          reason: 'stderr=$stderr',
        );
      }
    });
  });

  group('classifyBranchDeleteFailure decision table (exhaustive)', () {
    // Sealed-type contract, enumerated: {force} x {not-merged text} x
    // {held phrasing} x {stderr path match} x {name-fallback match}.
    // heldPhrasing: 'old' | 'new' | 'none'.
    // pathMatch:   'desk' (quoted path equals a desk's path) |
    //              'miss' (quoted path present but matches no desk) |
    //              'absent' (held phrasing present, no quotes follow).
    const deskPathMatchPath = 'C:/repo/worktrees/path-match';
    const deskNameMatchBranch = 'name-match-target';
    final deskPathMatch =
        _desk('other-branch-not-the-target', path: deskPathMatchPath);
    final deskNameMatch = _desk(deskNameMatchBranch,
        path: 'C:/repo/worktrees/name-match');

    String buildStderr({
      required bool notMerged,
      required String heldPhrasing,
      required String pathMatch,
    }) {
      final lines = <String>[];
      if (notMerged) {
        lines.add(
            "error: The branch '$deskNameMatchBranch' is not fully merged.");
      }
      if (heldPhrasing != 'none') {
        final phraseWords =
            heldPhrasing == 'old' ? 'checked out at' : 'used by worktree at';
        final tail = switch (pathMatch) {
          'desk' => "'$deskPathMatchPath'",
          'miss' => "'C:/repo/worktrees/no-such-path'",
          _ => 'unknown location', // 'absent'
        };
        lines.add(
            "error: cannot delete branch '$deskNameMatchBranch' $phraseWords $tail");
      }
      if (lines.isEmpty) {
        lines.add('error: unable to resolve HEAD');
      }
      return lines.join('\n');
    }

    for (final force in [false, true]) {
      for (final notMerged in [false, true]) {
        for (final heldPhrasing in ['old', 'new', 'none']) {
          for (final pathMatch in ['desk', 'miss', 'absent']) {
            for (final nameFallback in [false, true]) {
              final desks = <WorktreeData>[
                if (pathMatch == 'desk') deskPathMatch,
                if (nameFallback) deskNameMatch,
              ];
              final stderr = buildStderr(
                notMerged: notMerged,
                heldPhrasing: heldPhrasing,
                pathMatch: pathMatch,
              );
              final label = 'force=$force notMerged=$notMerged '
                  'heldPhrasing=$heldPhrasing pathMatch=$pathMatch '
                  'nameFallback=$nameFallback';

              test(label, () {
                final outcome = classifyBranchDeleteFailure(
                  stderr,
                  branch: deskNameMatchBranch,
                  desks: desks,
                  force: force,
                );

                if (!force && notMerged) {
                  expect(outcome, isA<DeleteNotMerged>(), reason: label);
                  return;
                }
                if (heldPhrasing != 'none') {
                  if (pathMatch == 'desk') {
                    expect(outcome, isA<DeleteHeldByDesk>(), reason: label);
                    expect(
                      (outcome as DeleteHeldByDesk).desk.path,
                      deskPathMatchPath,
                      reason: label,
                    );
                    return;
                  }
                  if (nameFallback) {
                    expect(outcome, isA<DeleteHeldByDesk>(), reason: label);
                    expect(
                      (outcome as DeleteHeldByDesk).desk.branch,
                      deskNameMatchBranch,
                      reason: label,
                    );
                    return;
                  }
                  expect(outcome, isA<DeleteFailed>(), reason: label);
                  return;
                }
                expect(outcome, isA<DeleteFailed>(), reason: label);
              });
            }
          }
        }
      }
    }
  });

  group('normalizeWorktreePath properties (seeded, ~200 cases)', () {
    // Fixed literal seed — never Date.now() — so failures are 100%
    // reproducible from the printed offending input alone.
    final rng = Random(1234567);
    const segVocab = [
      'repo',
      'DESK',
      'Worktrees',
      'a b',
      'C:',
      'x',
      'ünïcödé',
      '日本語',
      'é',
      'feature.branch',
      '..',
      '.',
      'très-bien',
      '_hidden',
      '1234',
      "o'brien",
      'a&b',
      'a(b)c',
    ];
    const seps = ['/', r'\', '//', r'\\', r'/\', r'\/'];

    String randomPathLike(Random r) {
      final segCount = 1 + r.nextInt(5);
      final segs =
          List.generate(segCount, (_) => segVocab[r.nextInt(segVocab.length)]);
      final sep = seps[r.nextInt(seps.length)];
      return segs.join(sep);
    }

    test('idempotence: n(n(x)) == n(x) for both fold settings', () {
      for (var i = 0; i < 200; i++) {
        final input = randomPathLike(rng);
        for (final fold in [true, false]) {
          final once = normalizeWorktreePath(input, caseFold: fold);
          final twice = normalizeWorktreePath(once, caseFold: fold);
          expect(twice, once,
              reason: 'input=$input fold=$fold once=$once twice=$twice');
        }
      }
    });

    test('fold-consistency: caseFold:true is invariant to input case', () {
      for (var i = 0; i < 200; i++) {
        final input = randomPathLike(rng);
        final lower = normalizeWorktreePath(input.toLowerCase(),
            caseFold: true);
        final upper = normalizeWorktreePath(input.toUpperCase(),
            caseFold: true);
        final asIs = normalizeWorktreePath(input, caseFold: true);
        expect(lower, upper, reason: 'input=$input');
        expect(lower, asIs, reason: 'input=$input');
      }
    });

    test(
        'separator invariance: any \\ <-> / mix of the same segments, at '
        'the same separator run-length, normalizes equal', () {
      // Deliberately single-char seps only ('/', '\\') — normalizeWorktreePath
      // maps each backslash to a forward slash 1:1 but never COLLAPSES
      // repeated separators, so a run of two slashes and a run of one
      // slash are genuinely different paths, not an invariance violation.
      // Varying the CHARACTER at each gap while holding run-length at 1 is
      // the actual invariance the doc comment on normalizeWorktreePath
      // claims (backslashes folded to forward slashes).
      const singleCharSeps = ['/', r'\'];
      for (var i = 0; i < 200; i++) {
        final segCount = 2 + rng.nextInt(4);
        final segs = List.generate(
            segCount, (_) => segVocab[rng.nextInt(segVocab.length)]);
        // Build several variants: each gap between segments independently
        // picks '/' or '\', all with run-length exactly 1.
        final variants = <String>{};
        for (var v = 0; v < 4; v++) {
          final buf = StringBuffer(segs.first);
          for (var g = 1; g < segs.length; g++) {
            buf.write(singleCharSeps[rng.nextInt(singleCharSeps.length)]);
            buf.write(segs[g]);
          }
          variants.add(normalizeWorktreePath(buf.toString(), caseFold: false));
        }
        expect(variants.length, 1,
            reason: 'segs=$segs variants=$variants');
      }
    });

    test(
        'run-length is NOT collapsed: single vs doubled separator is a '
        'genuinely distinct path, not a false invariance', () {
      // Documents the boundary of the invariance above so a future reader
      // (or a future property test) doesn't reintroduce the same false
      // assumption that bit the separator-invariance test during authoring.
      expect(normalizeWorktreePath('a/b', caseFold: false),
          isNot(normalizeWorktreePath('a//b', caseFold: false)));
      expect(normalizeWorktreePath(r'a\b', caseFold: false),
          normalizeWorktreePath('a/b', caseFold: false));
      expect(normalizeWorktreePath(r'a\\b', caseFold: false),
          normalizeWorktreePath('a//b', caseFold: false));
    });

    test(
        'no-trim identity: leading/trailing space changes identity, never '
        'silently collapses to the unpadded path', () {
      for (var i = 0; i < 200; i++) {
        final input = randomPathLike(rng);
        if (input.startsWith(' ') || input.endsWith(' ')) continue;
        final unpadded = normalizeWorktreePath(input, caseFold: false);
        final leadingPadded =
            normalizeWorktreePath(' $input', caseFold: false);
        final trailingPadded =
            normalizeWorktreePath('$input ', caseFold: false);
        expect(leadingPadded, isNot(unpadded), reason: 'input=$input');
        expect(trailingPadded, isNot(unpadded), reason: 'input=$input');
      }
    });
  });

  group('classifyBranchDeleteFailure (real git)', () {
    // See desk_pr_store_test.dart's docstring: Windows briefly holds file
    // handles after spawned git processes exit, so cleanup swallows
    // FileSystemException rather than failing an otherwise-passing test.
    Future<void> safeCleanup(Directory dir) async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Ignored — see above.
      }
    }

    test(
        'a real worktree holding the branch → DeleteHeldByDesk names it, '
        'matched by the real stderr path among several desks', () async {
      final repo = await Directory.systemTemp.createTemp('branch_ops_test_');
      try {
        await Process.run('git', ['init', '-q', '-b', 'main'],
            workingDirectory: repo.path);
        await Process.run('git', ['config', 'user.name', 'test'],
            workingDirectory: repo.path);
        await Process.run('git', ['config', 'user.email', 'test@local'],
            workingDirectory: repo.path);
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: repo.path);
        await Process.run('git', ['branch', 'feature/x'],
            workingDirectory: repo.path);
        await Process.run('git', ['branch', 'feature/y'],
            workingDirectory: repo.path);

        final deskDir =
            await Directory.systemTemp.createTemp('branch_ops_desk_');
        // A second desk on a DIFFERENT branch, so a name-only matcher would
        // have two candidates to potentially confuse and the test proves
        // the real one gets picked by its stderr-quoted path, not by luck
        // of being the only desk in the list.
        final otherDeskDir =
            await Directory.systemTemp.createTemp('branch_ops_desk2_');
        try {
          final add = await Process.run(
            'git',
            ['worktree', 'add', deskDir.path, 'feature/x'],
            workingDirectory: repo.path,
          );
          expect(add.exitCode, 0, reason: add.stderr.toString());
          final addOther = await Process.run(
            'git',
            ['worktree', 'add', otherDeskDir.path, 'feature/y'],
            workingDirectory: repo.path,
          );
          expect(addOther.exitCode, 0, reason: addOther.stderr.toString());

          final desksResult = await listWorktrees(repo.path);
          expect(desksResult.ok, isTrue);
          final desks = desksResult.data!;
          expect(desks.any((d) => d.branch == 'feature/x'), isTrue);
          expect(desks.any((d) => d.branch == 'feature/y'), isTrue);

          // The real deleteBranch path: git refuses because a worktree has
          // 'feature/x' checked out. Feed its actual stderr — not a
          // fixture we wrote by hand — through the classifier.
          final r = await deleteBranch(repo.path, 'feature/x');
          expect(r.ok, isFalse);
          final stderrText = r.error ?? '';

          // Confirms the fix's premise empirically rather than assuming it:
          // git really does quote the desk path in this stderr, and the
          // path really does match the desk list entry by exact string
          // equality on this machine (both render forward slashes).
          final expectedPath =
              desks.firstWhere((d) => d.branch == 'feature/x').path;
          expect(stderrText, contains("'$expectedPath'"));

          final outcome = classifyBranchDeleteFailure(
            stderrText,
            branch: 'feature/x',
            desks: desks,
          );
          expect(outcome, isA<DeleteHeldByDesk>());
          expect((outcome as DeleteHeldByDesk).desk.path, expectedPath);
          expect(outcome.desk.branch, 'feature/x');
        } finally {
          await safeCleanup(otherDeskDir);
          await safeCleanup(deskDir);
        }
      } finally {
        await safeCleanup(repo);
      }
    });

    test(
        'a real worktree at a path containing an apostrophe → real git '
        "stderr, real deleteBranch, extractor doesn't truncate at the "
        'embedded quote', () async {
      final repo = await Directory.systemTemp.createTemp('branch_ops_apos_');
      try {
        await Process.run('git', ['init', '-q', '-b', 'main'],
            workingDirectory: repo.path);
        await Process.run('git', ['config', 'user.name', 'test'],
            workingDirectory: repo.path);
        await Process.run('git', ['config', 'user.email', 'test@local'],
            workingDirectory: repo.path);
        await Process.run('git', ['commit', '--allow-empty', '-m', 'root'],
            workingDirectory: repo.path);
        await Process.run('git', ['branch', 'feature/x'],
            workingDirectory: repo.path);

        final basketDir =
            await Directory.systemTemp.createTemp('branch_ops_apos_base_');
        // NTFS/Win32 legally permits an apostrophe in a directory name —
        // this is the exact shape the apostrophe hunt reproduced by hand.
        final deskDir = Directory("${basketDir.path}${Platform.pathSeparator}"
            "o'brien desk");
        try {
          final add = await Process.run(
            'git',
            ['worktree', 'add', deskDir.path, 'feature/x'],
            workingDirectory: repo.path,
          );
          expect(add.exitCode, 0, reason: add.stderr.toString());

          final desksResult = await listWorktrees(repo.path);
          expect(desksResult.ok, isTrue);
          final desks = desksResult.data!;
          final desk = desks.firstWhere((d) => d.branch == 'feature/x');
          expect(desk.path, contains("o'brien"));

          final r = await deleteBranch(repo.path, 'feature/x');
          expect(r.ok, isFalse);
          final stderrText = r.error ?? '';
          // Pin the real observed rendering: git splices the apostrophe
          // in raw, unescaped.
          expect(stderrText, contains("at '${desk.path}'"));

          final outcome = classifyBranchDeleteFailure(
            stderrText,
            branch: 'feature/x',
            desks: desks,
          );
          expect(outcome, isA<DeleteHeldByDesk>());
          expect(
            (outcome as DeleteHeldByDesk).desk.path,
            desk.path,
            reason: 'extractor must capture the FULL path including the '
                'embedded apostrophe, not truncate at it; got stderr: '
                '$stderrText',
          );
        } finally {
          await safeCleanup(basketDir);
        }
      } finally {
        await safeCleanup(repo);
      }
    });
  });
}
