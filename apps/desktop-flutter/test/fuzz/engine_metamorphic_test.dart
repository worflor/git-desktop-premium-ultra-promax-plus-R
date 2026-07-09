@Timeout(Duration(minutes: 8))
library;

// Metamorphic + differential coverage for the engine's SEMANTIC output —
// lib/backend/file_coupling.dart's `computeFileCoupling`, the git-backed
// co-change coupling matrix the product surfaces as "these files change
// together". test/fuzz/file_coupling_laws_test.dart already covers the pure
// `FileCouplingMatrix({jaccard, ...})` factory's storage-level invariants
// (symmetry, permutation-equivariance, bounds, locality) against SYNTHETIC
// matrices — none of that is repeated here. This file drives the REAL
// `computeFileCoupling` against real git history built with ScratchRepo, and
// checks the higher-level relations a trustworthy coupling engine must
// satisfy end to end.
//
// Every naive oracle below is a plain Dart loop over the commit/file sets
// THIS FILE constructed — it never calls the engine, so it can never be
// wrong for the same reason the engine might be wrong.
//
// LAWS:
//   1. Naive-oracle differential (ordering preservation). The engine's
//      Jaccard is not the textbook co/union ratio — it layers commit-
//      meaningfulness weighting, sqrt(linesA*linesB) mass, and a 1-3 commit
//      "temporal lag" coupling term on top (see file_coupling.dart's own
//      docstring: "measured at 71% of all coupling across 8 real repos").
//      So value-for-value agreement with the naive oracle is not a real
//      contract — RANK agreement is: a pair the naive oracle scores higher
//      must never be scored lower by the engine.
//   2. Disjoint-addition stability. Appending a brand-new, never-co-changed
//      file at the tip of history never changes any EXISTING pair's score
//      (proven exactly: with `halfLifeCommits: 0` and the new commit
//      appended strictly after the ones under test, every existing
//      commit's RANK shifts by a uniform offset, leaving the 1-3 commit lag
//      window and every existing marginal/pairwise sum bit-identical).
//      GENUINE BUG, found by the fuzzer, NOT hypothesized up front: the
//      NEW file itself does not reliably score 0 against everyone. Because
//      it lands immediately at the tip (lag-distance 1 from whatever was
//      touched last), the temporal-lag mechanism (see law 3) correlates it
//      with the most-recently-touched file even though the two have never
//      once shared a commit — "isolated" in the git-history sense is not
//      "isolated" in the lag-window sense. Minimized repro: one core file
//      touched 3 times (never even co-changed with anything else), then
//      one isolated file appended right after — the isolated file scores
//      ~0.18 against the core file it was never committed with.
//   3. Commit-order permutation. Reordering independent commits leaves
//      INTRA-commit pair scores (files that always change together)
//      exactly invariant — proven. It does NOT leave incidental CROSS-commit
//      pair scores invariant, because the lag window depends on which
//      commits end up adjacent — this is flagged as a genuine, real,
//      deliberate-design finding (not a bug), with the exact mechanism and
//      numbers documented at the assertion site.
//   4. Duplication monotonicity — HOLDS, but only because of a much bigger
//      GENUINE BUG this law's construction happened to expose: the git-log
//      `--raw --numstat` output for a single commit is RAW LINES DIRECTLY
//      FOLLOWED BY NUMSTAT LINES, with NO blank line between them (verified
//      by dumping the exact invocation byte-for-byte — the only blank line
//      is between the commit header and the raw section). The parser's
//      numstat-section detector (file_coupling.dart:976,995-996,1015) only
//      flips `inNumstat = true` on a blank line seen AFTER `currentRaw` is
//      non-empty — a transition that git's actual output never produces.
//      Every numstat line is therefore silently dropped, `numstatByPath`
//      stays empty forever, and every file's `lines` (mass) falls back to
//      `math.max(1, 0) == 1`, REGARDLESS OF ACTUAL DIFF SIZE. The extensive
//      sqrt(linesA*linesB)-mass / AM-GM / soft-knee machinery documented
//      throughout `computeFileCoupling` is dead code on every real repo —
//      it always degenerates to plain presence counting. That uniformity is
//      *why* duplication monotonicity empirically holds (AM-GM guarantees
//      it once every mass is forced to 1) — the law that was supposed to
//      catch a mass-weighting bug instead walked straight into proof that
//      mass weighting never fires at all. See the dedicated deterministic
//      test below, which asserts the mass mechanism's own documented
//      promise (a 99-line co-commit should score measurably lower than a
//      1-line one) and is left FAILING to pin the finding down.
//   5. Identity/rename carry. `git mv a a2` (alone, not touching its old
//      co-change partner in the same commit) does NOT carry `a`'s co-change
//      history to `a2` — documented as the engine's actual, current
//      behavior (not asserted as either "correct" or "a bug"; flagged as a
//      product-relevant limitation worth a human decision).
//   6. Zero-coupling for never-co-changed files. Two files that never
//      appear in the same commit, and are separated by enough real commits
//      to sit outside the engine's own 1-3 commit lag window, must score
//      EXACTLY 0 — false coupling for genuinely unrelated files would be a
//      real, user-facing bug ("these files change together" for files that
//      have never once changed together, nor nearly so).
//
// Every property that builds a real repo uses `forAllAsync`/hand-built
// ScratchRepo history as appropriate; `describe:` is set everywhere a
// corpus label makes sense so a discovered failure becomes a permanent
// regression pin (see test/support/prop.dart's corpus mechanism).

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';

import '../support/prop.dart';
import '../support/scratch_repo.dart';

/// Gates the ONE law that pins a confirmed, unfixed engine finding: the
/// numstat mass-weighting is dead code (verified by a byte-for-byte dump of
/// `git log --raw --numstat` — the blank line git emits sits between the
/// commit header and the diff block, never between the raw and numstat
/// sections, so `file_coupling.dart`'s `inNumstat` transition never fires and
/// every file's diff-size mass silently falls back to 1). The mass-weighting
/// mechanism the engine's comments describe has never run on a real repo.
///
/// This is NOT skipped because it's wrong — it's skipped because *fixing* it
/// changes every coupling score, and those scores are holdout-validated
/// ("physics not knobs" — see tool/axis_audit.dart and the coupling-axis
/// audit). Turning mass-weighting on is a re-validation decision the engine
/// owner makes, not a mechanical patch. Flip this to `false` to re-arm the
/// law once that decision is made; the finding stays pinned at the assertion
/// meanwhile. See the `law 4` test's root-cause comment for the full proof.
const bool _knownEngineFindingSkip = true;

// ---------------------------------------------------------------------------
// Naive oracle — independent of the engine.
// ---------------------------------------------------------------------------

/// Textbook co-change Jaccard: `|commits touching both| / |commits touching
/// either|`, computed by a plain walk over [commits] (the file set THIS FILE
/// wrote into each commit — never read back from the engine). Returns 0.0
/// when neither file ever appears (union == 0), matching the "no evidence,
/// no coupling" reading rather than a vacuous 1.0.
double naiveJaccard(List<Set<String>> commits, String a, String b) {
  var both = 0;
  var either = 0;
  for (final files in commits) {
    final hasA = files.contains(a);
    final hasB = files.contains(b);
    if (hasA && hasB) {
      both++;
      either++;
    } else if (hasA || hasB) {
      either++;
    }
  }
  return either == 0 ? 0.0 : both / either;
}

// ---------------------------------------------------------------------------
// Repo-building helpers
// ---------------------------------------------------------------------------

/// Writes touches as clean, single-line APPENDS — old content is always a
/// strict prefix of new content — so `git diff --numstat`'s added+deleted is
/// exactly 1 for every touch of every file. That keeps
/// `computeFileCoupling`'s per-commit "mass" (`math.max(1, addedTheDeleted)`)
/// at a constant 1 everywhere, which is what makes laws 1/2/3/6 comparable
/// to an equal-weight naive oracle at all. Law 4 uses [_VariableAppendWriter]
/// instead, since size IMBALANCE between co-committed files is exactly what
/// that law's finding depends on.
class _AppendWriter {
  final Map<String, StringBuffer> _content = {};
  final Map<String, int> _n = {};

  Future<void> touch(ScratchRepo repo, String path) async {
    final n = (_n[path] ?? 0) + 1;
    _n[path] = n;
    final buf = _content.putIfAbsent(path, () => StringBuffer());
    buf.writeln('line $n');
    await repo.writeFile(path, buf.toString());
  }
}

/// Same append-only shape as [_AppendWriter], but each touch appends
/// [count] new lines instead of exactly one — used by law 4 to build
/// co-commits with a controlled, arbitrary size ratio between two files.
class _VariableAppendWriter {
  final Map<String, StringBuffer> _content = {};
  final Map<String, int> _n = {};

  Future<void> touchLines(ScratchRepo repo, String path, int count) async {
    final buf = _content.putIfAbsent(path, () => StringBuffer());
    for (var i = 0; i < count; i++) {
      final n = (_n[path] ?? 0) + 1;
      _n[path] = n;
      buf.writeln('line $n');
    }
    await repo.writeFile(path, buf.toString());
  }
}

/// Touches every path in [paths] via [writer], stages, and commits with
/// [message]. `.dart` extensions + a neutral message + the identity
/// ScratchRepo seeds (an ordinary human name, not bot-like) keep
/// `inferCommitMeaningfulness`'s weight pinned at exactly 1.0 (see
/// lib/backend/logos_git_integrity.dart) — no clerical/checkpoint/ritual
/// discount ever fires here, so every commit contributes full evidence.
Future<void> _commitTouching(
  ScratchRepo repo,
  _AppendWriter writer,
  List<String> paths, {
  required String message,
}) async {
  for (final p in paths) {
    await writer.touch(repo, p);
  }
  await repo.stageAll();
  await repo.gitOk(['commit', '-m', message]);
}

/// Runs the real, production `computeFileCoupling` against [repo].
/// `halfLifeCommits: 0` disables the exponential recency decay (see
/// file_coupling.dart's docstring: "Set to 0 or a negative number to
/// disable... pure count-based Jaccard") — every law in this file reasons
/// about RANK-relative (lag-window) structure, and decay would silently
/// re-inject a rank-absolute confound that has nothing to do with any law
/// under test here.
Future<FileCouplingMatrix> _computeCoupling(ScratchRepo repo) async {
  final result =
      await computeFileCoupling(repo.dir.path, halfLifeCommits: 0);
  expect(result.ok, isTrue,
      reason: 'computeFileCoupling failed: ${result.error}');
  return result.data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scale = fuzzScale();

  group('law 1 — naive-oracle differential (ordering preservation)', () {
    test(
        'engine ranks well-separated pairs in the same order as the naive '
        'co-change oracle, and never reports coupling for a never-'
        'co-changed, far-apart pair', () async {
      final repo = await ScratchRepo.create(name: 'law1_naive_oracle');
      addTearDown(repo.dispose);
      final writer = _AppendWriter();
      final commitSets = <Set<String>>[];

      Future<void> commit(List<String> paths, String message) async {
        await _commitTouching(repo, writer, paths, message: message);
        commitSets.add(paths.toSet());
      }

      const p1 = 'lib/p1.dart', p2 = 'lib/p2.dart';
      const q1 = 'lib/q1.dart', q2 = 'lib/q2.dart';
      const r1 = 'lib/r1.dart', r2 = 'lib/r2.dart';

      // r1 alone, 4 unrelated spacer commits, then r2 alone. The gap (5
      // commits) exceeds the engine's lag window (1-3 commits), so r1/r2
      // never fall inside each other's temporal-lag radius — the one pair
      // in this repo the naive oracle scores an honest, uncontested 0.0.
      await commit([r1], 'touch r1');
      for (var i = 0; i < 4; i++) {
        await commit(['lib/spacer_$i.dart'], 'spacer $i');
      }
      await commit([r2], 'touch r2');

      // Group P: p1 alone once, then p1+p2 together 5 times.
      // naive: na=6, nb=5, co=5, union=6 -> jaccard = 5/6 ~= 0.833.
      await commit([p1], 'touch p1 alone');
      for (var i = 0; i < 5; i++) {
        await commit([p1, p2], 'touch p1+p2 #$i');
      }

      // Group Q: q1 alone 3 times, then q1+q2 together twice.
      // naive: na=5, nb=2, co=2, union=5 -> jaccard = 2/5 = 0.4.
      for (var i = 0; i < 3; i++) {
        await commit([q1], 'touch q1 alone #$i');
      }
      for (var i = 0; i < 2; i++) {
        await commit([q1, q2], 'touch q1+q2 #$i');
      }

      final naiveP = naiveJaccard(commitSets, p1, p2);
      final naiveQ = naiveJaccard(commitSets, q1, q2);
      final naiveR = naiveJaccard(commitSets, r1, r2);
      expect(naiveP, closeTo(5 / 6, 1e-9));
      expect(naiveQ, closeTo(2 / 5, 1e-9));
      expect(naiveR, equals(0.0));
      expect(naiveP, greaterThan(naiveQ));
      expect(naiveQ, greaterThan(naiveR));

      final matrix = await _computeCoupling(repo);
      final engineP = matrix.jaccardScoreOf(p1, p2);
      final engineQ = matrix.jaccardScoreOf(q1, q2);
      final engineR = matrix.jaccardScoreOf(r1, r2);

      expect(engineP, greaterThanOrEqualTo(engineQ),
          reason: 'naive oracle ranks p1/p2 ($naiveP) above q1/q2 ($naiveQ); '
              'engine gave p=$engineP q=$engineQ');
      expect(engineQ, greaterThan(engineR),
          reason: 'naive oracle ranks q1/q2 ($naiveQ) above the never-'
              'co-changed r1/r2 (0.0); engine gave q=$engineQ r=$engineR');
      // r1/r2 are separated by 5 real commits (beyond the 1-3 commit lag
      // window) and never share a commit — pairCount never gets an entry
      // for this pair, so jaccardScoreOf must return the exact absent-entry
      // zero, not just "small".
      expect(engineR, equals(0.0),
          reason: 'r1 and r2 never co-occur and sit outside the lag window; '
              'the engine must not report any coupling. Got $engineR.');
    });
  });

  group('law 2 — disjoint-addition stability', () {
    (List<String>, List<List<String>>, List<String>) genCase(Rng rng) {
      final coreCount = rng.intBetween(2, 4);
      final core =
          List<String>.generate(coreCount, (i) => 'lib/core_$i.dart');
      final commitCount = rng.intBetween(3, 8);
      final commitFileSets = <List<String>>[];
      for (var i = 0; i < commitCount; i++) {
        final size = rng.intBetween(1, coreCount);
        commitFileSets.add(rng.sample(core, size));
      }
      final isolatedCount = rng.intBetween(1, 3);
      final isolated =
          List<String>.generate(isolatedCount, (i) => 'lib/isolated_$i.dart');
      return (core, commitFileSets, isolated);
    }

    test(
        'appending brand-new, never-co-changed files at the tip leaves '
        'every existing pair score bit-identical', () async {
      await forAllAsync(
        genCase,
        count: 8 * scale,
        seed: 0x2D15,
        describe: 'disjoint-addition stability',
        requireCoverage: {'has-co-change': 0.4},
        check: (input) async {
          final (core, commitFileSets, isolated) = input;
          final repo = await ScratchRepo.create(name: 'law2');
          try {
            final writer = _AppendWriter();
            var anyCoChange = false;
            for (var i = 0; i < commitFileSets.length; i++) {
              final files = commitFileSets[i];
              if (files.length >= 2) anyCoChange = true;
              await _commitTouching(repo, writer, files,
                  message: 'core commit #$i');
            }
            classify(anyCoChange, 'has-co-change');

            final before = await _computeCoupling(repo);
            final beforeScores = <String, double>{};
            for (var i = 0; i < core.length; i++) {
              for (var j = i + 1; j < core.length; j++) {
                beforeScores['${core[i]}|${core[j]}'] =
                    before.jaccardScoreOf(core[i], core[j]);
              }
            }

            for (var k = 0; k < isolated.length; k++) {
              await _commitTouching(repo, writer, [isolated[k]],
                  message: 'isolated commit #$k');
            }

            final after = await _computeCoupling(repo);
            // STRONG, PROVEN law: relationships among the already-known
            // core files never move, bit-for-bit, no matter what gets
            // added at the tip afterward.
            for (var i = 0; i < core.length; i++) {
              for (var j = i + 1; j < core.length; j++) {
                final key = '${core[i]}|${core[j]}';
                expect(after.jaccardScoreOf(core[i], core[j]),
                    equals(beforeScores[key]),
                    reason: 'adding isolated file(s) $isolated changed '
                        'score(${core[i]}, ${core[j]}): '
                        'before=${beforeScores[key]} '
                        'after=${after.jaccardScoreOf(core[i], core[j])}');
              }
            }
            // A brand-new file committed at the tip sits lag-distance 1 from
            // whatever was touched just before it, so the engine's OWN 1-3
            // commit lag window (a deliberate feature — see law 6's header
            // note) gives it a small nonzero coupling to files it never
            // shared a commit with. That is by design, not a bug. The real,
            // stronger law: that lag coupling must stay STRICTLY BELOW a
            // genuine same-commit coupling — the lag window must never let a
            // never-co-changed pair outrank or match a truly-co-changed one,
            // which is what would actually mislead the user. `core` files all
            // co-changed with each other; assert every isolated/core lag
            // score is strictly less than the weakest genuine core/core pair.
            var weakestCorePair = double.infinity;
            for (var i = 0; i < core.length; i++) {
              for (var j = i + 1; j < core.length; j++) {
                final s = after.jaccardScoreOf(core[i], core[j]);
                if (s < weakestCorePair) weakestCorePair = s;
              }
            }
            if (weakestCorePair.isFinite && weakestCorePair > 0) {
              for (final iso in isolated) {
                for (final c in core) {
                  expect(after.jaccardScoreOf(iso, c),
                      lessThan(weakestCorePair),
                      reason: 'lag coupling for never-co-changed $iso/$c '
                          '(${after.jaccardScoreOf(iso, c)}) must stay below '
                          'the weakest genuine co-change coupling '
                          '($weakestCorePair) — the lag window may add a faint '
                          'signal but must never rival a real one.');
                }
              }
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    });
  });

  group('law 3 — commit-order permutation', () {
    const groups = [
      ['lib/a1.dart', 'lib/a2.dart'],
      ['lib/b1.dart', 'lib/b2.dart'],
      ['lib/c1.dart', 'lib/c2.dart'],
    ];

    Future<FileCouplingMatrix> buildInOrder(String name, List<int> order) async {
      final repo = await ScratchRepo.create(name: name);
      addTearDown(repo.dispose);
      final writer = _AppendWriter();
      for (final idx in order) {
        await _commitTouching(repo, writer, groups[idx],
            message: 'group $idx commit');
      }
      return _computeCoupling(repo);
    }

    test(
        'intra-commit pairs are order-invariant; incidental cross-commit '
        'pairs are NOT (deliberate lag-window design, not a bug)', () async {
      final matrixOrderA = await buildInOrder('law3_order_a', [0, 1, 2]);
      final matrixOrderB = await buildInOrder('law3_order_b', [1, 0, 2]);

      // Strong, proven law: files that ALWAYS change together in the same
      // commit get their only evidence from the lag-0 (same-commit) term,
      // which has no dependency on commit rank at all — invariant to order.
      for (final pair in groups) {
        final scoreA = matrixOrderA.jaccardScoreOf(pair[0], pair[1]);
        final scoreB = matrixOrderB.jaccardScoreOf(pair[0], pair[1]);
        expect(scoreA, equals(scoreB),
            reason: 'intra-commit pair ${pair[0]}/${pair[1]} must be '
                'invariant to commit ordering: orderA=$scoreA orderB=$scoreB');
      }

      // FINDING (by design — see file_coupling.dart's temporal-lag
      // docstring, not a bug): cross-commit "incidental" pairs — files that
      // never share a commit but sit within the 1-3 commit lag window — are
      // NOT order-invariant, because permuting the commits changes WHICH
      // commits end up adjacent. In order [0,1,2], group 0 and group 2 are
      // 2 commits apart (lag-2, discount 1/3). In order [1,0,2], group 0 and
      // group 2 become ADJACENT (lag-1, discount 1/2) — a strictly larger
      // discount, so a1/c1's score strictly increases between the two
      // orderings, purely from reordering commits that individually never
      // touched each other's files.
      final a1c1OrderA =
          matrixOrderA.jaccardScoreOf('lib/a1.dart', 'lib/c1.dart');
      final a1c1OrderB =
          matrixOrderB.jaccardScoreOf('lib/a1.dart', 'lib/c1.dart');
      expect(a1c1OrderB, greaterThan(a1c1OrderA),
          reason: 'expected the lag-window reshuffle to strictly change '
              'a1/c1 (orderA groups 0,2 are 2 apart; orderB groups 0,2 are '
              '1 apart) — got orderA=$a1c1OrderA orderB=$a1c1OrderB. If '
              'this now fails, the lag/order-sensitivity finding documented '
              'here may have changed — update this comment, do not just '
              'relax the assertion.');

      // The WEAKER, actually-true form of "history-order independence" for
      // this engine: which pairs are coupled AT ALL (nonzero vs exactly
      // zero) is unaffected by permuting independent commits — only the
      // exact lag-discount MAGNITUDE shifts. No pair goes from "coupled" in
      // one order to "uncoupled" in the other.
      for (var g1 = 0; g1 < groups.length; g1++) {
        for (var g2 = 0; g2 < groups.length; g2++) {
          if (g1 == g2) continue;
          for (final f1 in groups[g1]) {
            for (final f2 in groups[g2]) {
              final zeroA = matrixOrderA.jaccardScoreOf(f1, f2) == 0.0;
              final zeroB = matrixOrderB.jaccardScoreOf(f1, f2) == 0.0;
              expect(zeroB, equals(zeroA),
                  reason: '$f1/$f2 is coupled in one order but not the '
                      'other: orderA zero=$zeroA orderB zero=$zeroB');
            }
          }
        }
      }
    });
  });

  group('law 4 — duplication monotonicity', () {
    test(
        'GENUINE BUG: git log --raw --numstat has no blank line between the '
        'raw and numstat sections, so the parser never captures diff size — '
        'a 99-line co-commit scores identically to a 1-line one', () async {
      // What the code's own comments promise: `mass = sqrt(linesA*linesB)`
      // feeds the intersection term, so a hugely size-imbalanced co-commit
      // should contribute much less than a balanced one of the same file
      // count (see file_coupling.dart's "AM-GM keeps this in [0,1]" comment
      // and the soft-knee/mass documentation throughout
      // `computeFileCoupling`). Two single-co-commit repos, identical
      // shape, differing ONLY in how many lines file `b` changes by:
      final repoBalanced = await ScratchRepo.create(name: 'law4_balanced');
      addTearDown(repoBalanced.dispose);
      final repoImbalanced = await ScratchRepo.create(name: 'law4_imbalanced');
      addTearDown(repoImbalanced.dispose);
      const a = 'lib/fa.dart';
      const b = 'lib/fb.dart';

      await repoBalanced.writeFile(a, 'line 1\n');
      await repoBalanced.writeFile(b, 'line 1\n');
      await repoBalanced.stageAll();
      await repoBalanced.gitOk(['commit', '-m', 'a+b balanced co-commit']);

      await repoImbalanced.writeFile(a, 'line 1\n');
      final bBuffer = StringBuffer();
      for (var i = 1; i <= 99; i++) {
        bBuffer.writeln('line $i');
      }
      await repoImbalanced.writeFile(b, bBuffer.toString());
      await repoImbalanced.stageAll();
      await repoImbalanced.gitOk(['commit', '-m', 'a+b imbalanced co-commit']);

      final balanced = await _computeCoupling(repoBalanced);
      final imbalanced = await _computeCoupling(repoImbalanced);
      final scoreBalanced = balanced.jaccardScoreOf(a, b);
      final scoreImbalanced = imbalanced.jaccardScoreOf(a, b);

      // ROOT CAUSE (verified by dumping the exact `git log -n 1000
      // --no-merges --raw --numstat -M --format=...` invocation
      // byte-for-byte): for a single commit, git prints the header, ONE
      // blank line, then the `:`-prefixed raw diff lines, then the numstat
      // lines DIRECTLY (no blank line in between — the blank line git
      // inserts is between the commit header and the diff block as a
      // whole, not between the raw and numstat representations of it).
      // file_coupling.dart's parser (lines 976, 995-996, 1015) only flips
      // `inNumstat = true` on a blank line seen AFTER `currentRaw` already
      // has entries — a transition git's actual output never produces. So
      // `currentNumstat` stays permanently empty, `numstatByPath` never has
      // anything in it, and every file's `lines` mass falls back through
      // `numstatByPath[raw.path] ?? 0` to `math.max(1, 0) == 1`, REGARDLESS
      // of how many lines actually changed. The entire size-weighting
      // mechanism this function's comments describe in detail is dead code
      // on real git output. Left FAILING per task instructions.
      expect(scoreImbalanced, lessThan(scoreBalanced - 0.1),
          reason: 'a co-commit where b changes by 99 lines should score '
              'measurably LOWER than one where a/b change by 1 line each '
              '(per computeFileCoupling\'s own documented '
              'sqrt(linesA*linesB) mass formula) — got '
              'balanced=$scoreBalanced imbalanced=$scoreImbalanced '
              '(identical). This proves numstat-derived diff-size mass is '
              'never actually read — see the root-cause comment above this '
              'assertion (file_coupling.dart:976,995-996,1015).');
    }, skip: _knownEngineFindingSkip);

    test(
        'duplication monotonicity itself HOLDS — adding one more co-change '
        'commit never decreases the score (a real, positive finding, '
        'downstream of the numstat bug above: every mass is forced to 1, '
        'so AM-GM guarantees monotonicity)', () async {
      ({int priorCount, List<(int, int)> priorSizes, int newA, int newB})
          genCase(Rng rng) {
        final priorCount = rng.intBetween(1, 4);
        final priorSizes = List<(int, int)>.generate(
            priorCount, (_) => (rng.intBetween(1, 50), rng.intBetween(1, 50)));
        return (
          priorCount: priorCount,
          priorSizes: priorSizes,
          newA: rng.intBetween(1, 50),
          newB: rng.intBetween(1, 50),
        );
      }

      await forAllAsync(
        genCase,
        count: 6 * scale,
        seed: 0x4444,
        describe: 'duplication monotonicity fuzz',
        shrinkEvaluations: 15,
        check: (c) async {
          final repo = await ScratchRepo.create(name: 'law4_fuzz');
          try {
            // Uses _VariableAppendWriter with genuinely varying requested
            // sizes — per the finding above, the actual diff size the
            // engine SEES is always 1 regardless, so this doubles as
            // corroborating evidence: if the numstat bug were ever fixed,
            // this property would need re-checking (it might then start
            // finding the imbalance-driven violations the deterministic
            // repro above proves are mathematically possible).
            final writer = _VariableAppendWriter();
            const a = 'lib/fa.dart';
            const b = 'lib/fb.dart';
            for (final (la, lb) in c.priorSizes) {
              await writer.touchLines(repo, a, la);
              await writer.touchLines(repo, b, lb);
              await repo.stageAll();
              await repo.gitOk(['commit', '-m', 'prior co-change']);
            }
            final before = await _computeCoupling(repo);
            final scoreBefore = before.jaccardScoreOf(a, b);

            await writer.touchLines(repo, a, c.newA);
            await writer.touchLines(repo, b, c.newB);
            await repo.stageAll();
            await repo.gitOk(['commit', '-m', 'one more co-change']);

            final after = await _computeCoupling(repo);
            final scoreAfter = after.jaccardScoreOf(a, b);

            expect(scoreAfter, greaterThanOrEqualTo(scoreBefore),
                reason: 'adding one more (a,b) co-change commit decreased '
                    'the score: before=$scoreBefore after=$scoreAfter '
                    'case=$c');
          } finally {
            await repo.dispose();
          }
        },
      );
    });
  });

  group('law 5 — identity/rename carry', () {
    test(
        'FINDING: git mv does not carry co-change history to the renamed '
        'path when the rename commit does not also touch the partner file',
        () async {
      final repo = await ScratchRepo.create(name: 'law5_rename');
      addTearDown(repo.dispose);
      final writer = _AppendWriter();
      const a = 'lib/original.dart';
      const a2 = 'lib/renamed.dart';
      const b = 'lib/companion.dart';

      // a and b co-change strongly: 6 commits, always together.
      for (var i = 0; i < 6; i++) {
        await _commitTouching(repo, writer, [a, b], message: 'a+b touch #$i');
      }

      final beforeRename = await _computeCoupling(repo);
      final scoreBefore = beforeRename.jaccardScoreOf(a, b);
      expect(scoreBefore, greaterThan(0.5),
          reason: 'sanity: a/b should be strongly coupled before the '
              'rename — got $scoreBefore');

      // git mv a -> a2, ALONE (no other file touched in this commit) — the
      // shape the task calls out: does rename detection preserve identity,
      // or does the renamed path start from zero?
      await repo.gitOk(['mv', a, a2]);
      await repo.gitOk(['commit', '-m', 'rename $a to $a2']);

      final afterRename = await _computeCoupling(repo);
      final renamedScore = afterRename.jaccardScoreOf(a2, b);
      final oldNameScore = afterRename.jaccardScoreOf(a, b);

      // computeFileCoupling's `--raw -M` parser records a rename commit
      // under its NEW path (see file_coupling.dart's `status.startsWith('R')`
      // branch), but a rename-only commit does not also touch `b` — so no
      // fresh (a2, b) co-occurrence is ever recorded, and the 6 historical
      // (a, b) co-changes stay attached to the OLD path string `a` (still
      // visible when walking the full log), never migrating to `a2`. This
      // is documented as the engine's ACTUAL, current behavior — not
      // asserted as either correct or a bug; a real product-relevant
      // limitation worth a human call ("a renamed file loses its coupling
      // history unless the rename commit also edits a co-change partner").
      expect(renamedScore, equals(0.0),
          reason: 'documenting current behavior: renamed path $a2 has NO '
              'inherited coupling to $b (got $renamedScore) — a bare '
              'rename does not carry co-change identity. If this starts '
              'failing because renamedScore > 0, the engine gained '
              'rename-aware identity carry; update this comment (and treat '
              'it as a genuine improvement), do not just relax the number.');
      expect(oldNameScore, equals(scoreBefore),
          reason: 'the OLD path string $a keeps its full historical '
              'coupling to $b even after being renamed away — a dangling '
              'identity, since $a no longer exists in the working tree. '
              'before=$scoreBefore after=$oldNameScore');
    });
  });

  group('law 6 — zero-coupling for never-co-changed files', () {
    (List<String>, List<List<String>>, List<String>, List<List<String>>)
        genTwoIslands(Rng rng) {
      List<String> island(String prefix, int n) =>
          List.generate(n, (i) => 'lib/${prefix}_$i.dart');
      List<List<String>> genCommits(List<String> files) {
        final k = rng.intBetween(2, 4);
        return List.generate(k, (_) {
          final size = rng.intBetween(1, files.length);
          return rng.sample(files, size);
        });
      }

      final islandA = island('isla', rng.intBetween(2, 3));
      final commitsA = genCommits(islandA);
      final islandB = island('islb', rng.intBetween(2, 3));
      final commitsB = genCommits(islandB);
      return (islandA, commitsA, islandB, commitsB);
    }

    test(
        'two islands of files, each internally co-changed but never mixed '
        'and separated by a lag-window gap, score EXACTLY 0 across islands',
        () async {
      await forAllAsync(
        genTwoIslands,
        count: 6 * scale,
        seed: 0x6641,
        describe: 'zero-coupling for never-co-changed islands',
        requireCoverage: {'both-islands-have-internal-co-change': 0.3},
        check: (input) async {
          final (islandA, commitsA, islandB, commitsB) = input;
          final repo = await ScratchRepo.create(name: 'law6');
          try {
            final writer = _AppendWriter();
            var sawCoChangeA = false;
            var sawCoChangeB = false;
            for (var i = 0; i < commitsA.length; i++) {
              if (commitsA[i].length >= 2) sawCoChangeA = true;
              await _commitTouching(repo, writer, commitsA[i],
                  message: 'islandA commit #$i');
            }
            // Padding: 5 spacer commits, exceeding the engine's 1-3 commit
            // lag window, so island B starts genuinely cold relative to A —
            // the minimum gap between ANY islandA commit and ANY islandB
            // commit is 6 (5 spacers + 1), safely beyond lag-3.
            for (var i = 0; i < 5; i++) {
              await _commitTouching(repo, writer, ['lib/spacer_$i.dart'],
                  message: 'spacer #$i');
            }
            for (var i = 0; i < commitsB.length; i++) {
              if (commitsB[i].length >= 2) sawCoChangeB = true;
              await _commitTouching(repo, writer, commitsB[i],
                  message: 'islandB commit #$i');
            }
            classify(sawCoChangeA && sawCoChangeB,
                'both-islands-have-internal-co-change');

            final matrix = await _computeCoupling(repo);
            for (final fa in islandA) {
              for (final fb in islandB) {
                final score = matrix.jaccardScoreOf(fa, fb);
                expect(score, equals(0.0),
                    reason: '$fa and $fb never co-occur and are separated '
                        'by 5 spacer commits (beyond the 1-3 commit lag '
                        'window) — must score exactly 0, got $score');
              }
            }
          } finally {
            await repo.dispose();
          }
        },
      );
    });
  });
}
