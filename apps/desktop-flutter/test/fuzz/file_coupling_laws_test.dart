// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Metamorphic property tests for Manifold's file-coupling engine
// (lib/backend/file_coupling.dart + lib/backend/engram_fit.dart).
//
// test/backend/file_coupling_ranking_test.dart and
// file_coupling_evaporation_test.dart already exercise the canonical ranking
// API and the time-weighted-Jaccard decay math against hand-picked, FIXED
// inputs. This file is the fuzzed complement: relationships that must hold
// across hundreds of RANDOM synthetic co-change graphs, never golden scores.
//
// Every law below feeds the PURE `FileCouplingMatrix({jaccard, headHash,
// commitsAnalyzed, spectral})` factory directly with synthetic data — none of
// this file calls the git-backed `computeFileCoupling`.
//
// LAWS:
//   1. Symmetry: score(a,b) == score(b,a) and jaccardScoreOf(a,b) ==
//      jaccardScoreOf(b,a), both from an explicitly symmetric input AND
//      (structurally, by construction) from an asymmetric one — the CSR
//      stores each unordered pair exactly once, so there is no way for the
//      matrix itself to disagree about direction.
//   2. Permutation equivariance: relabeling every file through a random
//      bijection preserves the multiset of pairwise scores and maps
//      topJaccardNeighbours(f) to topJaccardNeighbours(pi(f)) exactly
//      (same neighbours, renamed, same order/scores).
//   3. Bounds: jaccard/combined/pathAffinity scores and couplingConfidence
//      all stay in [0,1], always finite, even over hostile file names (NUL,
//      unicode, emoji ZWJ, bidi controls) and the empty matrix.
//   4. deriveEngramHalfLife totality: for every input shape (empty, single
//      commit, disjoint singletons, all-identical, random, hostile names)
//      the result is finite, inside the documented [50, 500] clamp band,
//      and deterministic.
//   5. pathAffinity metric shape: symmetric, self-maximal, bounded — NOT
//      prefix-monotonic (that's never promised by the implementation; see
//      the law-5 test for why asserting it would be testing a contract the
//      code doesn't make).
//   6. Locality: inserting a brand-new, edge-free file never changes any
//      existing pair's score/jaccardScoreOf/centrality — a real risk given
//      that paths are re-sorted (and CSR ids reassigned) on every
//      construction.
//   7. consecutiveJaccardSeries: length == max(0, commits-1); every value in
//      [0,1]; identical NON-EMPTY sets -> 1.0 (identical EMPTY sets are
//      special-cased to 0.0 — documented, not a bug); disjoint sets -> 0.0;
//      deterministic.
//
// Failures are captured with `describe:` (forAll's own reproduction line
// prints the failing seed+index) rather than papered over with a looser
// tolerance.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/engram_fit.dart' show consecutiveJaccardSeries;
import 'package:git_desktop/backend/file_coupling.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Local generators — synthetic co-change graphs over a small vocabulary of
// file paths, entirely independent of git.
// ---------------------------------------------------------------------------

/// A name flavor mixed at random per vocabulary slot: plain ASCII, tricky
/// relative paths (mixed separators, unicode segments, dotfiles), or fully
/// hostile strings (NUL, combining marks, bidi controls, emoji ZWJ runs).
Gen<String> _anyNameFlavor() {
  final ascii = genAscii(maxLen: 20);
  final relPath = genRelPath();
  final hostile = genUnicodeHostile(maxLen: 16);
  return (rng) {
    switch (rng.nextInt(3)) {
      case 0:
        return ascii(rng);
      case 1:
        return relPath(rng);
      default:
        return hostile(rng);
    }
  };
}

/// `n` distinct file-path-shaped names, flavored by [nameGen]. Uniqueness is
/// forced with an index suffix (`#i`) rather than retry-on-collision, so
/// even a maximally-degenerate [nameGen] (e.g. always `''`) can't produce a
/// vocabulary with duplicate slots — which would corrupt the bijection laws
/// below (a bijection needs a genuine domain of `n` distinct points).
List<String> _uniqueVocab(Rng rng, int n, Gen<String> nameGen) {
  final seen = <String>{};
  final out = <String>[];
  for (var i = 0; i < n; i++) {
    var name = '${nameGen(rng)}#$i';
    while (!seen.add(name)) {
      name = '$name~';
    }
    out.add(name);
  }
  return out;
}

/// Builds a jaccard map with an entry (possibly empty) for every path in
/// [vocab], then scatters random edges with weight in `[0, 1)` between
/// randomly chosen pairs at density [edgeProb]. Every edge is written to
/// BOTH directions with the SAME value — an explicitly symmetric input, the
/// precondition law 1's baseline check wants.
Map<String, Map<String, double>> _symmetricJaccardMap(
  List<String> vocab,
  Rng rng, {
  double edgeProb = 0.5,
}) {
  final map = <String, Map<String, double>>{
    for (final p in vocab) p: <String, double>{},
  };
  for (var i = 0; i < vocab.length; i++) {
    for (var j = i + 1; j < vocab.length; j++) {
      if (rng.nextDouble() >= edgeProb) continue;
      final v = rng.nextDouble();
      map[vocab[i]]![vocab[j]] = v;
      map[vocab[j]]![vocab[i]] = v;
    }
  }
  return map;
}

/// Relabels every key (outer and inner) of [src] through [pi] — a total
/// bijection from the source vocabulary to a fresh one. Values are carried
/// through completely unchanged; only identifiers move.
Map<String, Map<String, double>> _relabel(
  Map<String, Map<String, double>> src,
  Map<String, String> pi,
) {
  final out = <String, Map<String, double>>{};
  src.forEach((k, inner) {
    final newInner = <String, double>{};
    inner.forEach((k2, v) => newInner[pi[k2]!] = v);
    out[pi[k]!] = newInner;
  });
  return out;
}

FileCouplingMatrix _matrixOf(
  Map<String, Map<String, double>> jaccard, {
  int commitsAnalyzed = 200,
}) =>
    FileCouplingMatrix(
      jaccard: jaccard,
      headHash: 'synthetic',
      commitsAnalyzed: commitsAnalyzed,
    );

bool _finite(double v) => v.isFinite;

void main() {
  final scale = fuzzScale();

  group('law 1 — symmetry', () {
    test('score and jaccardScoreOf agree both directions from symmetric input', () {
      (List<String>, Map<String, Map<String, double>>) gen(Rng rng) {
        final vocab = _uniqueVocab(rng, rng.intBetween(2, 14), _anyNameFlavor());
        final jaccard =
            _symmetricJaccardMap(vocab, rng, edgeProb: rng.nextDouble());
        return (vocab, jaccard);
      }

      forAll(gen, count: 200 * scale, describe: 'symmetric jaccard input',
          check: (input) {
        final (vocab, jaccard) = input;
        final m = _matrixOf(jaccard);
        for (var i = 0; i < vocab.length; i++) {
          for (var j = i + 1; j < vocab.length; j++) {
            final a = vocab[i], b = vocab[j];
            expect(m.score(a, b), equals(m.score(b, a)),
                reason: 'score($a,$b) must equal score($b,$a)');
            expect(m.jaccardScoreOf(a, b), equals(m.jaccardScoreOf(b, a)),
                reason: 'jaccardScoreOf must be symmetric for $a/$b');
          }
        }
      });
    });

    test('storage is inherently symmetric even from an asymmetric input map', () {
      // _buildSymmetricCsr stores each unordered pair exactly ONCE — at
      // (min(i,j), max(i,j)) — with whichever direction is encountered first
      // during construction winning silently (no averaging). There is
      // therefore no way for an asymmetric input map to produce an
      // asymmetric matrix; this test locks in that structural guarantee
      // without prescribing which of the two conflicting values survives.
      (List<String>, Map<String, Map<String, double>>) gen(Rng rng) {
        final vocab = _uniqueVocab(rng, rng.intBetween(2, 10), _anyNameFlavor());
        final jaccard = <String, Map<String, double>>{
          for (final p in vocab) p: <String, double>{},
        };
        for (var i = 0; i < vocab.length; i++) {
          for (var j = i + 1; j < vocab.length; j++) {
            if (rng.nextDouble() >= 0.5) continue;
            // Deliberately DIFFERENT values in each direction.
            jaccard[vocab[i]]![vocab[j]] = rng.nextDouble();
            jaccard[vocab[j]]![vocab[i]] = rng.nextDouble();
          }
        }
        return (vocab, jaccard);
      }

      forAll(gen, count: 150 * scale, describe: 'asymmetric jaccard input',
          check: (input) {
        final (vocab, jaccard) = input;
        final m = _matrixOf(jaccard);
        for (var i = 0; i < vocab.length; i++) {
          for (var j = i + 1; j < vocab.length; j++) {
            final a = vocab[i], b = vocab[j];
            expect(m.score(a, b), equals(m.score(b, a)));
            expect(m.jaccardScoreOf(a, b), equals(m.jaccardScoreOf(b, a)));
          }
        }
      });
    });
  });

  group('law 2 — permutation equivariance (relabeling invariance)', () {
    test(
        'multiset of pairwise scores + topJaccardNeighbours are preserved '
        'under a random bijection', () {
      (List<String>, List<String>, Map<String, Map<String, double>>) gen(
        Rng rng,
      ) {
        final n = rng.intBetween(2, 12);
        final oldVocab = _uniqueVocab(rng, n, _anyNameFlavor());
        final newVocab = _uniqueVocab(rng.split(), n, _anyNameFlavor());
        final jaccard =
            _symmetricJaccardMap(oldVocab, rng, edgeProb: rng.nextDouble());
        return (oldVocab, newVocab, jaccard);
      }

      forAll(gen, count: 150 * scale, describe: 'permutation equivariance',
          check: (input) {
        final (oldVocab, newVocab, jaccard) = input;
        final pi = <String, String>{
          for (var i = 0; i < oldVocab.length; i++) oldVocab[i]: newVocab[i],
        };
        final matrixA = _matrixOf(jaccard);
        final matrixB = _matrixOf(_relabel(jaccard, pi));

        // Direct correspondence: renamed pair scores == original pair scores.
        final scoresA = <double>[];
        final scoresB = <double>[];
        for (var i = 0; i < oldVocab.length; i++) {
          for (var j = i + 1; j < oldVocab.length; j++) {
            final sa = matrixA.jaccardScoreOf(oldVocab[i], oldVocab[j]);
            final sb = matrixB.jaccardScoreOf(newVocab[i], newVocab[j]);
            expect(sb, equals(sa),
                reason: 'renaming ${oldVocab[i]}/${oldVocab[j]} -> '
                    '${newVocab[i]}/${newVocab[j]} must preserve the pair score');
            scoresA.add(sa);
            scoresB.add(sb);
          }
        }
        // Multiset equality, spelled out explicitly (sorted comparison) per
        // the letter of the law, even though the direct correspondence above
        // already implies it.
        scoresA.sort();
        scoresB.sort();
        expect(scoresB, equals(scoresA),
            reason:
                'the multiset of all pairwise scores must be identical up to renaming');

        // topJaccardNeighbours(pi(f)) on B == pi applied to
        // topJaccardNeighbours(f) on A — same neighbours, renamed, same
        // order/scores.
        for (final oldPath in oldVocab) {
          final newPath = pi[oldPath]!;
          final topOld = matrixA.topJaccardNeighbours(oldPath);
          final topNew = matrixB.topJaccardNeighbours(newPath);
          expect(topNew.length, equals(topOld.length),
              reason: 'neighbour count for $oldPath must survive renaming');
          for (var k = 0; k < topOld.length; k++) {
            expect(topNew[k].key, equals(pi[topOld[k].key]),
                reason: 'neighbour identity at rank $k for $oldPath must be '
                    'renamed via the same bijection, in the same order');
            expect(topNew[k].value, equals(topOld[k].value),
                reason: 'neighbour score at rank $k for $oldPath must be unchanged');
          }
        }
      });
    });
  });

  group('law 3 — bounds: scores/derived quantities never leave [0,1], never NaN/Inf', () {
    test('fuzzed matrices over mixed ascii/path/hostile names', () {
      (List<String>, Map<String, Map<String, double>>, int) gen(Rng rng) {
        final vocab = _uniqueVocab(rng, rng.intBetween(0, 14), _anyNameFlavor());
        final jaccard =
            _symmetricJaccardMap(vocab, rng, edgeProb: rng.nextDouble());
        final commitsAnalyzed = rng.intBetween(-50, 2000000);
        return (vocab, jaccard, commitsAnalyzed);
      }

      forAll(gen, count: 200 * scale, describe: 'bounds', check: (input) {
        final (vocab, jaccard, commitsAnalyzed) = input;
        final m = _matrixOf(jaccard, commitsAnalyzed: commitsAnalyzed);

        final conf = couplingConfidence(m);
        expect(_finite(conf), isTrue, reason: 'couplingConfidence must be finite');
        expect(conf, inInclusiveRange(0.0, 1.0));

        for (var i = 0; i < vocab.length; i++) {
          for (var j = 0; j < vocab.length; j++) {
            final a = vocab[i], b = vocab[j];
            final s = m.score(a, b);
            final js = m.jaccardScoreOf(a, b);
            expect(_finite(s), isTrue, reason: 'score($a,$b) must be finite');
            expect(_finite(js), isTrue, reason: 'jaccardScoreOf($a,$b) must be finite');
            expect(s, inInclusiveRange(0.0, 1.0));
            expect(js, inInclusiveRange(0.0, 1.0));
            // No spectral overlay was layered in, so score() must reduce to
            // the pure jaccard reading for any non-identity pair.
            if (a != b) {
              expect(s, equals(js),
                  reason: 'with no spectral overlay, score must equal jaccardScoreOf');
            }

            final combined = combinedCouplingScore(a, b, m);
            expect(_finite(combined), isTrue, reason: 'combinedCouplingScore must be finite');
            expect(combined, inInclusiveRange(0.0, 1.0));

            final aff = pathAffinity(a, b);
            expect(_finite(aff), isTrue, reason: 'pathAffinity must be finite');
            expect(aff, inInclusiveRange(0.0, 1.0));
          }
        }
      });
    });

    test('empty matrix and empty jaccard map never produce NaN/Inf', () {
      final m = FileCouplingMatrix.empty;
      expect(couplingConfidence(m), equals(0.0));
      expect(combinedCouplingScore('a', 'b', m), inInclusiveRange(0.0, 1.0));
      expect(pathAffinity('a', 'b'), inInclusiveRange(0.0, 1.0));
      expect(pathAffinity('', ''), equals(1.0));
      expect(pathAffinity('', 'x'), inInclusiveRange(0.0, 1.0));
    });

    test('a NUL byte inside a file name never breaks bounds', () {
      final nul = String.fromCharCode(0);
      final a = 'src/${nul}file.dart';
      final b = 'src/other$nul.dart';
      final m = _matrixOf({
        a: {b: 0.42},
        b: {a: 0.42},
      });
      expect(m.score(a, b), inInclusiveRange(0.0, 1.0));
      expect(pathAffinity(a, b), inInclusiveRange(0.0, 1.0));
      expect(combinedCouplingScore(a, b, m), inInclusiveRange(0.0, 1.0));
    });
  });

  group('law 4 — deriveEngramHalfLife: totality + clamp band', () {
    // Hardcoded from file_coupling.dart's `_halfLifeMin`/`_halfLifeMax`
    // (private constants — not exported, so the literal values are pinned
    // here directly; a change to those constants should update this too).
    const halfLifeMin = 50.0;
    const halfLifeMax = 500.0;

    void checkBounded(List<List<String>> commits) {
      final hl = deriveEngramHalfLife(commits);
      expect(_finite(hl), isTrue, reason: 'half-life must be finite for $commits');
      expect(hl, inInclusiveRange(halfLifeMin, halfLifeMax),
          reason: 'half-life must stay inside the [$halfLifeMin, $halfLifeMax] '
              'clamp band for $commits');
      // Determinism: re-run on a structurally-equal but freshly-built input.
      final again = deriveEngramHalfLife([for (final c in commits) [...c]]);
      expect(again, equals(hl), reason: 'deriveEngramHalfLife must be deterministic');
    }

    test('empty commit list', () {
      checkBounded(const []);
    });

    test('single commit, single file', () {
      checkBounded(const [
        ['a.dart']
      ]);
    });

    test('many commits, each touching a disjoint single file', () {
      checkBounded([for (var i = 0; i < 40; i++) ['file$i.dart']]);
    });

    test('all-identical commits', () {
      checkBounded([
        for (var i = 0; i < 30; i++) ['a.dart', 'b.dart', 'c.dart']
      ]);
    });

    test('fuzzed random commit sequences', () {
      List<List<String>> gen(Rng rng) {
        final vocab = _uniqueVocab(rng, rng.intBetween(1, 15), _anyNameFlavor());
        final commitCount = rng.intBetween(0, 60);
        return [
          for (var i = 0; i < commitCount; i++)
            [
              for (final f in vocab)
                if (rng.nextDouble() < 0.3) f,
            ],
        ];
      }

      forAll(gen, count: 150 * scale, describe: 'deriveEngramHalfLife totality',
          check: checkBounded);
    });

    test('fuzzed commits with hostile filenames', () {
      List<List<String>> gen(Rng rng) {
        final vocab =
            _uniqueVocab(rng, rng.intBetween(1, 10), genUnicodeHostile(maxLen: 16));
        final commitCount = rng.intBetween(0, 40);
        return [
          for (var i = 0; i < commitCount; i++)
            [
              for (final f in vocab)
                if (rng.nextDouble() < 0.4) f,
            ],
        ];
      }

      forAll(gen, count: 100 * scale,
          describe: 'deriveEngramHalfLife hostile names', check: checkBounded);
    });
  });

  group('law 5 — pathAffinity metric shape', () {
    test('symmetric, self-maximal, bounded', () {
      (String, String) gen(Rng rng) {
        final flavor = _anyNameFlavor();
        return (flavor(rng), flavor(rng));
      }

      forAll(gen, count: 200 * scale, describe: 'pathAffinity shape', check: (input) {
        final (a, b) = input;
        final ab = pathAffinity(a, b);
        final ba = pathAffinity(b, a);
        expect(_finite(ab), isTrue);
        expect(ab, inInclusiveRange(0.0, 1.0));
        expect(ab, equals(ba), reason: 'pathAffinity must be symmetric');
        expect(pathAffinity(a, a), equals(1.0));
        expect(pathAffinity(a, a), greaterThanOrEqualTo(ab),
            reason: 'self-affinity must be maximal');
        // NOT asserted: prefix-monotonicity ("a strictly longer shared
        // prefix implies a strictly higher score"). pathAffinity's dirScore
        // denominator is `max(depth_a, depth_b) - 1` and stemScore is a
        // Dice coefficient over stem length — both are relative to BOTH
        // paths' own lengths, so a pair sharing a longer literal prefix can
        // still score lower than a shallower pair once very differently
        // sized subtrees dilute the ratio. The function's own doc comment
        // promises "how much of the path is shared", not monotonicity, so
        // we don't hold it to a stronger contract than it advertises.
      });
    });
  });

  group('law 6 — locality: an isolated new file never shifts existing pair scores', () {
    test('inserting isolated files leaves every prior score bit-identical', () {
      (List<String>, Map<String, Map<String, double>>, List<String>) gen(
        Rng rng,
      ) {
        final vocab = _uniqueVocab(rng, rng.intBetween(2, 12), _anyNameFlavor());
        final jaccard =
            _symmetricJaccardMap(vocab, rng, edgeProb: rng.nextDouble());
        final isolatedCount = rng.intBetween(1, 5);
        final isolated =
            _uniqueVocab(rng.split(), isolatedCount, _anyNameFlavor())
                .map((s) => '${s}__isolated')
                .toList();
        return (vocab, jaccard, isolated);
      }

      forAll(gen, count: 150 * scale, describe: 'locality', check: (input) {
        final (vocab, jaccard, isolated) = input;
        final before = _matrixOf(jaccard);

        // Snapshot every existing pair's score BEFORE the insertion.
        final baselineScore = <String, double>{};
        final baselineJ = <String, double>{};
        final baselineCentrality = before.jaccardCentralityMap();
        for (var i = 0; i < vocab.length; i++) {
          for (var j = i + 1; j < vocab.length; j++) {
            final key = '${vocab[i]}\u0000${vocab[j]}';
            baselineScore[key] = before.score(vocab[i], vocab[j]);
            baselineJ[key] = before.jaccardScoreOf(vocab[i], vocab[j]);
          }
        }

        final augmented = <String, Map<String, double>>{...jaccard};
        for (final f in isolated) {
          augmented[f] = <String, double>{};
        }
        final after = _matrixOf(augmented);

        for (var i = 0; i < vocab.length; i++) {
          for (var j = i + 1; j < vocab.length; j++) {
            final key = '${vocab[i]}\u0000${vocab[j]}';
            expect(after.score(vocab[i], vocab[j]), equals(baselineScore[key]),
                reason: 'adding an isolated file must not change '
                    'score(${vocab[i]}, ${vocab[j]})');
            expect(after.jaccardScoreOf(vocab[i], vocab[j]), equals(baselineJ[key]),
                reason: 'adding an isolated file must not change '
                    'jaccardScoreOf(${vocab[i]}, ${vocab[j]})');
          }
        }
        final afterCentrality = after.jaccardCentralityMap();
        for (final p in vocab) {
          expect(afterCentrality[p], equals(baselineCentrality[p]),
              reason:
                  'jaccardCentralityMap for $p must be unaffected by an isolated insert');
        }
        for (final f in isolated) {
          expect(after.score(f, vocab.first), equals(0.0),
              reason: 'a brand-new isolated file must score 0 against everyone');
          expect(after.jaccardCentralityMap()[f], equals(0.0));
        }
      });
    });
  });

  group('law 7 — consecutiveJaccardSeries', () {
    test('length == max(0, commits-1); every value in [0,1]; deterministic', () {
      List<Set<String>> gen(Rng rng) {
        final vocab = _uniqueVocab(rng, rng.intBetween(1, 10), _anyNameFlavor());
        final n = rng.intBetween(0, 20);
        return [
          for (var i = 0; i < n; i++)
            {for (final f in vocab) if (rng.nextDouble() < 0.4) f},
        ];
      }

      forAll(gen, count: 200 * scale,
          describe: 'consecutiveJaccardSeries totality', check: (sets) {
        final series = consecutiveJaccardSeries(sets);
        expect(series.length, equals(sets.length < 2 ? 0 : sets.length - 1));
        for (final v in series) {
          expect(_finite(v), isTrue);
          expect(v, inInclusiveRange(0.0, 1.0));
        }
        final again = consecutiveJaccardSeries([for (final s in sets) {...s}]);
        expect(again, equals(series), reason: 'must be deterministic');
      });
    });

    test('identical non-empty consecutive sets -> 1.0', () {
      final s = {'a.dart', 'b.dart'};
      final series = consecutiveJaccardSeries([s, {...s}, {...s}]);
      expect(series, everyElement(closeTo(1.0, 1e-12)));
    });

    test('identical EMPTY consecutive sets are special-cased to 0.0, not 1.0', () {
      // consecutiveJaccardSeries's `a.isEmpty && b.isEmpty` branch
      // (engram_fit.dart) returns 0 rather than the "vacuously 1.0" a naive
      // 0/0 -> 1 convention would give. Documented behavior, not a bug:
      // intersection/union of two empty sets is 0/0, and the implementation
      // defines that as "no similarity" rather than "total similarity". We
      // assert the ACTUAL contract here, not the naively-expected one.
      final series = consecutiveJaccardSeries([<String>{}, <String>{}, <String>{}]);
      expect(series, everyElement(equals(0.0)));
    });

    test('disjoint consecutive sets -> 0.0', () {
      final series = consecutiveJaccardSeries([
        {'a.dart'},
        {'b.dart'},
        {'c.dart'},
      ]);
      expect(series, everyElement(equals(0.0)));
    });
  });
}
