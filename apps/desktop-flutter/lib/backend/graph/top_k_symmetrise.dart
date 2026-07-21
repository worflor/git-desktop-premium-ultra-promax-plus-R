// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// top_k_symmetrise.dart — per-row top-K trim + symmetric-union
// sparsifier for the hunk- and chunk-level heat-kernel engines.
//
// Input: a symmetric sparse edges map `edges[i][j]` where
// `edges[i][j] == edges[j][i]` (the `addEdge` helpers in
// logos_hunks / logos_chunks write both directions with summed
// duplicates, so this invariant holds by construction).
//
// Output: a deduped `List<CsrEdge>` with each undirected pair
// appearing exactly once, ready for [buildSymmetricCsrGraph].
//
// Policy:
// - Per-row top-K keeps the [topK] heaviest edges by weight. Ties
//   broken by the map iteration order — not observable for the
//   spectra downstream (degree-fused values wash out any rank-tie
//   permutation).
// - Symmetric union: an edge survives if EITHER endpoint kept it
//   in its top-K row. The weight is unchanged by the union (equal
//   on both sides by the symmetry invariant above).
//
// Centralising this policy means any future change — different
// top-K rules, weight-aware tiebreakers, alternative sparsifiers —
// lands in one place instead of getting re-implemented per engine.

import 'csr_builder.dart';

/// Sparsify [edges] via per-row top-K trim then symmetric union,
/// returning a deduped CsrEdge list ready for
/// [buildSymmetricCsrGraph].
///
/// [edges] must already be symmetric (`edges[i][j] == edges[j][i]`).
/// The logos engines' `addEdge` helper establishes this invariant by
/// writing both directions for every call.
///
/// Cost: O(Σ dᵢ·log dᵢ) over rows whose degree dᵢ exceeds [topK]; rows
/// that already fit within [topK] cost O(dᵢ) (the sort is skipped).
List<CsrEdge> topKSymmetriseEdges({
  required Map<int, Map<int, double>> edges,
  required int topK,
}) {
  // Per-row top-K trim. We walk every row and keep its [topK] heaviest
  // edges. Lex-order ties are resolved by Map iteration order — not
  // observable for the spectra downstream (degree-fused values wash out
  // any rank-tie permutation), so the graph structure is deterministic
  // within a single build.
  final kept = <(int, int), double>{};
  for (final rowEntry in edges.entries) {
    final i = rowEntry.key;
    final row = rowEntry.value;
    if (row.isEmpty) continue;
    // When the row already fits within topK, every edge is kept
    // regardless of rank, so ranking it is pure waste — iterate the row
    // directly. The (a,b)-keyed `kept` map makes the visit order
    // irrelevant (each pair maps to the same weight either way), so
    // skipping the sort here is bit-identical, not an approximation.
    // Only over-degree rows pay the O(d·log d) sort; in a co-change
    // graph most rows are small, so this skips the common case.
    final Iterable<MapEntry<int, double>> top;
    if (row.length <= topK) {
      top = row.entries;
    } else {
      top = (row.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(topK);
    }
    for (final e in top) {
      final j = e.key;
      final w = e.value;
      final a = i < j ? i : j;
      final b = i < j ? j : i;
      // Symmetry invariant: `edges[i][j] == edges[j][i]`. The union
      // step then collapses to a plain assignment — whichever row
      // top-K keeps the pair writes the same weight. If a future
      // caller ever supplies an asymmetric edges map, the winning
      // weight becomes iteration-order dependent, which is almost
      // never what you want. Debug-only assert: cheap in profile
      // mode, catches a real footgun in testing.
      assert(() {
        final mirror = edges[j]?[i];
        return mirror == null || mirror == w;
      }(),
          'topKSymmetriseEdges requires edges[i][j] == edges[j][i]; '
          'caller passed asymmetric weights for ($i, $j).');
      kept[(a, b)] = w;
    }
  }
  return [
    for (final entry in kept.entries)
      CsrEdge(entry.key.$1, entry.key.$2, entry.value),
  ];
}
