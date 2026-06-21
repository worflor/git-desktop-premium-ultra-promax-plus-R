// geometric_tokenizer.dart — the GEOMETRICALLY yielded adaptive tokenizer.
//
// A real tokenizer (vocabulary, encode text→ids, decode ids→text), learned
// from a repo's own character statistics with no grammar and no keywords.
// The segmentation is not a coupling threshold — it is the geometry of a
// Clifford algebra the coupling statistics define.
//
// THE FOUNDATION (validated exactly by alpha-math, ../alpha-math/gyat-proofs.ts).
// The repo-global CharCoupling is a 128×128 bigram form. Symmetrised, it is a
// metric tensor; diagonalising it (top-8 eigenpairs) gives an 8-dimensional
// space whose Clifford algebra is Cl(8) — the SAME 256-cell lattice the engine
// already runs on (the blade index is the XOR of the addresses; gyat-proofs G1),
// with the anticommutation sign restored. In that algebra:
//   • characters are grade-1 vectors,
//   • a token is a rotor — a product of an even number of character vectors —
//     living in the closed even subalgebra Cl(8)⁺ ≅ Cl(7) (gyat-proofs G6),
//   • the geometric product is associative (gyat-proofs G3), so a token's
//     product is well-defined however the text is split into tokens.
//
// THE SEGMENTATION CRITERION. A token is a maximal run of characters whose
// vectors stay inside one low-dimensional subspace of the eigenspace. The
// boundary is where the next character's component ORTHOGONAL to the run's
// accumulated blade — the wedge it adds, the new plane it opens — exceeds the
// baseline a random direction would contribute. This is the grade-CLIMB of the
// running geometric product, not its parity (the parity of a product of k
// vectors is just the parity of k, so it carries no boundary signal). The
// criterion has memory: it depends on every character in the run via their
// span, not just the last pair.
//
// THE ONE FAILURE MODE (gyat-proofs G5). A non-degenerate metric of ANY
// signature gives a clean simple algebra, so the tokenizer is invariant to the
// SIGNS of the coupling eigenvalues — there is no metric knob to tune. The sole
// degeneracy is a zero eigenvalue in the top 8: it grows a radical and the
// rotors stop being invertible. [GeometricMetric] guards against it by dropping
// near-null axes and reporting a reduced effective dimension.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart' show CharCoupling, denseSymmetricEigen;

/// The eigen-projected metric: characters as vectors in the diagonalised
/// coupling space, plus the Clifford signature that space carries.
class GeometricMetric {
  /// 7-bit ASCII basis — matches CharCoupling's alphabet (the known
  /// universality wart; non-ASCII collapses onto its low 7 bits).
  static const int alphabet = 128;

  /// Cl(8): eight axes, the 256-cell lattice. The tokenizer uses the
  /// largest [maxAxes] non-degenerate eigen-directions.
  static const int maxAxes = 8;

  /// Relative floor below the dominant eigenvalue under which an axis is
  /// treated as null and dropped. This is the G5 cliff guard — a near-zero
  /// eigenvalue is the one signature that breaks the rotor structure.
  static const double _degenerateTol = 1e-8;

  final CharCoupling coupling;

  /// Effective number of non-degenerate axes (≤ [maxAxes]). Below 8 means
  /// the coupling form is rank-deficient in its dominant block.
  final int dim;

  /// Signature (p, q): [positiveCount] axes with λ > 0, the rest negative.
  /// The algebra is the same simple matrix algebra for every (p, q) — this
  /// is reported for diagnostics, not used to gate any computation.
  final int positiveCount;

  // [alphabet × dim], char-major. Emphasis-scaled coordinates: axis a holds
  // u_a[c]·√|λ_a|, the standard spectral embedding that weights dominant
  // coupling modes. The √|λ| scale is gauge the algebra is blind to
  // (alpha-math proof: derivations/identities cannot see a metric rescaling),
  // so it is free to choose for the geometry without changing the algebra.
  final Float64List _embed;
  final Int8List _sign; // [dim] metric sign per axis (+1 / −1)
  final Float64List _eigenvalues; // [dim] selected eigenvalues, |λ| descending

  /// Median strength of an observed character bond — the typical grade-0
  /// (scalar) part of the geometric product across the repo's bigrams. The
  /// segmenter cuts at bonds weaker than this, so the threshold is
  /// data-derived, not a tuning constant.
  final double medianBond;

  GeometricMetric._(this.coupling, this.dim, this.positiveCount, this._embed,
      this._sign, this._eigenvalues, this.medianBond);

  /// Diagonalise the symmetrised coupling form and keep its dominant
  /// non-degenerate axes.
  factory GeometricMetric.fromCoupling(CharCoupling coupling) {
    const n = alphabet;
    final w = coupling.rawWeights; // 128×128 row-major bigram weights
    // Symmetric metric M = (C + Cᵀ)/2 — a quadratic form needs to be
    // symmetric; the bigram matrix is not (a→b ≠ b→a).
    final m = Float64List(n * n);
    for (var a = 0; a < n; a++) {
      for (var b = 0; b < n; b++) {
        m[a * n + b] = 0.5 * (w[a * n + b] + w[b * n + a]);
      }
    }
    final eig = denseSymmetricEigen(m, n);

    // Rank axes by |eigenvalue| descending.
    final order = List<int>.generate(n, (i) => i)
      ..sort((i, j) => eig.values[j].abs().compareTo(eig.values[i].abs()));
    final lambdaMax = order.isEmpty ? 0.0 : eig.values[order.first].abs();

    // Select up to maxAxes non-degenerate axes (the G5 cliff guard).
    final cols = <int>[];
    for (final col in order) {
      if (cols.length >= maxAxes) break;
      if (lambdaMax <= 0 ||
          eig.values[col].abs() < _degenerateTol * lambdaMax) {
        break;
      }
      cols.add(col);
    }

    final dim = cols.length;
    final embed = Float64List(n * dim);
    final sign = Int8List(dim);
    final eigvals = Float64List(dim);
    var pos = 0;
    for (var a = 0; a < dim; a++) {
      final col = cols[a];
      final lambda = eig.values[col];
      sign[a] = lambda >= 0 ? 1 : -1;
      if (lambda >= 0) pos++;
      eigvals[a] = lambda;
      final emphasis = math.sqrt(lambda.abs());
      for (var c = 0; c < n; c++) {
        embed[c * dim + a] = eig.vectors[c * n + col] * emphasis;
      }
    }

    // Median observed bond strength — the typical scalar part of a
    // character geometric product. Cuts below this are genuine valleys.
    final nz = <double>[];
    for (var i = 0; i < w.length; i++) {
      if (w[i] > 0) nz.add(w[i]);
    }
    nz.sort();
    final medianBond = nz.isEmpty ? 0.0 : nz[nz.length ~/ 2];

    return GeometricMetric._(
        coupling, dim, pos, embed, sign, eigvals, medianBond);
  }

  /// The bond between two adjacent characters: the grade-0 (scalar) part of
  /// their geometric product, i.e. the directed coupling `⟨e_a, e_b⟩` the
  /// repo's bigram statistics learned. High inside a token, low at a boundary.
  double bond(int a, int b) => coupling.weight(a, b);

  /// True when the dominant coupling block is rank-deficient (< 8 usable
  /// axes). The tokenizer still works, in a smaller algebra.
  bool get isDegenerate => dim < maxAxes;
  int get negativeCount => dim - positiveCount;
  int signOf(int axis) => _sign[axis];
  double eigenvalueOf(int axis) => _eigenvalues[axis];

  /// The character's vector in the emphasis-scaled eigenspace (length [dim]).
  /// Used to address a token to its Cl(8) lattice cell.
  Float64List vectorOf(int codeUnit) {
    final c = codeUnit & 0x7F;
    final out = Float64List(dim);
    final base = c * dim;
    for (var a = 0; a < dim; a++) {
      out[a] = _embed[base + a];
    }
    return out;
  }
}

/// Splits text into geometric tokens at coupling valleys.
class GeometricSegmenter {
  final GeometricMetric metric;
  const GeometricSegmenter(this.metric);

  /// A token is a maximal run of characters whose bonds hold it together. A
  /// boundary is a bond that is a local minimum of the coupling profile AND
  /// dips below the run's OWN mean bond so far — the place where the geometric
  /// product `e_{prev}·e_{cur}` loses the grade-0 (scalar) cohesion the token
  /// had been sustaining and becomes wedge-dominated, so the grade climbs and
  /// a new structural direction opens. Returns half-open `[start, end)`.
  ///
  /// The threshold is the token's own running cohesion — no tuning constant,
  /// and adaptive with memory: a tightly bound token (high mean bond) breaks
  /// at the first real dip, a loosely bound one tolerates more before it ends.
  /// A global floor ([GeometricMetric.medianBond]) additionally cuts any bond
  /// the whole repo would consider weak.
  ///
  /// alpha-math proof: the scalar this thresholds is the grade-0 part of the
  /// geometric product, whose blade index is the XOR addressing the lattice
  /// already uses (gyat-proofs G1); the surviving run composes into a rotor in
  /// the even subalgebra Cl(8)⁺ ≅ Cl(7) (gyat-proofs G6), and that product's
  /// associativity (gyat-proofs G3) is what lets a run be re-split at any
  /// boundary without changing the token it represents.
  List<({int start, int end})> segment(String text) {
    final out = <({int start, int end})>[];
    final n = text.length;
    if (n == 0) return out;
    if (n == 1) {
      out.add((start: 0, end: 1));
      return out;
    }

    // Bond strength link[i] = scalar(e_{i−1}·e_i) for i in 1..n−1.
    final link = Float64List(n);
    for (var i = 1; i < n; i++) {
      link[i] = metric.bond(text.codeUnitAt(i - 1), text.codeUnitAt(i));
    }
    final floor = metric.medianBond;

    var start = 0;
    var runSum = 0.0;
    var runCount = 0;
    for (var i = 1; i < n; i++) {
      final l = link[i];
      // The token's cohesion so far (its mean interior bond). Until a bond
      // has been absorbed, the token tolerates anything (a token is ≥ 1 char).
      final cohesion = runCount > 0 ? runSum / runCount : double.infinity;
      final localMin = l <= link[i - 1] && (i + 1 >= n || l <= link[i + 1]);
      // Never cut between a surrogate pair — a token must hold whole runes
      // so its UTF-8 expansion (and so the round-trip) stays valid.
      final prev = text.codeUnitAt(i - 1), cur = text.codeUnitAt(i);
      final midRune = prev >= 0xD800 &&
          prev <= 0xDBFF &&
          cur >= 0xDC00 &&
          cur <= 0xDFFF;
      if (localMin && !midRune && (l < cohesion || l < floor)) {
        out.add((start: start, end: i));
        start = i;
        runSum = 0.0;
        runCount = 0;
      } else {
        runSum += l;
        runCount++;
      }
    }
    out.add((start: start, end: n));
    return out;
  }
}

/// One vocabulary entry. Every token carries its UTF-8 [bytes] so decoding is
/// lossless for any input; learned tokens additionally carry their [text] (for
/// longest-match) and an 8-bit Cl(8) lattice [address]. Tokens with ids 0..255
/// are the raw byte floor — [text] is null and [bytes] is the single byte.
class GeoToken {
  final int id;
  final String? text;
  final List<int> bytes;
  final int address;
  int count;
  GeoToken(this.id, this.text, this.bytes, this.address, this.count);
}

/// The rotor atlas: a learned vocabulary over geometric tokens, plus the
/// encode/decode that make it a real tokenizer.
class GeometricVocabulary {
  final GeometricMetric metric;
  final GeometricSegmenter segmenter;
  final Map<String, GeoToken> _byText = {};
  final List<GeoToken> _byId = [];

  GeometricVocabulary._(this.metric) : segmenter = GeometricSegmenter(metric);

  int get size => _byId.length;
  GeoToken? tokenForId(int id) =>
      (id >= 0 && id < _byId.length) ? _byId[id] : null;
  GeoToken? tokenForText(String text) => _byText[text];

  /// Learn a vocabulary from [corpus]. The 256 raw byte values are always
  /// reserved (ids 0..255) so encoding is total and decoding is lossless for
  /// any UTF-8 input; multi-character segments that recur at least [minCount]
  /// times are admitted on top as learned tokens.
  factory GeometricVocabulary.build(
    GeometricMetric metric,
    Iterable<String> corpus, {
    int minCount = 2,
  }) {
    final vocab = GeometricVocabulary._(metric);
    final sources = corpus.toList(growable: false);

    // The lossless floor: one token per byte value. Any character — ASCII,
    // accented, emoji, the repo's 𝕆/ℂ/⊕ — round-trips through its UTF-8 bytes.
    for (var b = 0; b < 256; b++) {
      vocab._byId.add(GeoToken(b, null, <int>[b], b & 0xFF, 0));
    }

    // Count recurrent multi-character segments (whole-rune, from the
    // surrogate-safe segmenter).
    final counts = <String, int>{};
    for (final src in sources) {
      for (final seg in vocab.segmenter.segment(src)) {
        if (seg.end - seg.start < 2) continue;
        final s = src.substring(seg.start, seg.end);
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }

    // Admit recurrent segments, longest first so greedy encode prefers them.
    final admitted = counts.entries.where((e) => e.value >= minCount).toList()
      ..sort((a, b) {
        final byLen = b.key.length.compareTo(a.key.length);
        return byLen != 0 ? byLen : b.value.compareTo(a.value);
      });
    for (final e in admitted) {
      final text = e.key;
      final tok = GeoToken(vocab._byId.length, text, utf8.encode(text),
          vocab._addressOf(text), e.value);
      vocab._byId.add(tok);
      vocab._byText[text] = tok;
    }
    return vocab;
  }

  /// A token's 8-bit Cl(8) address: which side of each metric axis the
  /// token's summed character vector (its rotor's vector part) falls on.
  /// Length-independent and deterministic — the same cell space the
  /// FlowSseLattice already indexes (gyat-proofs G1: blade index is the XOR).
  int _addressOf(String s) {
    final acc = Float64List(metric.dim);
    for (var i = 0; i < s.length; i++) {
      final v = metric.vectorOf(s.codeUnitAt(i));
      for (var a = 0; a < metric.dim; a++) {
        acc[a] += v[a];
      }
    }
    var addr = 0;
    for (var a = 0; a < metric.dim && a < 8; a++) {
      if (acc[a] > 0) addr |= (1 << a);
    }
    return addr & 0xFF;
  }

  /// text → token ids. Segments geometrically, then covers each segment with
  /// the longest available vocabulary entries, falling back to single
  /// characters (always reserved) so encoding never fails.
  List<int> encode(String text) {
    final ids = <int>[];
    for (final seg in segmenter.segment(text)) {
      _encodeSpan(text, seg.start, seg.end, ids);
    }
    return ids;
  }

  void _encodeSpan(String text, int start, int end, List<int> out) {
    var p = start;
    while (p < end) {
      GeoToken? best;
      for (var q = end; q > p + 1; q--) {
        final cand = _byText[text.substring(p, q)];
        if (cand != null) {
          best = cand;
          break;
        }
      }
      if (best != null) {
        out.add(best.id);
        p += best.text!.length;
      } else {
        // Uncovered character: emit one code point as raw byte tokens (ids
        // 0..255). Whole valid runes go out as UTF-8; an UNPAIRED surrogate
        // (legal in a Dart String, illegal in UTF-8) goes out as its 3-byte
        // WTF-8 form so it survives the round-trip instead of collapsing to
        // U+FFFD. Total and lossless for every possible code-unit sequence.
        final cu = text.codeUnitAt(p);
        if (cu >= 0xD800 &&
            cu <= 0xDBFF &&
            p + 1 < end &&
            _isLowSurrogate(text.codeUnitAt(p + 1))) {
          // a valid high+low pair → standard 4-byte UTF-8
          for (final byte in utf8.encode(text.substring(p, p + 2))) {
            out.add(byte);
          }
          p += 2;
        } else if (cu >= 0xD800 && cu <= 0xDFFF) {
          // an unpaired surrogate → 3-byte WTF-8 (decoded back by _bytesToString)
          out.add(0xE0 | (cu >> 12));
          out.add(0x80 | ((cu >> 6) & 0x3F));
          out.add(0x80 | (cu & 0x3F));
          p += 1;
        } else {
          for (final byte in utf8.encode(text.substring(p, p + 1))) {
            out.add(byte);
          }
          p += 1;
        }
      }
    }
  }

  static bool _isLowSurrogate(int cu) => cu >= 0xDC00 && cu <= 0xDFFF;

  /// ids → text. Concatenates each token's bytes and decodes the stream once.
  /// The round-trip `decode(encode(x)) == x` holds for EVERY Dart string — not
  /// just real text: ASCII, accented, emoji, the repo's non-BMP 𝕆/𝕊/𝕋, and
  /// even unpaired surrogates (via the WTF-8 path), because the codec preserves
  /// raw UTF-16 code units rather than normalising them.
  String decode(Iterable<int> ids) {
    final bytes = <int>[];
    for (final id in ids) {
      final t = tokenForId(id);
      if (t != null) bytes.addAll(t.bytes);
    }
    return _bytesToString(bytes);
  }

  /// Decode a UTF-8/WTF-8 byte stream to a string, reproducing UTF-16 code
  /// units exactly — 3-byte sequences in the surrogate range are kept as lone
  /// surrogate code units (the WTF-8 contract) so nothing is lost. Self-
  /// contained (no dependency on the SDK decoder's surrogate handling), and
  /// bounded against truncated input even though [encode] never produces it.
  static String _bytesToString(List<int> bytes) {
    final units = <int>[];
    final n = bytes.length;
    var i = 0;
    while (i < n) {
      final b = bytes[i];
      if (b < 0x80) {
        units.add(b);
        i += 1;
      } else if (b < 0xE0) {
        if (i + 1 < n) {
          units.add(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
          i += 2;
        } else {
          units.add(0xFFFD);
          i += 1;
        }
      } else if (b < 0xF0) {
        if (i + 2 < n) {
          units.add(((b & 0x0F) << 12) |
              ((bytes[i + 1] & 0x3F) << 6) |
              (bytes[i + 2] & 0x3F)); // may land in 0xD800..0xDFFF — kept as-is
          i += 3;
        } else {
          units.add(0xFFFD);
          i += 1;
        }
      } else {
        if (i + 3 < n) {
          final cp = ((b & 0x07) << 18) |
              ((bytes[i + 1] & 0x3F) << 12) |
              ((bytes[i + 2] & 0x3F) << 6) |
              (bytes[i + 3] & 0x3F);
          if (cp >= 0x10000) {
            final v = cp - 0x10000;
            units.add(0xD800 | (v >> 10));
            units.add(0xDC00 | (v & 0x3FF));
          } else {
            units.add(cp);
          }
          i += 4;
        } else {
          units.add(0xFFFD);
          i += 1;
        }
      }
    }
    return String.fromCharCodes(units);
  }
}

/// The geometric tokenizer: a metric and a vocabulary learned from a repo's
/// own text, exposing encode / decode / segment.
class GeometricTokenizer {
  final GeometricMetric metric;
  final GeometricVocabulary vocabulary;

  GeometricTokenizer._(this.metric, this.vocabulary);

  /// Train on [sources] (the repo's blobs). Builds the coupling metric and
  /// the learned vocabulary in one pass.
  factory GeometricTokenizer.train(Iterable<String> sources,
      {int minCount = 2}) {
    final list = sources.toList(growable: false);
    final coupling = CharCoupling.fromSources(list);
    final metric = GeometricMetric.fromCoupling(coupling);
    final vocab =
        GeometricVocabulary.build(metric, list, minCount: minCount);
    return GeometricTokenizer._(metric, vocab);
  }

  /// Build directly on a pre-computed [coupling] (e.g. the repo-global
  /// CharCoupling the GYAT lattice already carries) to avoid a second pass.
  factory GeometricTokenizer.fromCoupling(
      CharCoupling coupling, Iterable<String> sources,
      {int minCount = 2}) {
    final metric = GeometricMetric.fromCoupling(coupling);
    final vocab = GeometricVocabulary.build(metric, sources, minCount: minCount);
    return GeometricTokenizer._(metric, vocab);
  }

  List<int> encode(String text) => vocabulary.encode(text);
  String decode(Iterable<int> ids) => vocabulary.decode(ids);

  /// The raw geometric segmentation (boundaries before vocabulary coverage).
  List<String> segment(String text) => [
        for (final s in vocabulary.segmenter.segment(text))
          text.substring(s.start, s.end)
      ];

  int get vocabSize => vocabulary.size;

  /// Diagnostic one-liner: the algebra, its signature, and the vocabulary
  /// size — e.g. `Cl(8) signature (5,3) · vocab 4213`.
  String describe() => 'Cl(${metric.dim}) signature '
      '(${metric.positiveCount},${metric.negativeCount})'
      '${metric.isDegenerate ? " [degenerate]" : ""} · vocab ${vocabulary.size}';
}
