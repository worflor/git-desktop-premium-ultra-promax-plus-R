// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Tests for the geometric tokenizer — the Cl(8) rotor tokenizer whose
// segmentation is subspace coherence in the diagonalised coupling metric.
//
// The load-bearing guarantees pinned here:
//   • round-trip is lossless: decode(encode(x)) == x for any x over the
//     reserved alphabet (a tokenizer that can't reconstruct its input is
//     not a tokenizer);
//   • the whole pipeline is deterministic (Jacobi + bigram counts, no RNG),
//     so the same repo yields the same vocabulary and the same ids;
//   • segmentation tiles the text exactly (contiguous, covering, non-empty);
//   • the degenerate-metric path (tiny / uniform corpus) degrades to
//     character tokens instead of crashing — the G5 cliff handled, not hit.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/geometric_tokenizer.dart';

// A small but bigram-rich corpus so the coupling form is non-degenerate and
// the vocabulary learns recurrent structure.
const _corpus = <String>[
  'final result = computeValue(input, context);\n'
      'final result = computeValue(other, context);\n'
      'return result.normalize();',
  'class WidgetState extends State<Widget> {\n'
      '  final WidgetState state = WidgetState();\n'
      '  void update() => setState(() => state.value = value);\n'
      '}',
  'for (var i = 0; i < count; i++) { total += values[i]; }\n'
      'for (var j = 0; j < count; j++) { total += values[j]; }',
  'import package backend logos core;\n'
      'import package backend logos flow;\n'
      'import package backend geometric tokenizer;',
];

void main() {
  group('GeometricTokenizer round-trip', () {
    final tok = GeometricTokenizer.train(_corpus);

    for (final probe in <String>[
      'final result = computeValue(input, context);',
      'class WidgetState extends State<Widget> {}',
      'return result.normalize();',
      'totally unseen but ascii words 123 !@#',
      '',
      'a',
      '\n\t  spaced\tand\nnewlined  ',
      // non-ASCII the repo actually uses, incl. non-BMP (surrogate pairs):
      'ℂ[(Z/2)⁸] ⊕ Cl(8) ≅ 𝕆 — signature (3,5) ✓',
      '𝕆 𝕊 𝕋 · λ∇∂ ≤ ≥ ≠ é ñ 日本語 🜂',
    ]) {
      test('decode(encode(${_short(probe)})) == probe', () {
        final ids = tok.encode(probe);
        expect(tok.decode(ids), equals(probe));
      });
    }

    test('every emitted id resolves to a vocabulary entry', () {
      final ids = tok.encode(_corpus.first);
      for (final id in ids) {
        expect(tok.vocabulary.tokenForId(id), isNotNull);
      }
    });
  });

  group('GeometricTokenizer determinism', () {
    test('two trainings on the same corpus agree exactly', () {
      final a = GeometricTokenizer.train(_corpus);
      final b = GeometricTokenizer.train(_corpus);
      expect(a.vocabSize, equals(b.vocabSize));
      expect(a.metric.dim, equals(b.metric.dim));
      expect(a.metric.positiveCount, equals(b.metric.positiveCount));
      const probe = 'final result = computeValue(input, context);';
      expect(a.encode(probe), equals(b.encode(probe)));
    });
  });

  group('GeometricSegmenter tiling', () {
    final tok = GeometricTokenizer.train(_corpus);
    final seg = GeometricSegmenter(tok.metric);

    for (final text in <String>[
      _corpus.first,
      'getData(userId)',
      'aaaa bbbb cccc',
    ]) {
      test('segments are contiguous, covering, non-empty: ${_short(text)}', () {
        final ranges = seg.segment(text);
        expect(ranges, isNotEmpty);
        expect(ranges.first.start, equals(0));
        expect(ranges.last.end, equals(text.length));
        for (var i = 0; i < ranges.length; i++) {
          expect(ranges[i].end, greaterThan(ranges[i].start)); // non-empty
          if (i > 0) {
            expect(ranges[i].start, equals(ranges[i - 1].end)); // contiguous
          }
        }
      });
    }
  });

  group('GeometricVocabulary learning', () {
    final tok = GeometricTokenizer.train(_corpus, minCount: 2);

    test('learns multi-character tokens beyond the 256-byte floor', () {
      expect(tok.vocabSize, greaterThan(256));
    });

    test('every token address is an 8-bit Cl(8) cell', () {
      for (var id = 0; id < tok.vocabSize; id++) {
        final t = tok.vocabulary.tokenForId(id)!;
        expect(t.address, inInclusiveRange(0, 255));
      }
    });

    test('a recurrent token compresses below its character count', () {
      // whichever multi-char tokens were learned, encoding their own text
      // must cost fewer ids than their length (greedy prefers them).
      var sawCompression = false;
      for (var id = 256; id < tok.vocabSize; id++) {
        final text = tok.vocabulary.tokenForId(id)!.text;
        if (text == null || text.length < 2) continue;
        final ids = tok.encode(text);
        expect(ids.length, lessThanOrEqualTo(text.length));
        if (ids.length < text.length) sawCompression = true;
      }
      expect(sawCompression, isTrue,
          reason: 'at least one learned token should beat char-level');
    });
  });

  group('GeometricMetric signature', () {
    test('a bigram-rich corpus yields a non-degenerate 8-axis algebra', () {
      final tok = GeometricTokenizer.train(_corpus);
      expect(tok.metric.dim, inInclusiveRange(1, GeometricMetric.maxAxes));
      expect(tok.metric.positiveCount + tok.metric.negativeCount,
          equals(tok.metric.dim));
    });

    test('signature counts are consistent with per-axis signs', () {
      final tok = GeometricTokenizer.train(_corpus);
      var pos = 0;
      for (var a = 0; a < tok.metric.dim; a++) {
        if (tok.metric.signOf(a) > 0) pos++;
      }
      expect(pos, equals(tok.metric.positiveCount));
    });
  });

  group('GeometricTokenizer degeneracy', () {
    test('a uniform corpus degrades to char tokens without throwing', () {
      final tok = GeometricTokenizer.train(const ['aaaaaaaa', 'aaaaaaaa']);
      const probe = 'aaaa';
      expect(tok.decode(tok.encode(probe)), equals(probe));
      // the metric is rank-deficient (one dominant direction) but usable.
      expect(tok.metric.dim, lessThanOrEqualTo(GeometricMetric.maxAxes));
    });

    test('an empty corpus still round-trips ascii', () {
      final tok = GeometricTokenizer.train(const ['']);
      const probe = 'hello world';
      expect(tok.decode(tok.encode(probe)), equals(probe));
    });
  });

  // Losslessness is a guarantee for EVERY code-unit sequence, not just real
  // text. WTF-8 is a bijection on code units and the encoder only splits on
  // code-unit boundaries, so the byte stream round-trips exactly. This pins
  // the implementation to that proof — the full 102k-case exhaustive sweep
  // (all BMP units + astral stride + every repo file + 20k random) is run
  // out-of-band; this bounded version locks the same guarantee into CI.
  group('GeometricTokenizer losslessness (the guarantee)', () {
    final tok = GeometricTokenizer.train(_corpus);

    bool sameCodeUnits(String a, String b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) return false;
      }
      return true;
    }

    test('every lone surrogate code unit (0xD800..0xDFFF) round-trips', () {
      for (var u = 0xD800; u <= 0xDFFF; u++) {
        final s = String.fromCharCodes(<int>[u]);
        expect(sameCodeUnits(tok.decode(tok.encode(s)), s), isTrue,
            reason: 'lone surrogate U+${u.toRadixString(16)} corrupted');
      }
    });

    test('BMP scalars (strided) and astral-plane scalars round-trip', () {
      for (var u = 0; u <= 0xFFFF; u += 7) {
        if (u >= 0xD800 && u <= 0xDFFF) continue; // covered above
        final s = String.fromCharCodes(<int>[u]);
        expect(sameCodeUnits(tok.decode(tok.encode(s)), s), isTrue);
      }
      for (var cp = 0x10000; cp <= 0x10FFFF; cp += 0x111) {
        final s = String.fromCharCode(cp);
        expect(sameCodeUnits(tok.decode(tok.encode(s)), s), isTrue);
      }
    });

    test('5k seeded random strings incl. lone surrogates round-trip', () {
      final rng = Random(20260531);
      for (var t = 0; t < 5000; t++) {
        final units = List<int>.generate(rng.nextInt(40), (_) {
          final r = rng.nextInt(100);
          if (r < 70) return rng.nextInt(0x80);
          if (r < 90) return rng.nextInt(0x10000);
          return 0xD800 + rng.nextInt(0x800); // force lone surrogates
        });
        final s = String.fromCharCodes(units);
        expect(sameCodeUnits(tok.decode(tok.encode(s)), s), isTrue);
      }
    });
  });
}

String _short(String s) {
  final oneLine = s.replaceAll('\n', '\\n').replaceAll('\t', '\\t');
  return oneLine.length <= 32 ? oneLine : '${oneLine.substring(0, 29)}...';
}
