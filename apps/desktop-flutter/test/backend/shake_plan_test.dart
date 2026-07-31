// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// shake_plan_test.dart — the whole-codebase sweep, against real repositories.
//
// The claims worth testing here are not "the function returns a list". They
// are the guarantees that make a sweep mean anything:
//
//   * coverage is over the TREE, so code history never touched is reachable
//     (the entire reason this exists rather than a loop over commits);
//   * exclusions are DECLARED, so reported coverage is not a lie;
//   * "already examined" is decided by CONTENT, so editing a file re-opens it
//     and touching its mtime does not;
//   * the sweep reaches a FIXPOINT, so repeated runs converge instead of
//     re-doing work or quietly stopping short.
//
// Each test states which of those it is defending.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/shake_ledger.dart';
import 'package:git_desktop/backend/shake_plan.dart';

import '../support/scratch_repo.dart';

/// A repo whose shape is chosen to expose the coverage question:
/// `quiet.dart` is written once and never touched again, `busy.dart` is
/// rewritten repeatedly, and there is a generated file and a binary beside
/// them.
Future<ScratchRepo> buildRepo() async {
  final repo = await ScratchRepo.create(name: 'shake');
  await repo.writeFile('lib/quiet.dart', 'int quiet() => 1;\n');
  await repo.writeFile('lib/busy.dart', 'int busy() => 0;\n');
  await repo.writeFile('lib/model.g.dart', '// GENERATED\nint g() => 0;\n');
  await repo.writeFile('lib/other/side.dart', 'int side() => 2;\n');
  await repo.writeFile('README.md', 'docs\n');
  await File('${repo.dir.path}${Platform.pathSeparator}logo.png')
      .writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]);
  await repo.commitAll('seed');

  for (var i = 1; i <= 3; i++) {
    await repo.writeFile('lib/busy.dart', 'int busy() => $i;\n');
    await repo.commitAll('churn $i');
  }
  return repo;
}

Future<ShakePlan> planFor(ScratchRepo repo, ShakeLedger ledger) async {
  final r = await planShake(
    repositoryPath: repo.dir.path,
    ledger: ledger,
    // No engine on purpose for most tests: coverage must NOT depend on it.
    // An engine improves grouping and ordering; it must never decide which
    // files are reachable.
    engine: null,
  );
  expect(r.ok, isTrue, reason: 'plan failed: ${r.error}');
  return r.data!;
}

Set<String> plannedPaths(ShakePlan plan) => {
      for (final r in plan.pending) ...r.files.map((f) => f.path),
    };

void main() {
  late ScratchRepo repo;

  setUpAll(() async => repo = await buildRepo());
  tearDownAll(() async => repo.dispose());

  // ── coverage is over the tree ───────────────────────────────────

  test('S1: a file written once and never touched again is still planned',
      () async {
    // THE point. A sweep built on history would reach `busy.dart` (it churns)
    // and could miss `quiet.dart` entirely — and quiet, unexamined code is
    // where bugs survive longest.
    final plan = await planFor(repo, ShakeLedger.empty());
    final paths = plannedPaths(plan);

    expect(paths, contains('lib/quiet.dart'));
    expect(paths, contains('lib/busy.dart'));
    expect(paths, contains('lib/other/side.dart'));
  });

  test('S2: coverage does not depend on the engine being available',
      () async {
    // The plan above ran with engine: null and still reached every file. An
    // engine may only improve grouping and order.
    final plan = await planFor(repo, ShakeLedger.empty());
    expect(plan.domainFiles, plannedPaths(plan).length);
    expect(plan.pendingFiles, plan.domainFiles,
        reason: 'a fresh ledger means everything is pending');
  });

  test('S3: every domain file lands in exactly one region', () async {
    // Overlap would double-spend model calls; a gap would be silent
    // non-coverage wearing a completion report.
    final plan = await planFor(repo, ShakeLedger.empty());
    final seen = <String>[];
    for (final r in plan.pending) {
      seen.addAll(r.files.map((f) => f.path));
    }
    expect(seen.toSet().length, seen.length, reason: 'a file was in two '
        'regions');
    expect(seen.toSet(), plan.livePaths);
  });

  // ── exclusions are declared ─────────────────────────────────────

  test('S4: generated and non-source files are excluded BY NAME, not '
      'silently', () async {
    final plan = await planFor(repo, ShakeLedger.empty());
    final paths = plannedPaths(plan);

    expect(paths, isNot(contains('lib/model.g.dart')));
    expect(plan.excluded[ShakeExclusion.generated], contains('lib/model.g.dart'),
        reason: 'a skipped file must be counted and nameable, or the coverage '
            'number is a fiction');

    expect(paths, isNot(contains('logo.png')));
    expect(paths, isNot(contains('README.md')));
    expect(plan.excluded[ShakeExclusion.notSource],
        containsAll(<String>['logo.png', 'README.md']));
  });

  test('S5: the generated classifier recognises the usual machine output',
      () {
    for (final p in const [
      'lib/i18n/gen/strings_en.g.dart',
      'a/b/thing.freezed.dart',
      'proto/msg.pb.dart',
      'pubspec.lock',
      'web/vendor/jquery.min.js',
      'node_modules/x/index.js',
      'build/output.dart',
    ]) {
      expect(isGeneratedPath(p), isTrue, reason: p);
    }
    for (final p in const [
      'lib/backend/git.dart',
      'lib/features/regenerate.dart', // "gen" inside a word is not a dir
      'test/backend/thing_test.dart',
    ]) {
      expect(isGeneratedPath(p), isFalse, reason: p);
    }
  });

  // ── examined-ness is content, not time ──────────────────────────

  test('S6: a file examined at its current content drops out of the plan',
      () async {
    final ledger = ShakeLedger.empty();
    final first = await planFor(repo, ledger);
    final quiet = first.pending
        .expand((r) => r.files)
        .firstWhere((f) => f.path == 'lib/quiet.dart');

    ledger.mark(quiet.path, quiet.blobOid, '2026-01-01T00:00:00Z');

    final second = await planFor(repo, ledger);
    expect(plannedPaths(second), isNot(contains('lib/quiet.dart')));
    expect(second.freshFiles, 1);
    expect(second.pendingFiles, first.pendingFiles - 1);
  });

  test('S7: EDITING an examined file re-opens it; touching it does not',
      () async {
    final ledger = ShakeLedger.empty();
    final plan = await planFor(repo, ledger);
    final side = plan.pending
        .expand((r) => r.files)
        .firstWhere((f) => f.path == 'lib/other/side.dart');
    ledger.mark(side.path, side.blobOid, '2026-01-01T00:00:00Z');

    expect(plannedPaths(await planFor(repo, ledger)),
        isNot(contains('lib/other/side.dart')));

    // Rewrite with IDENTICAL content and commit: the blob OID is unchanged,
    // so it stays examined. A timestamp key would have re-opened it here —
    // and Windows mtime granularity has burned this codebase before.
    await repo.writeFile('lib/other/side.dart', 'int side() => 2;\n');
    await repo.git(['commit', '-am', 'no-op rewrite', '--allow-empty']);
    expect(plannedPaths(await planFor(repo, ledger)),
        isNot(contains('lib/other/side.dart')),
        reason: 'same bytes, same blob, still examined');

    // Now change it for real.
    await repo.writeFile('lib/other/side.dart', 'int side() => 999;\n');
    await repo.commitAll('really change side');
    expect(plannedPaths(await planFor(repo, ledger)),
        contains('lib/other/side.dart'),
        reason: 'different bytes, different blob, needs examining again');
  });

  test('S8: a RENAMED file is unexamined under its new name', () async {
    final ledger = ShakeLedger.empty();
    final plan = await planFor(repo, ledger);
    for (final f in plan.pending.expand((r) => r.files)) {
      ledger.mark(f.path, f.blobOid, '2026-01-01T00:00:00Z');
    }
    expect((await planFor(repo, ledger)).isComplete, isTrue);

    await repo.gitOk(['mv', 'lib/quiet.dart', 'lib/renamed.dart']);
    await repo.commitAll('rename quiet');

    final after = await planFor(repo, ledger);
    expect(plannedPaths(after), contains('lib/renamed.dart'),
        reason: 'the record was keyed to the old path; under a new name the '
            'file has not been examined, which is the honest answer');
  });

  test('S9: a DELETED file stops claiming coverage', () async {
    final ledger = ShakeLedger.empty();
    ledger.mark('lib/long_gone.dart', 'deadbeef', '2026-01-01T00:00:00Z');
    expect(ledger.examinedCount, 1);

    final plan = await planFor(repo, ledger);
    final pruned = ledger.prune(plan.livePaths);

    expect(pruned, 1);
    expect(ledger.recordFor('lib/long_gone.dart'), isNull,
        reason: 'a record for a file that no longer exists inflates the '
            'examined count forever');
  });

  // ── the sweep terminates ────────────────────────────────────────

  test('S10: examining everything reaches a fixpoint', () async {
    // Not "stops after N" — actually complete, and provably so.
    final ledger = ShakeLedger.empty();
    var plan = await planFor(repo, ledger);
    expect(plan.isComplete, isFalse, reason: 'guard: there is work to do');

    var rounds = 0;
    while (!plan.isComplete && rounds < 50) {
      rounds++;
      // One region per round, exactly as a budgeted run behaves.
      for (final f in plan.pending.first.files) {
        ledger.mark(f.path, f.blobOid, '2026-01-01T00:00:00Z');
      }
      plan = await planFor(repo, ledger);
    }

    expect(plan.isComplete, isTrue,
        reason: 'a bounded run repeated must converge, not stall');
    expect(plan.pendingFiles, 0);
    expect(plan.freshFiles, plan.domainFiles);
    expect(rounds, lessThan(50));
  });

  test('S11: regions never exceed what a single audit can admit', () async {
    // The size bound is derived from the analysis budget, so a planned region
    // is by construction one that can actually be read. A region above it
    // would be declined at the door and the sweep would stall on it forever.
    final plan = await planFor(repo, ShakeLedger.empty());
    final cap = maxRegionBytes();
    expect(cap, greaterThan(0));
    for (final r in plan.pending) {
      expect(r.bytes, lessThanOrEqualTo(cap), reason: r.label);
      expect(r.files, isNotEmpty, reason: 'an empty region is a wasted call');
    }
  });

  test('S12: unexamined regions are ordered before examined ones', () async {
    // The ordering is lexicographic on purpose — never-examined first, and
    // only then by churn. A weighted sum of incommensurable signals would be
    // a pile of tuning constants.
    final ledger = ShakeLedger.empty();
    final plan = await planFor(repo, ledger);
    // Examine ONE file out of one region, so that region is no longer
    // wholly unexamined while the others still are.
    final victim = plan.pending.last;
    ledger.mark(victim.files.first.path, victim.files.first.blobOid,
        '2026-01-01T00:00:00Z');

    final reordered = await planFor(repo, ledger);
    var sawExamined = false;
    for (final r in reordered.pending) {
      if (!r.unexamined) {
        sawExamined = true;
      } else {
        expect(sawExamined, isFalse,
            reason: 'an untouched region appeared after a partly-examined '
                'one: ${r.label}');
      }
    }
  });

  test('S12b: regions are named after the code in them, not a cluster '
      'number', () async {
    // `cluster 2 · part 1` told a reader nothing they could act on. A region
    // is named by its files' deepest shared directory, which is what a person
    // would have called the group anyway.
    final plan = await planFor(repo, ShakeLedger.empty());
    for (final r in plan.pending) {
      expect(r.label, isNot(startsWith('cluster ')));
      expect(r.label, isNot(contains('part ')));
      // Labels are RELATIVE to the plan's common prefix, which is stated once
      // by the reporter rather than repeated on every name.
      final head = r.label.split(' · ').first;
      final namesSomething = head == '.' ||
          r.files.any((f) {
            final rel = plan.commonPrefix.isEmpty
                ? f.path
                : f.path.substring(plan.commonPrefix.length + 1);
            return rel.startsWith(head);
          });
      expect(namesSomething, isTrue,
          reason: 'label "${r.label}" names none of its own files');
    }
  });

  test('S12d: the prefix shared by the whole domain is stripped, not '
      'repeated', () async {
    // Every file here lives under `lib/` or `test/`... in this fixture the
    // shared prefix is empty, so nothing is stripped. The contract that
    // matters is that whatever IS shared never appears in a label.
    final plan = await planFor(repo, ShakeLedger.empty());
    if (plan.commonPrefix.isEmpty) {
      expect(plan.pending, isNotEmpty);
      return;
    }
    for (final r in plan.pending) {
      expect(r.label, isNot(startsWith(plan.commonPrefix)),
          reason: 'the shared prefix was repeated on a region name');
    }
  });

  test('S12e: commonPrefixOf finds the deepest shared directory', () {
    expect(
      commonPrefixOf(const [
        'apps/desktop/lib/a.dart',
        'apps/desktop/lib/b/c.dart',
      ]),
      'apps/desktop/lib',
    );
    expect(
      commonPrefixOf(const ['apps/one/a.dart', 'apps/two/b.dart']),
      'apps',
    );
    // Nothing shared, and a root-level file, both collapse to empty rather
    // than inventing a prefix.
    expect(commonPrefixOf(const ['a/x.dart', 'b/y.dart']), '');
    expect(commonPrefixOf(const ['top.dart', 'lib/x.dart']), '');
    expect(commonPrefixOf(const []), '');
  });

  test('S12c: colliding names are numbered, unique names are left alone',
      () async {
    final plan = await planFor(repo, ShakeLedger.empty());
    final labels = [for (final r in plan.pending) r.label];
    expect(labels.toSet().length, labels.length,
        reason: 'two regions shared a name, so a finding could not be traced '
            'back to the region that produced it');
    // With this small repo nothing should need numbering at all.
    for (final l in labels) {
      expect(l, isNot(contains(' of ')));
    }
  });

  test('S13: a plan is reproducible run to run', () async {
    // A sweep whose order shuffles cannot be resumed meaningfully, and its
    // "next up" report would be noise.
    final a = await planFor(repo, ShakeLedger.empty());
    final b = await planFor(repo, ShakeLedger.empty());
    expect([for (final r in a.pending) r.label],
        [for (final r in b.pending) r.label]);
    expect([for (final r in a.pending) r.files.map((f) => f.path).toList()],
        [for (final r in b.pending) r.files.map((f) => f.path).toList()]);
  });
}
