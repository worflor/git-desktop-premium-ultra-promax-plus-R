// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Auto-collapse policy — pure math, no widget state, so it unit-tests in
// isolation and the diff shell just wires importances in and fold-indices
// out.
//
// The policy answers: given each hunk's importance (per-file max-normalized
// φ from the logos ranker, in [0, 1]), which hunks should render folded by
// default? The honest signal in that vector is not a rank order — real diffs
// have almost no within-file φ hierarchy (the heat-kernel centrality of a
// file's hunks is nearly uniform) — it's *concentration*: how many hunks
// actually carry the diff's importance.
//
// We measure that with the participation ratio's effective-count dual, the
// same machinery the spectral engine uses for mode localization:
//
//     N_eff = (Σ φ_i)² / Σ φ_i²
//
// N_eff is the effective number of participating hunks. It equals N when φ
// is uniform (every hunk participates equally → fold nothing) and collapses
// toward 1 when one hunk dominates (→ fold the tail). We keep the
// ceil(N_eff) most-important hunks expanded and fold the rest.
//
// The fold boundary is a STRICT threshold at the marginal-participation
// value — the (keep)-th largest φ. Every hunk at or below that value folds;
// every hunk strictly above stays expanded. Because the split is on value,
// not on index, a block of tied hunks is never split across the boundary:
// a hunk is folded only when it is strictly less important than every hunk
// that stays open, so we never fold a hunk that's indistinguishable from a
// kept one.
//
// Degenerate limits hold by construction:
//   • uniform φ         → N_eff = N   → keep = N → fold nothing
//   • one dominant hunk → N_eff → 1   → fold the whole tail
//   • two-tier φ        → N_eff ≈ |top tier| → fold exactly the lower tier
//   • all-zero / empty φ→ no signal   → fold nothing
//
// No tuned constants: the only number is ceil, the natural over-estimate of
// an effective count (round/floor were measured against 200 commits of real
// diffs and both fold hunks on essentially-uniform φ — the exact pathology
// this replaces; ceil alone makes "uniform → fold nothing" an equality, not
// an approximation). See docs/architecture/diff-collapse-policy.md.

/// Indices (into the input list) of hunks that should render folded by
/// default. Empty for diffs with fewer than 3 hunks, no φ signal, or φ that
/// is uniform enough that every hunk participates.
Set<int> autoCollapseFoldIndices(List<double> importances) {
  final n = importances.length;
  // Tiny diffs read better fully expanded; the participation ratio is also
  // meaningless below a handful of hunks.
  if (n < 3) return const <int>{};

  var sum = 0.0;
  var sumSq = 0.0;
  for (final v in importances) {
    sum += v;
    sumSq += v * v;
  }
  // No importance signal at all (all-zero φ, or the ranker fell back): fold
  // nothing rather than fold everything.
  if (sumSq <= 0) return const <int>{};

  final nEff = (sum * sum) / sumSq;
  var keep = nEff.ceil();
  if (keep < 1) keep = 1;
  // Effective support spans (essentially) every hunk → nothing to fold. This
  // is the exact uniform-φ case: N_eff = N, ceil(N) = N.
  if (keep >= n) return const <int>{};

  final desc = [...importances]..sort((a, b) => b.compareTo(a));
  // Marginal-participation value: the first φ a strict top-`keep` cut would
  // drop. Fold every hunk at or below it (ties share this fate); keep every
  // hunk strictly above.
  final marginal = desc[keep];
  final folds = <int>{};
  for (var i = 0; i < n; i++) {
    if (importances[i] <= marginal) folds.add(i);
  }
  return folds;
}
