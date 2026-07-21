// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_ratchet.dart — learned prior for claim-shape outcomes.
//
// Axis 5 of the emergent review pipeline. When the user actions a
// review finding we record the observation keyed by the claim's
// quantised shape hash, and future claims with the same shape get the
// learned posterior as their prior.
//
// In the current product only DISMISS is surfaced (see the finding card),
// so observations are reject-only and the posterior is one-sided: it
// slides from 0.5 (unseen / neutral) toward 0 (repeatedly dismissed →
// suppressed). This is intentional — a per-repo noise filter the user
// trains by muting, with no boost direction to over-amplify. The accept
// path below is kept intact for a future implicit "this was real" signal
// (e.g. the user editing the flagged hunk), which would restore the
// two-sided estimator without asking anyone to click a Confirm button.
//
// The prior is Laplace-smoothed (add-one) so unseen shapes return
// exactly `0.5` — the codebase's maximum-uncertainty convention. As
// reject observations accumulate, the prior converges toward 0 for that
// shape bucket (and would converge to the true accept fraction once the
// accept signal is wired).
//
// In-memory for v1. The state is JSON-serialisable (see [toJson] /
// [fromJson]) so a future persistence layer — SharedPreferences,
// per-repo `.logos/review_ratchet.json`, or whatever the project
// settles on — can hook in without touching the math.

import 'dart:convert' show json;

import 'json_safety.dart';
import 'review_logos.dart' show ClaimShape;

/// Per-shape outcome counters. Accept / reject tallies feed the
/// Laplace-smoothed `p(accept | shape) = (accepts + 1) / (accepts +
/// rejects + 2)` prior.
class _Bucket {
  _Bucket({this.accepts = 0, this.rejects = 0});

  int accepts;
  int rejects;

  int get total => accepts + rejects;

  double get smoothedAcceptRate =>
      (accepts + 1.0) / (total + 2.0);

  Map<String, int> toJson() => {'a': accepts, 'r': rejects};

  /// Total parse. A missing counter defaults to 0 (older-schema
  /// tolerance), but a present-and-wrong-typed counter makes the whole
  /// bucket malformed — returns null so [ClaimOutcomeRatchet.fromJsonString]
  /// drops the entry per its contract, rather than recording a
  /// fabricated observation bucket.
  static _Bucket? fromJsonOrNull(Map<String, Object?> j) {
    final a = j['a'];
    final r = j['r'];
    final accepts = a == null ? 0 : asIntOrNull(a);
    final rejects = r == null ? 0 : asIntOrNull(r);
    if (accepts == null || rejects == null) return null;
    return _Bucket(accepts: accepts, rejects: rejects);
  }
}

/// In-memory store of (shape → outcome-counts). Backs the axis-5
/// learned prior in [composeReviewScore].
///
/// The store is keyed by [ClaimShape.shapeHash] — a 32-bit quantised
/// projection of the five axes. Two claims with similar but not
/// identical shapes land in the same bucket; this is the point. The
/// ratchet wouldn't generalise otherwise.
///
/// **Not isolate-safe**: the internal bucket map is plain `Map<int,
/// _Bucket>` with no synchronisation. Create one ratchet per
/// isolate, or if sharing is required, wrap [observe] in external
/// mutex coordination. In practice this is fine — review scoring
/// runs on the UI isolate, and persistence across isolate
/// boundaries happens via [toJsonString] → serialised copy, which
/// makes the sharing explicit.
class ClaimOutcomeRatchet {
  ClaimOutcomeRatchet();

  final Map<int, _Bucket> _buckets = {};

  /// Record that a claim was accepted (`verified = true`) or rejected
  /// (`verified = false`). The entry is keyed by the claim's shape
  /// hash, not the claim text, so shape-equivalent claims share
  /// posterior mass.
  void observe({required ClaimShape shape, required bool verified}) {
    final key = shape.shapeHash();
    final bucket = _buckets.putIfAbsent(key, () => _Bucket());
    if (verified) {
      bucket.accepts++;
    } else {
      bucket.rejects++;
    }
  }

  /// Posterior `p(verified | shape)` with Laplace smoothing. An
  /// unseen shape maps to `0.5` — the max-uncertainty value — so the
  /// Born-mixer blend in [composeReviewScore] doesn't push a hot
  /// opinion in either direction until the ratchet has seen real
  /// observations.
  double priorFor(ClaimShape shape) {
    final bucket = _buckets[shape.shapeHash()];
    if (bucket == null) return 0.5;
    return bucket.smoothedAcceptRate;
  }

  /// Observation count in this shape's bucket. Used by the Born
  /// blend as the evidence weight for the prior axis: buckets with
  /// 1000 observations carry more weight than buckets with 3.
  int observationCountFor(ClaimShape shape) {
    return _buckets[shape.shapeHash()]?.total ?? 0;
  }

  /// Total observations across every bucket. Useful for diagnostics
  /// (how much data has the ratchet accumulated?) and for stopping
  /// conditions in generative tests.
  int get totalObservations =>
      _buckets.values.fold(0, (sum, b) => sum + b.total);

  /// Distinct shape buckets tracked so far. A proxy for "how varied
  /// are the claim shapes we've seen."
  int get bucketCount => _buckets.length;

  /// Serialise for persistence. The bucket key is emitted as its
  /// decimal string so the JSON is grep-able in plain tooling.
  String toJsonString() {
    final map = <String, dynamic>{
      for (final e in _buckets.entries) e.key.toString(): e.value.toJson(),
    };
    return json.encode(map);
  }

  /// Rehydrate from [toJsonString]. Unknown / malformed entries are
  /// silently dropped — the ratchet always stays well-formed, even
  /// when a persistence file from an older schema is read. Fully
  /// garbled input (not valid JSON at all) also yields an empty
  /// ratchet rather than throwing — we'd rather lose accumulated
  /// observations on disk corruption than prevent the app from
  /// starting.
  static ClaimOutcomeRatchet fromJsonString(String src) {
    final ratchet = ClaimOutcomeRatchet();
    if (src.trim().isEmpty) return ratchet;
    dynamic decoded;
    try {
      decoded = json.decode(src);
    } catch (_) {
      return ratchet;
    }
    if (decoded is! Map<String, dynamic>) return ratchet;
    decoded.forEach((key, value) {
      // Each entry is parsed under its own guard so one malformed bucket
      // (bad key, wrong shape, or a present-but-wrong-typed "a"/"r")
      // drops just that entry instead of aborting the whole rehydrate —
      // belt-and-suspenders alongside _Bucket.fromJsonOrNull's own total
      // json_safety reads.
      try {
        final parsedKey = int.tryParse(key);
        if (parsedKey == null) return;
        final map = asMapOrNull(value);
        if (map == null) return;
        final bucket = _Bucket.fromJsonOrNull(map);
        if (bucket == null) return;
        ratchet._buckets[parsedKey] = bucket;
      } catch (_) {
        // Drop the malformed entry; never let it take down the parse.
      }
    });
    return ratchet;
  }

  /// Clear every bucket. Exists for tests and for the "start over
  /// after schema change" case; never called in production flow.
  void clear() {
    _buckets.clear();
  }
}
