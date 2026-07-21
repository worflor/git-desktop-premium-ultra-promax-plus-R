// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Serialization roundtrip + malformed-input-robustness fuzz tests for
// Manifold's DTOs. `VersionVector`/`LogosEdit` byte codecs are covered by
// the separate logos_edits_codec suite.
//
// Two families of law: (1) roundtrip identity for DTOs owning both a
// `toX`/`fromX` pair, with generators pre-satisfying each class's own
// documented normalization (trim/clamp/non-blank) so the test exercises
// real identity, not the normalization; (2) malformed-input robustness
// for the parse-only DTOs in dtos.dart that consume untrusted git/gh/
// gitea/glab process JSON — missing/null/unknown-extra keys must never
// throw, per each class's `?? default` / `is T ?` leniency contract.
//
// Most of these classes used to read `j['x'] as T?`, which is null-safe but
// not type-safe, so a present-but-wrong-typed value threw instead of
// defaulting. Fixed for B16/B17/B18 (dtos.dart, review_ratchet.dart,
// shadow_coupling_cache.dart, ai_api_keys_store.dart, ai_audit_store.dart)
// via lib/backend/json_safety.dart's total readers — the wrong-type repros
// below now assert `returnsNormally`. See
// docs/architecture/test-hardening-bug-dossier.md (B15-B19) for the fuller
// writeup; B15 (SpectralBasis) is a separate, still-open bug.
// `RepositoryStatusFile` is the positive control proving the other
// classes aren't unsafe by accident (its fields go through `.toString()`,
// which cannot throw).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:git_desktop/backend/ai_api_keys_store.dart';
import 'package:git_desktop/backend/ai_audit_store.dart';
import 'package:git_desktop/backend/desk_issue.dart';
import 'package:git_desktop/backend/desk_pr.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/graph/csr_builder.dart';
import 'package:git_desktop/backend/json_safety.dart';
import 'package:git_desktop/backend/logos_core.dart';
import 'package:git_desktop/backend/remote_types.dart' show PrReviewer;
import 'package:git_desktop/backend/review_logos.dart' show ClaimShape;
import 'package:git_desktop/backend/review_ratchet.dart';
import 'package:git_desktop/backend/shadow_coupling_cache.dart';

import '../support/gen.dart';
import '../support/prop.dart';

// ---------------------------------------------------------------------------
// Shared generators
// ---------------------------------------------------------------------------

CsrGraph _toCsrGraph(TestGraph g) => buildSymmetricCsrGraph(
      n: g.n,
      edges: [for (final (a, b, w) in g.edges) CsrEdge(a, b, w)],
    );

/// Half ASCII, half Unicode-hostile — every hostile-string field below
/// gets a mix of boring and adversarial content across a fuzz run.
String _text(Rng rng, {int maxLen = 24}) => rng.nextBool()
    ? genAscii(maxLen: maxLen)(rng)
    : genUnicodeHostile(maxLen: (maxLen / 2).ceil())(rng);

/// [_text], pre-trimmed. Several DTOs below `.trim()` specific fields in
/// their own `fromJson` (DeskIssue.title/authorIdentity, DeskPr.title/
/// headRef/baseRef/authorIdentity). `trim()` is idempotent, so trimming
/// up front makes the parser's own trim a no-op — the roundtrip law then
/// tests the DTO's real identity contract instead of tripping its
/// documented normalization.
String _trimmedText(Rng rng, {int maxLen = 24}) =>
    _text(rng, maxLen: maxLen).trim();

/// A non-blank string — several DTOs treat a blank-after-trim string as
/// "absent" (AiApiKeyEntry.baseUrl, AiApiKeysSnapshot entries keyed on a
/// non-blank apiKey). Falls back to [fallback] on the rare draw that's
/// blank after trimming, so callers never accidentally exercise that
/// (separately documented, not-a-bug) normalization here.
String _nonBlank(Rng rng, String fallback) {
  final s = _text(rng, maxLen: 24);
  return s.trim().isEmpty ? fallback : s;
}

/// Millisecond-granular so `toIso8601String()` / `DateTime.tryParse()`
/// round-trip with zero precision loss (no microsecond remainder to
/// lose in the string form).
DateTime _genDateTime(Rng rng) => DateTime.fromMillisecondsSinceEpoch(
      rng.intBetween(0, 4102444800000), // 1970-01-01 .. 2100-01-01
    );

List<String> _stringList(Rng rng, {int maxLen = 4}) => List<String>.generate(
      rng.intBetween(0, maxLen),
      (_) => _text(rng, maxLen: 12),
    );

List<int> _intList(Rng rng, {int maxLen = 4}) => List<int>.generate(
      rng.intBetween(0, maxLen),
      (_) => rng.intBetween(0, 100000),
    );

void main() {
  // ===========================================================================
  // json_safety.dart — the total readers every parser below now depends on.
  // Pins the numeric contract explicitly (raised in external review): an
  // integral double is accepted, a FRACTIONAL one is rejected rather than
  // silently truncated, because truncating fabricates a value the sender
  // never transmitted. Non-finite is rejected too (jsonDecode('1e400') is
  // Infinity with no parse error, and .toInt() on it throws).
  // ===========================================================================
  group('json_safety numeric readers', () {
    test('asIntOrNull accepts ints and exactly-integral doubles', () {
      expect(asIntOrNull(3), 3);
      expect(asIntOrNull(-7), -7);
      expect(asIntOrNull(3.0), 3);
      expect(asIntOrNull(-7.0), -7);
      expect(asIntOrNull(0.0), 0);
    });

    test('asIntOrNull rejects fractional doubles (no silent truncation)', () {
      expect(asIntOrNull(3.7), isNull);
      expect(asIntOrNull(-0.5), isNull);
      expect(asIntOr(3.7, 42), 42, reason: 'falls back, does not truncate to 3');
    });

    test('asIntOrNull / asDoubleOrNull reject non-finite and non-numbers', () {
      for (final bad in <Object?>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        '5',
        true,
        <String, Object?>{},
        <Object?>[],
        null,
      ]) {
        expect(asIntOrNull(bad), isNull, reason: 'asIntOrNull($bad)');
        expect(asDoubleOrNull(bad), isNull, reason: 'asDoubleOrNull($bad)');
      }
      expect(asIntOr(double.nan, 9), 9);
      expect(asDoubleOr('x', 1.5), 1.5);
    });

    test('asDoubleOrNull accepts any finite num, fractional included', () {
      expect(asDoubleOrNull(3), 3.0);
      expect(asDoubleOrNull(3.7), 3.7);
    });
  });

  // ===========================================================================
  // SpectralBasis.toBytes / fromBytes — lib/backend/logos_core.dart
  // ===========================================================================
  group('SpectralBasis.toBytes / fromBytes — roundtrip identity', () {
    test('random small graphs, random k, with/without labels roundtrip exactly',
        () {
      forAll<SpectralBasis>(
        (rng) {
          final graph = genConnectedGraph(maxNodes: 12)(rng);
          final csr = _toCsrGraph(graph);
          final k = rng.intBetween(1, graph.n.clamp(1, 4));
          final labeled = rng.nextBool();
          return SpectralBasis.fromGraph(
            csr,
            k,
            nodePaths: labeled
                ? List<String>.generate(graph.n, (i) => genRelPath()(rng))
                : null,
          );
        },
        count: 80 * fuzzScale(),
        describe: 'SpectralBasis roundtrip',
        check: (basis) {
          final restored = SpectralBasis.fromBytes(basis.toBytes());
          expect(restored.n, basis.n);
          expect(restored.k, basis.k);
          expect(restored.signature, basis.signature);
          expect(restored, equals(basis)); // SpectralBasis.== on signature
          expect(restored.eigenvalues, equals(basis.eigenvalues));
          expect(restored.eigenvectors, equals(basis.eigenvectors));
          expect(restored.nodePaths, equals(basis.nodePaths));
        },
      );
    });
  });

  group('SpectralBasis.fromBytes — malformed-input robustness', () {
    test(
      'fixed: fromBytes(empty bytes) throws the documented FormatException '
      '(length guard added ahead of any fixed-offset read)',
      () {
        expect(
          () => SpectralBasis.fromBytes(Uint8List(0)),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'fixed: fromBytes(1 byte) throws the documented FormatException '
      '(length guard added ahead of any fixed-offset read)',
      () {
        expect(
          () => SpectralBasis.fromBytes(Uint8List.fromList(const [0x00])),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('wrong magic correctly throws the documented FormatException', () {
      // 28 zero bytes: magic 0 != the real 0x4c475300 magic. Long enough
      // that this exercises the magic check itself, not a length short-fall.
      expect(
        () => SpectralBasis.fromBytes(Uint8List(28)),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'correct magic, unsupported version correctly throws the documented '
      'FormatException',
      () {
        final bytes = Uint8List(28);
        final bd = ByteData.view(bytes.buffer);
        bd.setUint32(0, 0x4c475300, Endian.little);
        bd.setUint32(4, 2, Endian.little); // version 2: unsupported
        expect(
          () => SpectralBasis.fromBytes(bytes),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'fixed: every truncated prefix of a valid encoding throws the '
      'documented FormatException, never a RangeError — length guards now '
      'cover the header, the fixed value/vector payload, and each label '
      'read',
      () {
        final rng = Rng(0xBEEF01);
        final trials = 6 * fuzzScale();
        for (var trial = 0; trial < trials; trial++) {
          final graph = genConnectedGraph(maxNodes: 10)(rng);
          final csr = _toCsrGraph(graph);
          final k = rng.intBetween(1, graph.n.clamp(1, 4));
          final labeled = rng.nextBool();
          final basis = SpectralBasis.fromGraph(
            csr,
            k,
            nodePaths: labeled
                ? List<String>.generate(graph.n, (i) => genRelPath()(rng))
                : null,
          );
          final bytes = basis.toBytes();
          for (var len = 0; len < bytes.length; len++) {
            final prefix = bytes.sublist(0, len);
            expect(
              () => SpectralBasis.fromBytes(prefix),
              throwsA(isA<FormatException>()),
              reason: 'truncated prefix (len=$len of ${bytes.length}, '
                  'trial=$trial, n=${basis.n} k=${basis.k} '
                  'labeled=$labeled) should throw FormatException',
            );
          }
        }
      },
    );

    test(
      'random garbage bytes of random length never silently produce an '
      'inconsistent basis — always the FormatException/RangeError family',
      () {
        forAll<Uint8List>(
          (rng) {
            final len = rng.intBetween(0, 400);
            return Uint8List.fromList(
              List<int>.generate(len, (_) => rng.intBetween(0, 255)),
            );
          },
          count: 150 * fuzzScale(),
          describe: 'SpectralBasis.fromBytes garbage fuzz',
          check: (garbage) {
            try {
              final basis = SpectralBasis.fromBytes(garbage);
              // Astronomically unlikely (needs bytes 0..7 to randomly
              // match magic+version) but if it ever "succeeds", the
              // result must at least be structurally sane.
              expect(basis.k, greaterThanOrEqualTo(0));
              expect(basis.n, greaterThanOrEqualTo(0));
            } on FormatException {
              // controlled, documented failure mode.
            } on RangeError {
              // Should no longer occur now that length guards cover the
              // header, fixed payload, and each label read — kept as a
              // defensive catch, not an expected outcome.
            }
          },
        );
      },
    );
  });

  // ===========================================================================
  // ShadowCouplingCacheData — lib/backend/shadow_coupling_cache.dart
  // ===========================================================================
  group('ShadowCouplingCacheData', () {
    Gen<ShadowCouplingCacheData> genCache() {
      return (rng) {
        final edgeCount = rng.intBetween(0, 5);
        final edges = <String, Map<String, double>>{};
        for (var i = 0; i < edgeCount; i++) {
          final innerCount = rng.intBetween(1, 4); // non-empty: fromJson
          // drops empty inner maps by design, see mergeWith/fromJson.
          final inner = <String, double>{
            for (var j = 0; j < innerCount; j++)
              'f${i}_$j${genRelPath()(rng)}': genDouble(min: -1e6, max: 1e6)(rng),
          };
          edges['file$i${genRelPath()(rng)}'] = inner;
        }
        final typeCount = rng.intBetween(0, 4);
        final types = <String, int>{
          for (var i = 0; i < typeCount; i++) 'type$i': rng.intBetween(0, 100000),
        };
        return ShadowCouplingCacheData(
          headHash: _text(rng, maxLen: 40),
          discoveredAt: _genDateTime(rng),
          shadowCommitCount: rng.intBetween(0, 1000000),
          jaccardEdges: edges,
          edgeTypeCounts: types,
        );
      };
    }

    test('toJson/fromJson roundtrip', () {
      forAll<ShadowCouplingCacheData>(
        genCache(),
        count: 80 * fuzzScale(),
        describe: 'ShadowCouplingCacheData roundtrip',
        check: (data) {
          final restored = ShadowCouplingCacheData.fromJson(data.toJson());
          expect(restored.headHash, data.headHash);
          expect(restored.discoveredAt, data.discoveredAt);
          expect(restored.shadowCommitCount, data.shadowCommitCount);
          expect(restored.jaccardEdges, equals(data.jaccardEdges));
          expect(restored.edgeTypeCounts, equals(data.edgeTypeCounts));
        },
      );
    });

    test(
      'GENUINE BUG (B18, FIXED): fromJson tolerates a wrong-typed field '
      '(was the same `as T?` pattern as dtos.dart; now reads through '
      'json_safety, matching ShadowCouplingCache.load\'s own try/catch '
      'contract instead of relying on it to mask a throw)',
      () {
        expect(
          () => ShadowCouplingCacheData.fromJson(<String, dynamic>{
            'shadowCommitCount': 'not-a-number',
          }),
          returnsNormally,
        );
      },
    );
  });

  // ===========================================================================
  // ClaimOutcomeRatchet (+ _Bucket) — lib/backend/review_ratchet.dart
  // ===========================================================================
  group('ClaimOutcomeRatchet', () {
    Gen<ClaimShape> genShape() {
      return (rng) => ClaimShape(
            grounding: genDouble(min: 0, max: 1)(rng),
            verifiability: genDouble(min: 0, max: 1)(rng),
            reach: genDouble(min: 0, max: 1)(rng),
            coherence: genDouble(min: 0, max: 1)(rng),
            symbolCount: rng.intBetween(0, 20),
            textLength: rng.intBetween(0, 5000),
          );
    }

    test('toJsonString/fromJsonString preserves every bucket exactly', () {
      forAll<({ClaimOutcomeRatchet ratchet, List<ClaimShape> shapes})>(
        (rng) {
          final ratchet = ClaimOutcomeRatchet();
          final shapeCount = rng.intBetween(1, 8);
          final shapes = <ClaimShape>[];
          for (var i = 0; i < shapeCount; i++) {
            final shape = genShape()(rng);
            shapes.add(shape);
            final observations = rng.intBetween(0, 40);
            for (var o = 0; o < observations; o++) {
              ratchet.observe(shape: shape, verified: rng.nextBool());
            }
          }
          return (ratchet: ratchet, shapes: shapes);
        },
        count: 40 * fuzzScale(),
        describe: 'ClaimOutcomeRatchet roundtrip',
        check: (c) {
          final restored =
              ClaimOutcomeRatchet.fromJsonString(c.ratchet.toJsonString());
          expect(restored.bucketCount, c.ratchet.bucketCount);
          expect(restored.totalObservations, c.ratchet.totalObservations);
          for (final shape in c.shapes) {
            expect(restored.priorFor(shape), c.ratchet.priorFor(shape));
            expect(restored.observationCountFor(shape),
                c.ratchet.observationCountFor(shape));
          }
        },
      );
    });

    test(
      'fromJsonString tolerates broadly hostile garbage strings (beyond the '
      'fixed cases already pinned in review_ratchet_test.dart)',
      () {
        forAll<String>(
          (rng) => rng.nextBool()
              ? genUnicodeHostile(maxLen: 40)(rng)
              : genAscii(maxLen: 40)(rng),
          count: 100 * fuzzScale(),
          describe: 'ClaimOutcomeRatchet.fromJsonString hostile-string fuzz',
          check: (garbage) {
            expect(() => ClaimOutcomeRatchet.fromJsonString(garbage),
                returnsNormally);
          },
        );
      },
    );

    test(
      'GENUINE BUG (B16, FIXED): fromJsonString never throws on a '
      'structurally-valid bucket whose "a"/"r" value is present-but-wrong-'
      'typed, honoring its own doc comment ("malformed entries silently '
      'dropped ... never throwing") — was an uncaught TypeError because '
      '_Bucket.fromJson(value) ran inside decoded.forEach, outside the '
      'try/catch guarding json.decode; now each entry is parsed under its '
      'own try/catch and a bucket with a present-but-wrong-typed counter is '
      'DROPPED (a missing counter still defaults to 0 for older-schema '
      'tolerance) — dropping honors the doc contract; defaulting would '
      'fabricate an observation bucket that never existed',
      () {
        const bad = '{"5": {"a": "not-a-number", "r": 0}}';
        expect(() => ClaimOutcomeRatchet.fromJsonString(bad), returnsNormally);
        final restored = ClaimOutcomeRatchet.fromJsonString(bad);
        expect(restored.bucketCount, 0);
        expect(restored.totalObservations, 0);
        // Older-schema tolerance: a merely-missing counter is not malformed.
        final partial = ClaimOutcomeRatchet.fromJsonString('{"5": {"a": 3}}');
        expect(partial.bucketCount, 1);
        expect(partial.totalObservations, 3);
      },
    );
  });

  // ===========================================================================
  // DeskIssue / DeskIssueComment — lib/backend/desk_issue.dart
  // ===========================================================================
  group('DeskIssue', () {
    Gen<DeskIssue> genIssue() {
      return (rng) {
        final commentCount = rng.intBetween(0, 4);
        return DeskIssue(
          issueId: rng.intBetween(0, 1000000),
          title: _trimmedText(rng, maxLen: 30),
          body: _text(rng, maxLen: 60),
          state: rng.pick(const ['OPEN', 'CLOSED']),
          authorIdentity: _trimmedText(rng, maxLen: 20),
          createdAt: _genDateTime(rng),
          updatedAt: _genDateTime(rng),
          labels: _stringList(rng),
          assignees: _stringList(rng),
          addressedBy: _stringList(rng),
          comments: List<DeskIssueComment>.generate(
            commentCount,
            (_) => DeskIssueComment(
              author: _text(rng, maxLen: 16),
              body: _text(rng, maxLen: 40),
              at: _genDateTime(rng),
            ),
          ),
          remoteNumber: rng.nextBool() ? null : rng.intBetween(1, 999999),
        );
      };
    }

    void expectEqual(DeskIssue a, DeskIssue b) {
      expect(b.issueId, a.issueId);
      expect(b.title, a.title);
      expect(b.body, a.body);
      expect(b.state, a.state);
      expect(b.authorIdentity, a.authorIdentity);
      expect(b.createdAt, a.createdAt);
      expect(b.updatedAt, a.updatedAt);
      expect(b.labels, equals(a.labels));
      expect(b.assignees, equals(a.assignees));
      expect(b.addressedBy, equals(a.addressedBy));
      expect(b.comments.length, a.comments.length);
      for (var i = 0; i < a.comments.length; i++) {
        expect(b.comments[i].author, a.comments[i].author);
        expect(b.comments[i].body, a.comments[i].body);
        expect(b.comments[i].at, a.comments[i].at);
      }
      expect(b.remoteNumber, a.remoteNumber);
    }

    test('toJson/fromJson roundtrip', () {
      forAll<DeskIssue>(
        genIssue(),
        count: 100 * fuzzScale(),
        describe: 'DeskIssue json roundtrip',
        check: (issue) => expectEqual(issue, DeskIssue.fromJson(issue.toJson())),
      );
    });

    test('toBlob/fromBlob roundtrip (git-ref persisted form)', () {
      forAll<DeskIssue>(
        genIssue(),
        count: 60 * fuzzScale(),
        describe: 'DeskIssue blob roundtrip',
        check: (issue) =>
            expectEqual(issue, DeskIssue.fromBlob(issue.toBlob())),
      );
    });

    test('fromJson tolerates a fully empty map with sane defaults', () {
      final issue = DeskIssue.fromJson(<String, dynamic>{});
      expect(issue.issueId, 0);
      expect(issue.title, '');
      expect(issue.state, 'OPEN');
      expect(issue.labels, isEmpty);
      expect(issue.comments, isEmpty);
      expect(issue.remoteNumber, isNull);
    });
  });

  // ===========================================================================
  // DeskThreadEntry / DeskPr — lib/backend/desk_pr.dart
  // ===========================================================================
  group('DeskPr', () {
    Gen<DeskPr> genPr() {
      return (rng) {
        final reviewerCount = rng.intBetween(0, 3);
        final threadCount = rng.intBetween(0, 4);
        return DeskPr(
          deskId: rng.intBetween(0, 1000000),
          title: _trimmedText(rng, maxLen: 30),
          body: _text(rng, maxLen: 60),
          headRef: _trimmedText(rng, maxLen: 20),
          baseRef: _trimmedText(rng, maxLen: 20),
          state: rng.pick(const ['OPEN', 'CLOSED', 'MERGED']),
          isDraft: rng.nextBool(),
          authorIdentity: _trimmedText(rng, maxLen: 20),
          createdAt: _genDateTime(rng),
          updatedAt: _genDateTime(rng),
          reviewers: List<PrReviewer>.generate(
            reviewerCount,
            (_) => PrReviewer(
              login: _text(rng, maxLen: 16),
              state: rng.pick(const [
                'PENDING',
                'APPROVED',
                'CHANGES_REQUESTED',
                'COMMENTED',
                'DISMISSED',
              ]),
            ),
          ),
          labels: _stringList(rng),
          assignees: _stringList(rng),
          linkedIssues: _intList(rng),
          linkedRemoteIssues: _intList(rng),
          thread: List<DeskThreadEntry>.generate(
            threadCount,
            (_) => DeskThreadEntry(
              author: _text(rng, maxLen: 16),
              body: _text(rng, maxLen: 40),
              at: _genDateTime(rng),
              verdict: rng
                  .pick(const ['', 'APPROVED', 'CHANGES_REQUESTED', 'COMMENTED']),
            ),
          ),
          additions: rng.intBetween(0, 5000),
          deletions: rng.intBetween(0, 5000),
          changedFiles: rng.intBetween(0, 200),
          mergeable: rng.pick(const ['MERGEABLE', 'CONFLICTING', 'UNKNOWN']),
          remoteNumber: rng.nextBool() ? null : rng.intBetween(1, 999999),
        );
      };
    }

    void expectEqual(DeskPr a, DeskPr b) {
      expect(b.deskId, a.deskId);
      expect(b.title, a.title);
      expect(b.body, a.body);
      expect(b.headRef, a.headRef);
      expect(b.baseRef, a.baseRef);
      expect(b.state, a.state);
      expect(b.isDraft, a.isDraft);
      expect(b.authorIdentity, a.authorIdentity);
      expect(b.createdAt, a.createdAt);
      expect(b.updatedAt, a.updatedAt);
      expect(b.reviewers.length, a.reviewers.length);
      for (var i = 0; i < a.reviewers.length; i++) {
        expect(b.reviewers[i].login, a.reviewers[i].login);
        expect(b.reviewers[i].state, a.reviewers[i].state);
      }
      expect(b.labels, equals(a.labels));
      expect(b.assignees, equals(a.assignees));
      expect(b.linkedIssues, equals(a.linkedIssues));
      expect(b.linkedRemoteIssues, equals(a.linkedRemoteIssues));
      expect(b.thread.length, a.thread.length);
      for (var i = 0; i < a.thread.length; i++) {
        expect(b.thread[i].author, a.thread[i].author);
        expect(b.thread[i].body, a.thread[i].body);
        expect(b.thread[i].at, a.thread[i].at);
        expect(b.thread[i].verdict, a.thread[i].verdict);
      }
      expect(b.additions, a.additions);
      expect(b.deletions, a.deletions);
      expect(b.changedFiles, a.changedFiles);
      expect(b.mergeable, a.mergeable);
      expect(b.remoteNumber, a.remoteNumber);
    }

    test('toJson/fromJson roundtrip', () {
      forAll<DeskPr>(
        genPr(),
        count: 100 * fuzzScale(),
        describe: 'DeskPr json roundtrip',
        check: (pr) => expectEqual(pr, DeskPr.fromJson(pr.toJson())),
      );
    });

    test('toBlob/fromBlob roundtrip (git-ref persisted form)', () {
      forAll<DeskPr>(
        genPr(),
        count: 60 * fuzzScale(),
        describe: 'DeskPr blob roundtrip',
        check: (pr) => expectEqual(pr, DeskPr.fromBlob(pr.toBlob())),
      );
    });

    test('fromJson tolerates a fully empty map with sane defaults', () {
      final pr = DeskPr.fromJson(<String, dynamic>{});
      expect(pr.deskId, 0);
      expect(pr.title, '');
      expect(pr.baseRef, 'main');
      expect(pr.state, 'OPEN');
      expect(pr.mergeable, 'UNKNOWN');
      expect(pr.reviewers, isEmpty);
      expect(pr.thread, isEmpty);
      expect(pr.remoteNumber, isNull);
    });
  });

  // ===========================================================================
  // AiApiKeyEntry / AiApiKeysSnapshot — lib/backend/ai_api_keys_store.dart
  // ===========================================================================
  group('AiApiKeyEntry / AiApiKeysSnapshot', () {
    Gen<AiApiKeyEntry> genEntry() {
      return (rng) => AiApiKeyEntry(
            apiKey: _nonBlank(rng, 'key'),
            baseUrl:
                rng.nextBool() ? null : _nonBlank(rng, 'https://example.test'),
          );
    }

    test('AiApiKeyEntry.toJson/fromJson roundtrip', () {
      forAll<AiApiKeyEntry>(
        genEntry(),
        count: 100 * fuzzScale(),
        describe: 'AiApiKeyEntry roundtrip',
        check: (e) {
          final restored = AiApiKeyEntry.fromJson(e.toJson());
          expect(restored.apiKey, e.apiKey);
          expect(restored.baseUrl, e.baseUrl);
        },
      );
    });

    test('AiApiKeysSnapshot.toJson/fromJson roundtrip', () {
      forAll<Map<String, AiApiKeyEntry>>(
        (rng) {
          final n = rng.intBetween(0, 6);
          return <String, AiApiKeyEntry>{
            for (var i = 0; i < n; i++) 'provider$i': genEntry()(rng),
          };
        },
        count: 80 * fuzzScale(),
        describe: 'AiApiKeysSnapshot roundtrip',
        check: (entries) {
          final snapshot = AiApiKeysSnapshot(entries: entries);
          final restored = AiApiKeysSnapshot.fromJson(snapshot.toJson());
          expect(
              restored.entries.keys.toSet(), equals(snapshot.entries.keys.toSet()));
          for (final key in snapshot.entries.keys) {
            expect(restored.entries[key]!.apiKey, snapshot.entries[key]!.apiKey);
            expect(
                restored.entries[key]!.baseUrl, snapshot.entries[key]!.baseUrl);
          }
        },
      );
    });

    test(
      'GENUINE BUG (B18, FIXED): AiApiKeysSnapshot.fromJson tolerates a '
      'wrong-typed nested apiKey (was the same `as T?` pattern; now reads '
      "through json_safety, matching AiApiKeysStore.load's own try/catch "
      'contract instead of relying on it to mask a throw)',
      () {
        expect(
          () => AiApiKeysSnapshot.fromJson(<String, dynamic>{
            'openai': <String, dynamic>{'apiKey': 12345},
          }),
          returnsNormally,
        );
      },
    );
  });

  // ===========================================================================
  // AiAuditEntryData — lib/backend/ai_audit_store.dart
  // ===========================================================================
  group('AiAuditEntryData', () {
    Gen<AiAuditEntryData> genEntry() {
      return (rng) => AiAuditEntryData(
            id: _text(rng, maxLen: 20),
            event: _text(rng, maxLen: 20),
            providerId: _text(rng, maxLen: 20),
            repositoryHint: _text(rng, maxLen: 30),
            diffScopePath: rng.nextBool() ? null : genRelPath()(rng),
            promptPreview: _text(rng, maxLen: 60),
            outputPreview: _text(rng, maxLen: 60),
            ok: rng.nextBool(),
            errorCode: rng.nextBool() ? null : _text(rng, maxLen: 16),
            createdAt: _genDateTime(rng).toIso8601String(),
          );
    }

    test('toJson/fromJson roundtrip', () {
      forAll<AiAuditEntryData>(
        genEntry(),
        count: 100 * fuzzScale(),
        describe: 'AiAuditEntryData roundtrip',
        check: (e) {
          final restored = AiAuditEntryData.fromJson(e.toJson());
          expect(restored.id, e.id);
          expect(restored.event, e.event);
          expect(restored.providerId, e.providerId);
          expect(restored.repositoryHint, e.repositoryHint);
          expect(restored.diffScopePath, e.diffScopePath);
          expect(restored.promptPreview, e.promptPreview);
          expect(restored.outputPreview, e.outputPreview);
          expect(restored.ok, e.ok);
          expect(restored.errorCode, e.errorCode);
          expect(restored.createdAt, e.createdAt);
        },
      );
    });

    test(
      'GENUINE BUG (B18, FIXED): fromJson tolerates a wrong-typed required '
      'field — used a bare `as String` (not even `as String?`), so this one '
      'never even attempted the leniency pattern used elsewhere; now reads '
      "through json_safety, matching AiAuditStore._loadEntries's own "
      'per-line try/catch contract instead of relying on it to mask a throw',
      () {
        expect(
          () => AiAuditEntryData.fromJson(<String, dynamic>{
            'id': 'x',
            'event': 'e',
            'providerId': 'p',
            'repositoryHint': 'r',
            'promptPreview': '',
            'outputPreview': '',
            'ok': true,
            'createdAt': 123,
          }),
          returnsNormally,
        );
      },
    );
  });

  // ===========================================================================
  // MuseQuiverEntry — lib/backend/dtos.dart
  // ===========================================================================
  group('MuseQuiverEntry', () {
    test(
      'toJson/fromJson roundtrip (count kept within the documented 1..5 '
      'clamp so the roundtrip tests identity, not the clamp itself)',
      () {
        forAll<MuseQuiverEntry>(
          (rng) => MuseQuiverEntry(
            kind: rng.pick(MuseStrandKind.values),
            count: rng.intBetween(1, 5),
          ),
          count: 100 * fuzzScale(),
          describe: 'MuseQuiverEntry roundtrip',
          check: (entry) {
            final restored = MuseQuiverEntry.fromJson(entry.toJson());
            expect(restored, isNotNull);
            expect(restored!.kind, entry.kind);
            expect(restored.count, entry.count);
          },
        );
      },
    );

    test('fromJson tolerates malformed input by returning null, never throwing',
        () {
      forAll<Object?>(
        (rng) {
          switch (rng.intBetween(0, 8)) {
            case 0:
              return null;
            case 1:
              return rng.intBetween(-100, 100);
            case 2:
              return _text(rng);
            case 3:
              return <dynamic>[rng.intBetween(0, 9), _text(rng, maxLen: 6)];
            case 4:
              return <String, dynamic>{};
            case 5:
              return <String, dynamic>{
                'kind': rng.intBetween(0, 9),
                'count': rng.intBetween(1, 5),
              };
            case 6:
              return <String, dynamic>{
                'kind': genUnicodeHostile(maxLen: 8)(rng),
                'count': 1,
              };
            case 7:
              return <String, dynamic>{'kind': 'spark', 'count': _text(rng)};
            default:
              return <String, dynamic>{'kind': 'spark'};
          }
        },
        count: 80 * fuzzScale(),
        describe: 'MuseQuiverEntry.fromJson malformed tolerance',
        check: (bad) {
          expect(() => MuseQuiverEntry.fromJson(bad), returnsNormally);
        },
      );
    });
  });

  // ===========================================================================
  // Parse-only external-wire parsers — lib/backend/dtos.dart
  //
  // These consume untrusted git/gh/gitea/glab process JSON. No toJson of
  // their own — the law here is robustness, not roundtrip identity.
  // ===========================================================================
  _runParseOnlyWireParserSuite();
}

// ---------------------------------------------------------------------------
// Parse-only wire-parser harness
// ---------------------------------------------------------------------------

/// Deliberately mismatched JSON-shaped values for the wrong-type fuzz
/// below — never `null` (that's the separate missing/null-tolerance
/// law), always a real value of a plausible-but-wrong JSON type: exactly
/// what a schema drift in the upstream git/gh/gitea/glab JSON would
/// produce.
List<Object> _wrongTypePool(Rng rng) => <Object>[
      rng.intBetween(-999999, 999999),
      genDouble(min: -1e6, max: 1e6)(rng),
      rng.nextBool(),
      _text(rng, maxLen: 12),
      <dynamic>[_text(rng, maxLen: 6), rng.intBetween(0, 9)],
      <String, dynamic>{'unexpected': _text(rng, maxLen: 6)},
    ];

Map<String, dynamic> _mutateWrongType(
  Map<String, dynamic> good,
  List<String> keys,
  Rng rng,
) {
  final mutated = Map<String, dynamic>.from(good);
  final howMany = rng.intBetween(1, keys.length);
  final chosen = rng.sample(keys, howMany);
  for (final key in chosen) {
    mutated[key] = rng.pick(_wrongTypePool(rng));
  }
  return mutated;
}

/// Every parse-only DTO below defaults each field via `?? <default>` (or
/// an `is T ?` guard) on a MISSING or explicitly-`null` key — that's the
/// documented, intended leniency contract for reading untrusted process
/// JSON. This sweeps that contract with fuzzed maps: each valid key
/// independently omitted, nulled, or kept, plus a random unknown extra
/// key thrown in (schema drift adding a field this app doesn't know
/// about yet).
void _expectLenientToMissingAndNull({
  required String label,
  required List<String> validKeys,
  required Map<String, dynamic> Function(Rng rng) genGoodMap,
  required void Function(Map<String, dynamic>) callFromJson,
  int seed = 0x900D,
}) {
  test('$label.fromJson tolerates missing/null keys + unknown extras', () {
    forAll<Map<String, dynamic>>(
      (rng) {
        final good = genGoodMap(rng);
        final mutated = <String, dynamic>{};
        for (final key in validKeys) {
          final roll = rng.intBetween(0, 2);
          if (roll == 0) continue; // omit entirely
          if (roll == 1) {
            mutated[key] = null; // explicit null
            continue;
          }
          mutated[key] = good[key]; // keep the valid value
        }
        if (rng.nextBool()) {
          mutated['__unknown_${rng.intBetween(0, 1 << 30)}'] = _text(rng);
        }
        return mutated;
      },
      count: 80 * fuzzScale(),
      seed: seed,
      describe: '$label missing/null tolerance',
      check: (mutated) => expect(() => callFromJson(mutated), returnsNormally),
    );
  });
}

/// Multi-field wrong-type canary: swaps a random non-empty subset of
/// [validKeys] for a deliberately mismatched value and classifies the
/// outcome. This is NOT a "must never throw" law — most classes below DO
/// throw today (that's the genuine-bug family documented one field at a
/// time via [_expectGenuineWrongTypeBug]) — it's a regression net that
/// fails loudly only if a mutation ever produces something OUTSIDE the
/// already-catalogued TypeError/NoSuchMethodError/RangeError family.
void _wrongTypeFuzzCanary({
  required String label,
  required Map<String, dynamic> Function(Rng rng) genGoodMap,
  required List<String> validKeys,
  required void Function(Map<String, dynamic>) callFromJson,
  int seed = 0xC0FFEE,
}) {
  test('$label.fromJson wrong-type fuzz stays within known failure modes', () {
    forAll<Map<String, dynamic>>(
      (rng) => _mutateWrongType(genGoodMap(rng), validKeys, rng),
      count: 120 * fuzzScale(),
      seed: seed,
      describe: '$label wrong-type canary',
      check: (mutated) {
        try {
          callFromJson(mutated);
        } catch (e) {
          expect(
            e,
            anyOf(isA<TypeError>(), isA<NoSuchMethodError>(), isA<RangeError>()),
            reason: 'unexpected exception class ${e.runtimeType} for '
                'malformed input $mutated',
          );
        }
      },
    );
  });
}

/// GENUINE BUG (B17, FIXED): dtos.dart's parse-only classes used to read
/// `j['x'] as T?`, which is only null-safe, not type-safe — a wrong-type-
/// but-present JSON value threw instead of falling back to the class's own
/// documented default. Every class exercised via this helper now reads
/// through lib/backend/json_safety.dart's total readers (asStringOr,
/// asIntOr, asBoolOr, asDoubleOrNull, asMapOrNull, asListOrNull), so the
/// wrong-type repro below returns normally instead of throwing. Kept as a
/// single assertion per class so a regression back to a hard `as T?` cast
/// fails loudly.
void _expectGenuineWrongTypeBug({
  required String label,
  required String fieldNote,
  required Map<String, dynamic> badMap,
  required void Function(Map<String, dynamic>) callFromJson,
}) {
  test(
    '$label.fromJson: tolerates wrong-type $fieldNote (fixed via '
    'json_safety, B17)',
    () {
      expect(
        () => callFromJson(badMap),
        returnsNormally,
        reason: 'repro map: $badMap',
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Parse-only wire-parser "good JSON" generators
// ---------------------------------------------------------------------------

Map<String, dynamic> _goodStatusFileJson(Rng rng) => <String, dynamic>{
      'path': genRelPath()(rng),
      'staged': rng.pick(const ['M', 'A', 'D', '.', '?']),
      'unstaged': rng.pick(const ['M', 'A', 'D', '.', '?']),
    };

Map<String, dynamic> _goodRepositoryStatusJson(Rng rng) => <String, dynamic>{
      'branch': _text(rng, maxLen: 20),
      'upstream': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'ahead': rng.intBetween(0, 50),
      'behind': rng.intBetween(0, 50),
      'files':
          List<Map<String, dynamic>>.generate(
              rng.intBetween(0, 3), (_) => _goodStatusFileJson(rng)),
      'hasHeadCommit': rng.nextBool(),
    };

Map<String, dynamic> _goodCommitHistoryEntryJson(Rng rng) => <String, dynamic>{
      'commitHash': _text(rng, maxLen: 40),
      'shortHash': _text(rng, maxLen: 8),
      'parentHashes': _stringList(rng),
      'refNames': _stringList(rng),
      'isMerge': rng.nextBool(),
      'subject': _text(rng, maxLen: 40),
      'authorName': _text(rng, maxLen: 20),
      'authorEmail': _text(rng, maxLen: 20),
      'authoredAt': _genDateTime(rng).toIso8601String(),
    };

Map<String, dynamic> _goodCommitFileStatJson(Rng rng) => <String, dynamic>{
      'path': genRelPath()(rng),
      'additions': rng.intBetween(0, 500),
      'deletions': rng.intBetween(0, 500),
      'changeType': rng.pick(const ['M', 'A', 'D', 'R', 'C', 'T', 'U']),
    };

Map<String, dynamic> _goodCommitDetailJson(Rng rng) => <String, dynamic>{
      'commitHash': _text(rng, maxLen: 40),
      'shortHash': _text(rng, maxLen: 8),
      'subject': _text(rng, maxLen: 40),
      'body': _text(rng, maxLen: 80),
      'authorName': _text(rng, maxLen: 20),
      'authorEmail': _text(rng, maxLen: 20),
      'authoredAt': _genDateTime(rng).toIso8601String(),
      'filesChanged': rng.intBetween(0, 20),
      'additions': rng.intBetween(0, 500),
      'deletions': rng.intBetween(0, 500),
      'files':
          List<Map<String, dynamic>>.generate(
              rng.intBetween(0, 3), (_) => _goodCommitFileStatJson(rng)),
    };

Map<String, dynamic> _goodBranchInfoJson(Rng rng) => <String, dynamic>{
      'name': _text(rng, maxLen: 20),
      'current': rng.nextBool(),
      'upstream': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'ahead': rng.intBetween(0, 50),
      'behind': rng.intBetween(0, 50),
      'gone': rng.nextBool(),
      'lastCommitAt':
          rng.nextBool() ? null : _genDateTime(rng).toIso8601String(),
      'squashMerged': rng.nextBool() ? null : rng.nextBool(),
      'absorbed': rng.nextBool() ? null : rng.nextBool(),
      'absorbedWitness': rng.nextBool() ? null : _text(rng, maxLen: 20),
    };

Map<String, dynamic> _goodTagEntryJson(Rng rng) => <String, dynamic>{
      'name': _text(rng, maxLen: 20),
      'tagType': rng.pick(const ['lightweight', 'annotated']),
      'targetHash': rng.nextBool() ? null : _text(rng, maxLen: 40),
      'createdAt': rng.nextBool() ? null : _genDateTime(rng).toIso8601String(),
      'creatorName': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'subject': rng.nextBool() ? null : _text(rng, maxLen: 40),
    };

Map<String, dynamic> _goodReflogEntryJson(Rng rng) => <String, dynamic>{
      'commitHash': _text(rng, maxLen: 40),
      'shortHash': _text(rng, maxLen: 8),
      'refSelector': _text(rng, maxLen: 20),
      'actionSummary': _text(rng, maxLen: 40),
      'authorName': _text(rng, maxLen: 20),
      'authoredAt': _genDateTime(rng).toIso8601String(),
    };

Map<String, dynamic> _goodCommitSearchResultJson(Rng rng) => <String, dynamic>{
      'commit_hash': _text(rng, maxLen: 40),
      'short_hash': _text(rng, maxLen: 8),
      'subject': _text(rng, maxLen: 60),
      'author_name': _text(rng, maxLen: 20),
      'authored_at': _genDateTime(rng).toIso8601String(),
      'match_context': _text(rng, maxLen: 60),
    };

Map<String, dynamic> _goodBlameLineJson(Rng rng) => <String, dynamic>{
      'lineNumber': rng.intBetween(0, 5000),
      'commitHash': _text(rng, maxLen: 40),
      'shortHash': _text(rng, maxLen: 8),
      'authorName': _text(rng, maxLen: 20),
      'authoredAt': _genDateTime(rng).toIso8601String(),
      'lineContent': _text(rng, maxLen: 60),
    };

Map<String, dynamic> _goodSyncDataJson(Rng rng) => <String, dynamic>{
      'operation': rng.pick(const ['pull', 'push', 'fetch']),
      'remote': _text(rng, maxLen: 20),
      'branch': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'output': _text(rng, maxLen: 60),
    };

Map<String, dynamic> _goodAiProviderStatusJson(Rng rng) => <String, dynamic>{
      'id': _text(rng, maxLen: 20),
      'available': rng.nextBool(),
      'binary': _text(rng, maxLen: 20),
      'planName': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'resolvedBinary': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'detectionSource': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'healthCheck': rng.nextBool() ? null : _text(rng, maxLen: 20),
    };

Map<String, dynamic> _goodAiProviderListJson(Rng rng) => <String, dynamic>{
      'providers': List<Map<String, dynamic>>.generate(
          rng.intBetween(0, 3), (_) => _goodAiProviderStatusJson(rng)),
    };

Map<String, dynamic> _goodAiModelOptionJson(Rng rng) => <String, dynamic>{
      'value': _text(rng, maxLen: 20),
      'modelId': _text(rng, maxLen: 20),
      'providerId': _text(rng, maxLen: 20),
      'providerLabel': _text(rng, maxLen: 20),
      'planName': rng.nextBool() ? null : _text(rng, maxLen: 20),
      'label': _text(rng, maxLen: 20),
      'description': _text(rng, maxLen: 40),
      'promptPricePer1m': rng.nextBool() ? null : genDouble(min: 0, max: 100)(rng),
      'completionPricePer1m':
          rng.nextBool() ? null : genDouble(min: 0, max: 100)(rng),
      'supportsReasoning': rng.nextBool(),
      'hasFastTier': rng.nextBool(),
    };

Map<String, dynamic> _goodAiModelCategoryJson(Rng rng) => <String, dynamic>{
      'id': _text(rng, maxLen: 20),
      'label': _text(rng, maxLen: 20),
      'description': rng.nextBool() ? null : _text(rng, maxLen: 40),
      'models': List<Map<String, dynamic>>.generate(
          rng.intBetween(0, 3), (_) => _goodAiModelOptionJson(rng)),
    };

Map<String, dynamic> _goodAiModelOptionListJson(Rng rng) => <String, dynamic>{
      'categories': List<Map<String, dynamic>>.generate(
          rng.intBetween(0, 3), (_) => _goodAiModelCategoryJson(rng)),
    };

Map<String, dynamic> _goodAppSettingsJson(Rng rng) => <String, dynamic>{
      'themeId': rng.pick(const ['aether', 'phosphor', 'glass']),
      'keybindingProfile': rng.pick(const ['classic', 'vim']),
      'sidebarWidthPx': rng.intBetween(180, 400),
      'aiReadOnlyDefault': rng.nextBool(),
    };

// ---------------------------------------------------------------------------
// Parse-only wire-parser test groups
// ---------------------------------------------------------------------------

void _runParseOnlyWireParserSuite() {
  group('RepositoryStatusFile.fromJson — robust via .toString(), no bug', () {
    const validKeys = ['path', 'staged', 'unstaged'];
    _expectLenientToMissingAndNull(
      label: 'RepositoryStatusFile',
      validKeys: validKeys,
      genGoodMap: _goodStatusFileJson,
      callFromJson: (m) => RepositoryStatusFile.fromJson(m),
    );

    test(
      'RepositoryStatusFile.fromJson tolerates ANY JSON value via '
      '.toString() — positive control proving the other 14 classes are '
      'not unsafe by accident',
      () {
        forAll<Map<String, dynamic>>(
          (rng) => _mutateWrongType(_goodStatusFileJson(rng), validKeys, rng),
          count: 80 * fuzzScale(),
          describe: 'RepositoryStatusFile wrong-type (expected robust)',
          check: (mutated) {
            expect(
                () => RepositoryStatusFile.fromJson(mutated), returnsNormally);
          },
        );
      },
    );
  });

  group('RepositoryStatus.fromJson', () {
    const validKeys = [
      'branch',
      'upstream',
      'ahead',
      'behind',
      'files',
      'hasHeadCommit',
    ];
    _expectLenientToMissingAndNull(
      label: 'RepositoryStatus',
      validKeys: validKeys,
      genGoodMap: _goodRepositoryStatusJson,
      callFromJson: (m) => RepositoryStatus.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'RepositoryStatus',
      genGoodMap: _goodRepositoryStatusJson,
      validKeys: validKeys,
      callFromJson: (m) => RepositoryStatus.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'RepositoryStatus',
      fieldNote: "'ahead' (String instead of int)",
      badMap: const <String, dynamic>{'ahead': 'not-a-number'},
      callFromJson: (m) => RepositoryStatus.fromJson(m),
    );
  });

  group('CommitHistoryEntry.fromJson', () {
    const validKeys = [
      'commitHash',
      'shortHash',
      'parentHashes',
      'refNames',
      'isMerge',
      'subject',
      'authorName',
      'authorEmail',
      'authoredAt',
    ];
    _expectLenientToMissingAndNull(
      label: 'CommitHistoryEntry',
      validKeys: validKeys,
      genGoodMap: _goodCommitHistoryEntryJson,
      callFromJson: (m) => CommitHistoryEntry.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'CommitHistoryEntry',
      genGoodMap: _goodCommitHistoryEntryJson,
      validKeys: validKeys,
      callFromJson: (m) => CommitHistoryEntry.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'CommitHistoryEntry',
      fieldNote: "'isMerge' (String instead of bool)",
      badMap: const <String, dynamic>{'isMerge': 'yes'},
      callFromJson: (m) => CommitHistoryEntry.fromJson(m),
    );
  });

  group('CommitDetailData.fromJson', () {
    const validKeys = [
      'commitHash',
      'shortHash',
      'subject',
      'body',
      'authorName',
      'authorEmail',
      'authoredAt',
      'filesChanged',
      'additions',
      'deletions',
      'files',
    ];
    _expectLenientToMissingAndNull(
      label: 'CommitDetailData',
      validKeys: validKeys,
      genGoodMap: _goodCommitDetailJson,
      callFromJson: (m) => CommitDetailData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'CommitDetailData',
      genGoodMap: _goodCommitDetailJson,
      validKeys: validKeys,
      callFromJson: (m) => CommitDetailData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'CommitDetailData',
      fieldNote: "'additions' (String instead of int)",
      badMap: const <String, dynamic>{'additions': 'lots'},
      callFromJson: (m) => CommitDetailData.fromJson(m),
    );
  });

  group('BranchInfo.fromJson', () {
    const validKeys = [
      'name',
      'current',
      'upstream',
      'ahead',
      'behind',
      'gone',
      'lastCommitAt',
      'squashMerged',
      'absorbed',
      'absorbedWitness',
    ];
    _expectLenientToMissingAndNull(
      label: 'BranchInfo',
      validKeys: validKeys,
      genGoodMap: _goodBranchInfoJson,
      callFromJson: (m) => BranchInfo.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'BranchInfo',
      genGoodMap: _goodBranchInfoJson,
      validKeys: validKeys,
      callFromJson: (m) => BranchInfo.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'BranchInfo',
      fieldNote: "'ahead' (String instead of int)",
      badMap: const <String, dynamic>{'ahead': 'NaN'},
      callFromJson: (m) => BranchInfo.fromJson(m),
    );

    test(
      "BranchInfo.fromJson: lastCommitAt/squashMerged/absorbed use `is "
      "T ?` guards and tolerate wrong types fine — contrast with the "
      'unsafe `as T?` fields above (name/ahead/behind/current/gone/'
      'absorbedWitness)',
      () {
        final result = BranchInfo.fromJson(<String, dynamic>{
          'name': 'main',
          'current': true,
          'ahead': 0,
          'behind': 0,
          'lastCommitAt': 12345, // wrong type: int, not String
          'squashMerged': 'nope', // wrong type: String, not bool
          'absorbed': 42, // wrong type: int, not bool
        });
        expect(result.lastCommitAt, isNull);
        expect(result.squashMerged, isNull);
        expect(result.absorbed, isNull);
      },
    );
  });

  group('TagEntryData.fromJson', () {
    const validKeys = [
      'name',
      'tagType',
      'targetHash',
      'createdAt',
      'creatorName',
      'subject',
    ];
    _expectLenientToMissingAndNull(
      label: 'TagEntryData',
      validKeys: validKeys,
      genGoodMap: _goodTagEntryJson,
      callFromJson: (m) => TagEntryData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'TagEntryData',
      genGoodMap: _goodTagEntryJson,
      validKeys: validKeys,
      callFromJson: (m) => TagEntryData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'TagEntryData',
      fieldNote: "'name' (int instead of String)",
      badMap: const <String, dynamic>{'name': 42},
      callFromJson: (m) => TagEntryData.fromJson(m),
    );
  });

  group('ReflogEntryData.fromJson', () {
    const validKeys = [
      'commitHash',
      'shortHash',
      'refSelector',
      'actionSummary',
      'authorName',
      'authoredAt',
    ];
    _expectLenientToMissingAndNull(
      label: 'ReflogEntryData',
      validKeys: validKeys,
      genGoodMap: _goodReflogEntryJson,
      callFromJson: (m) => ReflogEntryData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'ReflogEntryData',
      genGoodMap: _goodReflogEntryJson,
      validKeys: validKeys,
      callFromJson: (m) => ReflogEntryData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'ReflogEntryData',
      fieldNote: "'commitHash' (int instead of String)",
      badMap: const <String, dynamic>{'commitHash': 42},
      callFromJson: (m) => ReflogEntryData.fromJson(m),
    );
  });

  // The class the first B17 sweep MISSED (caught by external review): its
  // dual-key reads ((j['commit_hash'] ?? j['commitHash']) as String?) kept
  // the unsafe cast while every sibling was converted.
  group('CommitSearchResultData.fromJson', () {
    const validKeys = [
      'commit_hash',
      'short_hash',
      'subject',
      'author_name',
      'authored_at',
      'match_context',
    ];
    _expectLenientToMissingAndNull(
      label: 'CommitSearchResultData',
      validKeys: validKeys,
      genGoodMap: _goodCommitSearchResultJson,
      callFromJson: (m) => CommitSearchResultData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'CommitSearchResultData',
      genGoodMap: _goodCommitSearchResultJson,
      validKeys: validKeys,
      callFromJson: (m) => CommitSearchResultData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'CommitSearchResultData',
      fieldNote: "'commit_hash' (int instead of String)",
      badMap: const <String, dynamic>{'commit_hash': 42},
      callFromJson: (m) => CommitSearchResultData.fromJson(m),
    );
    test('camelCase alternate keys are honored and equally type-safe', () {
      final d = CommitSearchResultData.fromJson(const <String, dynamic>{
        'commitHash': 'abc',
        'shortHash': 'ab',
        'authorName': 'a',
        'authoredAt': 't',
        'matchContext': 42, // wrong-typed → null, not TypeError
      });
      expect(d.commitHash, 'abc');
      expect(d.matchContext, isNull);
    });
  });

  group('BlameLineData.fromJson', () {
    const validKeys = [
      'lineNumber',
      'commitHash',
      'shortHash',
      'authorName',
      'authoredAt',
      'lineContent',
    ];
    _expectLenientToMissingAndNull(
      label: 'BlameLineData',
      validKeys: validKeys,
      genGoodMap: _goodBlameLineJson,
      callFromJson: (m) => BlameLineData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'BlameLineData',
      genGoodMap: _goodBlameLineJson,
      validKeys: validKeys,
      callFromJson: (m) => BlameLineData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'BlameLineData',
      fieldNote: "'lineNumber' (String instead of int)",
      badMap: const <String, dynamic>{'lineNumber': '10'},
      callFromJson: (m) => BlameLineData.fromJson(m),
    );
  });

  group('SyncData.fromJson', () {
    const validKeys = ['operation', 'remote', 'branch', 'output'];
    _expectLenientToMissingAndNull(
      label: 'SyncData',
      validKeys: validKeys,
      genGoodMap: _goodSyncDataJson,
      callFromJson: (m) => SyncData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'SyncData',
      genGoodMap: _goodSyncDataJson,
      validKeys: validKeys,
      callFromJson: (m) => SyncData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'SyncData',
      fieldNote: "'operation' (int instead of String)",
      badMap: const <String, dynamic>{'operation': 5},
      callFromJson: (m) => SyncData.fromJson(m),
    );
  });

  group('AiProviderStatus.fromJson', () {
    const validKeys = [
      'id',
      'available',
      'binary',
      'planName',
      'resolvedBinary',
      'detectionSource',
      'healthCheck',
    ];
    _expectLenientToMissingAndNull(
      label: 'AiProviderStatus',
      validKeys: validKeys,
      genGoodMap: _goodAiProviderStatusJson,
      callFromJson: (m) => AiProviderStatus.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'AiProviderStatus',
      genGoodMap: _goodAiProviderStatusJson,
      validKeys: validKeys,
      callFromJson: (m) => AiProviderStatus.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AiProviderStatus',
      fieldNote: "'available' (String instead of bool)",
      badMap: const <String, dynamic>{'available': 'true'},
      callFromJson: (m) => AiProviderStatus.fromJson(m),
    );
  });

  group('AiProviderListData.fromJson', () {
    const validKeys = ['providers'];
    _expectLenientToMissingAndNull(
      label: 'AiProviderListData',
      validKeys: validKeys,
      genGoodMap: _goodAiProviderListJson,
      callFromJson: (m) => AiProviderListData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AiProviderListData',
      fieldNote: "'providers' (String instead of List)",
      badMap: const <String, dynamic>{'providers': 'nope'},
      callFromJson: (m) => AiProviderListData.fromJson(m),
    );
  });

  group('AiModelOptionData.fromJson', () {
    const validKeys = [
      'value',
      'modelId',
      'providerId',
      'providerLabel',
      'planName',
      'label',
      'description',
      'promptPricePer1m',
      'completionPricePer1m',
      'supportsReasoning',
      'hasFastTier',
    ];
    _expectLenientToMissingAndNull(
      label: 'AiModelOptionData',
      validKeys: validKeys,
      genGoodMap: _goodAiModelOptionJson,
      callFromJson: (m) => AiModelOptionData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'AiModelOptionData',
      genGoodMap: _goodAiModelOptionJson,
      validKeys: validKeys,
      callFromJson: (m) => AiModelOptionData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AiModelOptionData',
      fieldNote: "'value' (int instead of String)",
      badMap: const <String, dynamic>{'value': 42},
      callFromJson: (m) => AiModelOptionData.fromJson(m),
    );

    test(
      'AiModelOptionData.fromJson: supportsReasoning/hasFastTier use '
      '`== true`, tolerating any type fine — another positive contrast',
      () {
        final result = AiModelOptionData.fromJson(<String, dynamic>{
          'value': 'x',
          'label': 'x',
          'description': '',
          'supportsReasoning': 'yes', // wrong type: String, not bool
          'hasFastTier': 1, // wrong type: int, not bool
        });
        expect(result.supportsReasoning, isFalse);
        expect(result.hasFastTier, isFalse);
      },
    );
  });

  group('AiModelCategoryData.fromJson', () {
    const validKeys = ['id', 'label', 'description', 'models'];
    _expectLenientToMissingAndNull(
      label: 'AiModelCategoryData',
      validKeys: validKeys,
      genGoodMap: _goodAiModelCategoryJson,
      callFromJson: (m) => AiModelCategoryData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'AiModelCategoryData',
      genGoodMap: _goodAiModelCategoryJson,
      validKeys: validKeys,
      callFromJson: (m) => AiModelCategoryData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AiModelCategoryData',
      fieldNote: "'id' (bool instead of String)",
      badMap: const <String, dynamic>{'id': true},
      callFromJson: (m) => AiModelCategoryData.fromJson(m),
    );
  });

  group('AiModelOptionListData.fromJson', () {
    const validKeys = ['categories'];
    _expectLenientToMissingAndNull(
      label: 'AiModelOptionListData',
      validKeys: validKeys,
      genGoodMap: _goodAiModelOptionListJson,
      callFromJson: (m) => AiModelOptionListData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AiModelOptionListData',
      fieldNote: "'categories' (int instead of List)",
      badMap: const <String, dynamic>{'categories': 5},
      callFromJson: (m) => AiModelOptionListData.fromJson(m),
    );
  });

  group('AppSettingsData.fromJson', () {
    const validKeys = [
      'themeId',
      'keybindingProfile',
      'sidebarWidthPx',
      'aiReadOnlyDefault',
    ];
    _expectLenientToMissingAndNull(
      label: 'AppSettingsData',
      validKeys: validKeys,
      genGoodMap: _goodAppSettingsJson,
      callFromJson: (m) => AppSettingsData.fromJson(m),
    );
    _wrongTypeFuzzCanary(
      label: 'AppSettingsData',
      genGoodMap: _goodAppSettingsJson,
      validKeys: validKeys,
      callFromJson: (m) => AppSettingsData.fromJson(m),
    );
    _expectGenuineWrongTypeBug(
      label: 'AppSettingsData',
      fieldNote: "'sidebarWidthPx' (String instead of int)",
      badMap: const <String, dynamic>{'sidebarWidthPx': '240'},
      callFromJson: (m) => AppSettingsData.fromJson(m),
    );
  });
}
