// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Spool gate for local desk PR detail (fetchLocalDeskPrDetail).
//
// The patch body always streams to a disk spool first; the spool's ACTUAL
// byte length then picks the representation. A machine-scale local PR (the
// multi-GB rewrite class) therefore never exists as a Dart String — the
// review UI reads it through DiffDocument.lazyFromSpool with memory bounded
// by the active file. The gate is BYTES, deliberately not numstat churn: a
// few extremely long changed lines report tiny churn while weighing tens of
// MB, and binary churn reads as 0, so any line-count heuristic reopens the
// OOM class. The threshold is injected small so the gate is exercised
// without generating a genuinely huge repo.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/desk_pr_diff.dart';
import 'package:git_desktop/backend/git_result.dart';
import 'package:git_desktop/backend/remote_types.dart';
import 'package:git_desktop/features/diff/diff_document.dart';

import '../support/git_barrier.dart' show GitStartFault;
import '../support/git_faults.dart' show gitFail;
import '../support/scratch_repo.dart';

DeskPr _pr({required String head, required String base}) => DeskPr(
  deskId: 1,
  title: 'spool gate',
  body: '',
  headRef: head,
  baseRef: base,
  state: 'OPEN',
  isDraft: false,
  authorIdentity: 'tester',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScratchRepo repo;

  setUp(() async {
    repo = await ScratchRepo.create(name: 'desk_pr_diff_spool');
    await repo.writeFile('a.txt', 'base a\n');
    await repo.commitAll('base');
    await repo.gitOk(['checkout', '-b', 'feature']);
    final big = StringBuffer();
    for (var i = 0; i < 120; i++) {
      big.writeln('feature line $i');
    }
    await repo.writeFile('a.txt', big.toString());
    await repo.writeFile('b.txt', 'brand new\n');
    await repo.commitAll('feature work');
    await repo.gitOk(['checkout', 'main']);
  });

  tearDown(() => repo.dispose());

  test(
    'above the byte threshold the diff stays spooled, never a String',
    () async {
      final r = await fetchLocalDeskPrDetail(
        repoPath: repo.dir.path,
        pr: _pr(head: 'feature', base: 'main'),
        spoolBytesThreshold: 64, // force the gate with a small repo
      );
      expect(r.ok, isTrue, reason: r.error);
      final detail = r.data!;
      expect(
        detail.diffSpool,
        isNotNull,
        reason:
            'the patch body exceeds the injected byte threshold — and '
            'the gate is BYTES, not line churn, so a few huge lines can '
            'never sneak a machine-scale diff onto the String path',
      );
      expect(
        detail.diff,
        isEmpty,
        reason: 'a spooled detail must not also retain the String',
      );
      expect(detail.rawDiffByFile, isEmpty);
      expect(detail.files.map((f) => f.path), containsAll(['a.txt', 'b.txt']));
      expect(detail.diffSpool!.byteLength, greaterThan(0));

      // The review surface's exact consumption path: lazy doc over the spool,
      // per-file slice for the active pill.
      final doc = await DiffDocument.lazyFromSpool(
        detail.diffSpool!.path,
        documentId: 'test-spool',
      );
      try {
        expect(
          doc.sections.map((s) => s.path),
          containsAll(['a.txt', 'b.txt']),
        );
        final sliceA = doc.rawSliceForPath('a.txt');
        final sliceB = doc.rawSliceForPath('b.txt');
        expect(sliceA, isNotNull);
        expect(sliceA, contains('+feature line 0'));
        expect(
          sliceA,
          isNot(contains('brand new')),
          reason: 'a per-file slice must contain exactly that file',
        );
        expect(sliceB, contains('+brand new'));
        // b.txt is brand-new → structurally blame-ineligible on this backing.
        expect(doc.newFilePaths, contains('b.txt'));
        expect(doc.newFilePaths, isNot(contains('a.txt')));
      } finally {
        doc.dispose();
      }
      await detail.diffSpool!.dispose();
    },
  );

  test(
    'includeDiff: false returns stats only — no body, no spool to orphan',
    () async {
      final r = await fetchLocalDeskPrDetail(
        repoPath: repo.dir.path,
        pr: _pr(head: 'feature', base: 'main'),
        spoolBytesThreshold: 64, // would spool if the body were fetched
        includeDiff: false,
      );
      expect(r.ok, isTrue, reason: r.error);
      final detail = r.data!;
      expect(detail.files.map((f) => f.path), containsAll(['a.txt', 'b.txt']));
      expect(detail.diff, isEmpty);
      expect(
        detail.diffSpool,
        isNull,
        reason:
            'a stats-only caller (DeskPrState.recomputeDiffStats) never '
            'receives a spool it would orphan',
      );
      expect(
        detail.diffLoaded,
        isFalse,
        reason: 'metadata-only: a later full request must still fetch',
      );
    },
  );

  test('a legitimately empty patch loads to a STABLE state', () async {
    // base...base: a genuinely empty range — the numstat and body both
    // succeed with nothing in them. The detail must read as LOADED
    // (diffLoaded) even though there is no content (hasDiff false), or the
    // branches row refetches it on every expand forever.
    final r = await fetchLocalDeskPrDetail(
      repoPath: repo.dir.path,
      pr: _pr(head: 'main', base: 'main'),
    );
    expect(r.ok, isTrue, reason: r.error);
    final detail = r.data!;
    expect(detail.diff, isEmpty);
    expect(detail.diffSpool, isNull);
    expect(detail.hasDiff, isFalse);
    expect(
      detail.diffLoaded,
      isTrue,
      reason: 'empty-but-loaded must be distinguishable from not-loaded',
    );
  });

  test('below the byte threshold the String path is unchanged', () async {
    final r = await fetchLocalDeskPrDetail(
      repoPath: repo.dir.path,
      pr: _pr(head: 'feature', base: 'main'),
    );
    expect(r.ok, isTrue, reason: r.error);
    final detail = r.data!;
    expect(detail.diffSpool, isNull);
    expect(detail.diff, contains('+brand new'));
    expect(detail.rawDiffByFile.keys, containsAll(['a.txt', 'b.txt']));
  });

  test(
    'a failed patch-body fetch is an ERROR, never a silently empty diff',
    () async {
      // Fail exactly the body pass — the spool STREAMS through the
      // Process.start seam (the numstat probe rides the run seam and stays
      // healthy) — the shape of an infrastructure failure arriving after
      // the file list already looked fine.
      final fault = GitStartFault.install(
        predicate: (args) =>
            args.contains('diff') && !args.contains('--numstat'),
        result: () => gitFail(128, 'fatal: unable to read tree object'),
        times: 999,
      );
      late GitResult<PullRequestDetail> r;
      try {
        r = await fetchLocalDeskPrDetail(
          repoPath: repo.dir.path,
          pr: _pr(head: 'feature', base: 'main'),
        );
      } finally {
        fault.dispose();
      }
      expect(
        r.ok,
        isFalse,
        reason:
            'files/comments without the patch would misrepresent an '
            'infrastructure failure as "this PR has no diff"',
      );
      expect(r.error, contains('unable to read tree object'));
    },
  );
}
