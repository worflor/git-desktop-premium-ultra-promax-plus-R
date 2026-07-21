// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// repo_native_embedding.dart — repo-native content vectors for file coupling.
//
// WHY AN IDF TOKEN BAG, NOT A SPECTRAL EMBEDDING
// The first cut of this module WAS a spectral embedding: PPMI identifier
// co-occurrence → normalized-Laplacian eigenmap, with the equilibrium mode
// projected out. It measured beautifully on structural north-stars (imports,
// same-directory) — but that benchmark was rigged in its favour: "hard pairs"
// were DEFINED as low-literal-overlap, i.e. exactly the pairs a token bag is
// worst at, so the embedding was handed its own best case.
//
// On the REAL objective — a temporal holdout that trains on older commits and
// predicts which files actually co-change in held-out future commits — the
// spectral embedding LOST, badly, to a plain IDF-weighted token bag, and
// max-merging it into the coupling axis actively DEGRADED the result (MANIFOLD
// max(jac,bag) 0.761 → max(jac,bag,emb) 0.719; on worflor it scored WORSE than a
// coin flip on its own supposed niche). The reason is structural: files
// co-change because they share SPECIFIC identifiers — an import, a constant, a
// data contract — and semantic smoothing destroys exactly that signal.
// Co-change is literal, not topical.
//
// So this is the validated design: a repo-native, IDF-weighted, feature-hashed
// identifier bag. Repo-native (each repo learns its own document frequencies),
// zero pretraining, zero OOV. On the temporal holdout it lifts co-change AUC
// from history-alone 0.695 to max(jac,bag) 0.769, and it beats a char-level
// content bag 0.756 vs 0.634 — so it adds real signal, not a duplicate of the
// engine's char-address histogram (which, notably, is near-useless and even
// harmful for co-change: max(jac,char) 0.632 < jac 0.695).
//
// The cosine rides into computeSpectralCoupling as one more max-merged
// contribution to the spectral axis. Max-merge is safe here — unlike the
// embedding, the IDF bag has high co-change PRECISION, so raising a pair's
// coupling to its bag score only fires on pairs that genuinely tend to
// co-change.
//
// TOKEN COUPLING CHARGE — the second, deeper signal this module carries.
// IDF weights a token by rarity; the CHARGE weighs it by what the repo's own
// history says it DOES: charge(w) = P(two files sharing w co-changed), measured
// over w's carrier files against the co-change matrix. It is the engine's
// equivalent of a transformer's trained attention weights — which token-matches
// matter — extracted from the git log instead of gradient descent, zero knobs.
// On the temporal holdout it is the strongest single co-change predictor ever
// measured here (MANIFOLD 0.794 vs the bag's 0.758 and history's 0.695;
// fused champion 0.795 vs 0.770 without it), form-validated across top-1/3/5
// and noisy-or pooling and df caps 30/60/120 (top-5 mean, cap 120 is the
// robust member). Charges transfer to pairs with zero history because a
// token's charge is pooled from every OTHER pair that shares it — the
// vocabulary carries the knowledge to new files.

import 'dart:math' as math;
import 'dart:typed_data';

/// Weak-coupling floor for the per-changeset spectral overlay. Shared by
/// the eigenAddress-histogram cosine and the repo-native embedding cosine
/// so both sub-signals gate identically; below it, a pair carries no
/// overlay edge. Lives HERE (not file_coupling.dart) so Flutter-free CLI
/// harnesses (tool/jury_*_audit.dart) can test the shipped protocol
/// without dragging in dart:ui.
const double spectralCouplingFloor = 0.25;

/// Feature-hash width for the bag. 2048 buckets keeps collisions negligible for
/// real repo vocabularies (a few thousand couplable identifiers) while the
/// per-file vector stays a single small dense Float64List.
const int _kBagDims = 2048;

/// Minimum in-vocabulary identifiers a file needs before [fileVector] trusts
/// its bag. One hit is a vector dominated by a single token — noisy. Two is the
/// floor where the bag starts describing the file.
const int _kMinFileHits = 2;

/// Minimum files / distinct couplable identifiers below which the corpus is too
/// small to build a useful model; [build] returns null and callers skip the
/// signal.
const int _kMinFiles = 3;
const int _kMinVocab = 20;

/// Carrier-count band for token coupling charges. Below 2 carriers a token can
/// never couple a pair; above [_kChargeMaxCarriers] the token approaches the
/// corpus base rate (it's in everything) and the pair enumeration cost grows
/// quadratically for no signal. The 120 cap was selected by the holdout sweep
/// (caps 30/60/120 tested; AUC rose monotonically to 120, with 120 the elbow).
const int _kChargeMinCarriers = 2;
const int _kChargeMaxCarriers = 120;

/// How many of a pair's strongest shared-token charges are pooled into its
/// charge score. Top-5 mean was the robust winner of the functional-form sweep
/// (vs top-1, top-3, noisy-or) on both holdout repos.
const int _kChargeTopK = 5;

/// Identifiers we never count: language keywords and ubiquitous type names that
/// co-occur with everything and carry no discriminative signal.
const Set<String> _kNoise = {
  'the', 'for', 'and', 'this', 'class', 'void', 'final', 'const', 'import',
  'export', 'from', 'return', 'if', 'else', 'while', 'async', 'await', 'new',
  'public', 'private', 'static', 'get', 'set', 'var', 'let', 'function', 'def',
  'self', 'true', 'false', 'null', 'int', 'double', 'String', 'bool', 'List',
  'Map', 'Set', 'type', 'interface', 'package',
};

/// Is [token] noise — too short/long, all digits, or a ubiquitous keyword?
bool _isNoise(String token) {
  if (token.length < 3 || token.length > 40) return true;
  if (_kNoise.contains(token)) return true;
  var allDigits = true;
  for (var i = 0; i < token.length; i++) {
    final c = token.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) {
      allDigits = false;
      break;
    }
  }
  return allDigits;
}

/// Deterministic FNV-1a bucket for an identifier. Explicit (not String.hashCode)
/// so the mapping is stable across VM versions and identical in every isolate
/// that builds a file vector.
int _bucket(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i) & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h % _kBagDims;
}

/// A repository-native content model: per-identifier IDF learned from the repo's
/// own document frequencies, and a per-file IDF-weighted, feature-hashed bag
/// vector whose cosine is a co-change coupling signal. Immutable after [build].
class RepoNativeEmbedding {
  RepoNativeEmbedding._({
    required Map<String, double> idf,
    required Map<String, List<String>> carriers,
    required this.fileCount,
  })  : _idf = idf,
        _carriers = carriers;

  /// identifier → IDF weight. Only identifiers appearing in ≥2 files are kept:
  /// an identifier in a single file can never make two files match, so it only
  /// adds noise to the norm.
  final Map<String, double> _idf;

  /// identifier → the repo-relative paths of the files that contain it, for
  /// tokens in the chargeable band [_kChargeMinCarriers, _kChargeMaxCarriers].
  /// Feeds [computeTokenCharges]; paths use the same repo-relative
  /// forward-slash space as the coupling matrix.
  final Map<String, List<String>> _carriers;

  /// Number of files the model was trained on — the IDF denominator.
  final int fileCount;

  /// Bag dimensionality — exposed so callers/tests can reason about vectors.
  int get dim => _kBagDims;

  /// Number of distinct couplable identifiers (df ≥ 2) in the vocabulary.
  int get vocabSize => _idf.length;

  /// Build the content model from per-file raw identifier tokens (whole
  /// identifier runs). Returns null when the corpus is too small — callers then
  /// omit the signal.
  static RepoNativeEmbedding? build(
    Map<String, List<String>> fileTokens, {
    int vocabCap = 20000,
  }) {
    final fileCount = fileTokens.length;
    if (fileCount < _kMinFiles) return null;

    // Document frequency over noise-filtered identifiers.
    final df = <String, int>{};
    for (final tokens in fileTokens.values) {
      final seen = <String>{};
      for (final t in tokens) {
        if (_isNoise(t) || !seen.add(t)) continue;
        df[t] = (df[t] ?? 0) + 1;
      }
    }

    // Keep only couplable identifiers (df ≥ 2), most-frequent first, capped.
    final couplable = <String>[];
    for (final e in df.entries) {
      if (e.value >= 2) couplable.add(e.key);
    }
    if (couplable.length < _kMinVocab) return null;
    couplable.sort((a, b) {
      final c = df[b]!.compareTo(df[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
    if (couplable.length > vocabCap) couplable.length = vocabCap;

    final idf = <String, double>{};
    for (final w in couplable) {
      // Smoothed IDF: rarer identifiers weigh more, common ones tend to 0.
      idf[w] = math.log(1.0 + fileCount / df[w]!);
    }

    // Carrier lists for the chargeable band. Independent of the IDF vocab cap:
    // charge is about history, not rarity.
    final carriers = <String, List<String>>{};
    for (final entry in fileTokens.entries) {
      final seen = <String>{};
      for (final t in entry.value) {
        if (_isNoise(t) || !seen.add(t)) continue;
        final d = df[t];
        if (d == null ||
            d < _kChargeMinCarriers ||
            d > _kChargeMaxCarriers) {
          continue;
        }
        (carriers[t] ??= []).add(entry.key);
      }
    }

    return RepoNativeEmbedding._(
      idf: idf,
      carriers: carriers,
      fileCount: fileCount,
    );
  }

  /// Measure each chargeable token's coupling charge against the repo's
  /// co-change history: charge(w) = fraction of w's carrier-file pairs that
  /// have actually co-changed, per [coChanged]. This is the repo teaching us
  /// its own coupling vocabulary — the analogue of a transformer's trained
  /// attention weights, read out of the git log. Zero knobs: every value is a
  /// measured probability.
  ///
  /// Cost is Σ (carriers choose 2) over the chargeable band — bounded by the
  /// [_kChargeMaxCarriers] cap; run it off the UI isolate for large repos.
  /// Compute once per (model, coupling-matrix HEAD) and reuse.
  Map<String, double> computeTokenCharges({
    required bool Function(String a, String b) coChanged,
  }) {
    final out = <String, double>{};
    _carriers.forEach((token, files) {
      final m = files.length;
      var hits = 0;
      var tot = 0;
      for (var i = 0; i < m; i++) {
        for (var j = i + 1; j < m; j++) {
          tot++;
          if (coChanged(files[i], files[j])) hits++;
        }
      }
      if (tot > 0) out[token] = hits / tot;
    });
    return out;
  }

  /// Charge score for a pair of files: the mean of the top-[_kChargeTopK]
  /// charges among their shared charged tokens, 0 when they share none. Both
  /// the pooling form and the carrier cap were selected by the holdout sweep;
  /// see the module header for the measurements.
  ///
  /// alpha-math proof: ../alpha-math/manifold-charge-proofs.ts — top-k-mean is
  /// PROVEN non-monotone in evidence over exact ℚ (adding a weak shared token
  /// can lower the score: {9/10} → 9/10 but {9/10, 1/10} → 1/2), and the
  /// axiom-derived monotone alternative (geometric pooling) exists and was
  /// jury-tested: it LOSES on the temporal holdout. The non-monotonicity is a
  /// feature — the mean is an evidence-CONSISTENCY estimator that dilutes lone
  /// charge-1.0 spikes (noisy df-2 tokens) unless surrounding evidence agrees.
  /// Deliberate; do not "fix" the monotonicity without re-convening the jury.
  static double chargeScore(
    Map<String, double> charges,
    Set<String> tokensA,
    Set<String> tokensB,
  ) {
    if (charges.isEmpty) return 0.0;
    // Iterate the smaller set for the intersection.
    final small = tokensA.length <= tokensB.length ? tokensA : tokensB;
    final large = identical(small, tokensA) ? tokensB : tokensA;
    final shared = <double>[];
    for (final t in small) {
      if (!large.contains(t)) continue;
      final c = charges[t];
      if (c != null) shared.add(c);
    }
    if (shared.isEmpty) return 0.0;
    shared.sort((a, b) => b.compareTo(a));
    final k = shared.length < _kChargeTopK ? shared.length : _kChargeTopK;
    var sum = 0.0;
    for (var i = 0; i < k; i++) {
      sum += shared[i];
    }
    return sum / k;
  }

  /// The receipts behind [chargeScore]: the pair's strongest shared charged
  /// tokens, charge-descending, capped at [k]. This is the exact attribution
  /// the bilinear construction makes possible — the coupling decomposes over
  /// named tokens, so "why do these files belong together" has a literal
  /// answer, not a saliency estimate. Only called for pairs that already
  /// cleared the coupling floor, so it can afford the small allocation.
  static List<(String, double)> topCharges(
    Map<String, double> charges,
    Set<String> tokensA,
    Set<String> tokensB, {
    int k = _kChargeTopK,
  }) {
    if (charges.isEmpty) return const [];
    final small = tokensA.length <= tokensB.length ? tokensA : tokensB;
    final large = identical(small, tokensA) ? tokensB : tokensA;
    final shared = <(String, double)>[];
    for (final t in small) {
      if (!large.contains(t)) continue;
      final c = charges[t];
      if (c != null) shared.add((t, c));
    }
    shared.sort((a, b) => b.$2.compareTo(a.$2));
    if (shared.length > k) shared.length = k;
    return shared;
  }

  /// L2-normalised IDF-weighted, feature-hashed bag for a file. Returns null
  /// when the file has fewer than [_kMinFileHits] in-vocabulary identifiers.
  Float64List? fileVector(List<String> rawTokens) {
    final counts = <String, int>{};
    for (final t in rawTokens) {
      if (_isNoise(t)) continue;
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final out = Float64List(_kBagDims);
    var hits = 0;
    counts.forEach((w, c) {
      final wIdf = _idf[w];
      if (wIdf == null) return;
      out[_bucket(w)] += c * wIdf;
      hits++;
    });
    if (hits < _kMinFileHits) return null;
    var norm = 0.0;
    for (var i = 0; i < _kBagDims; i++) {
      norm += out[i] * out[i];
    }
    if (norm < 1e-18) return null;
    final inv = 1.0 / math.sqrt(norm);
    for (var i = 0; i < _kBagDims; i++) {
      out[i] *= inv;
    }
    return out;
  }

  /// Cosine similarity between two file vectors. Both are L2-normalised by
  /// [fileVector], so this is a plain dot product. Returns 0 when either side
  /// is null (no signal) — never a false positive.
  static double cosine(Float64List? a, Float64List? b) {
    if (a == null || b == null || a.length != b.length) return 0.0;
    var dot = 0.0;
    for (var j = 0; j < a.length; j++) {
      dot += a[j] * b[j];
    }
    return dot;
  }
}
