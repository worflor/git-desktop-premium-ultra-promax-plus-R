// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// Changeset derivation — the pure, content-addressed core of the Changes-page
// view (file clustering, dim-opacity, and the spectral-coupling overlay),
// lifted out of `ChangesPage.build()`.
//
// The old design evaluated this derivation graph *inside* `build()`, re-run on
// every `setState`: a repo refresh kicked off five independent async sources,
// each landing in its own `setState`, and every rebuild re-ran `clusterFiles`
// and the file-reading spectral pass on the UI isolate. This module is the
// derivation extracted into reusable, side-effect-free pieces:
//
//   * [computeFileDimOpacity]      — the per-file dimming, a pure function of
//                                    the changed paths + the engine's volatility
//                                    / integrity stats + the coupling matrix.
//   * [spectralCouplingIsolated]   — the content-coupling pass (identifier bag
//                                    + token charges), moved off the UI isolate
//                                    via `Isolate.run` (it reads every changed
//                                    file from disk — the dominant freeze in
//                                    the old path).
//   * [ChangesetSignature]         — a content key so the controller can skip a
//                                    re-derivation when the *content* is
//                                    unchanged, even when upstream mints fresh
//                                    objects (a new `RepositoryStatus` every
//                                    refresh, a fresh `withSpectral` wrapper).
//
// `clusterFiles` (file_coupling.dart) and `withSpectral` are reused as-is by the
// controller; they stay on the main isolate because clustering reaches into the
// (non-sendable) Logos engine and the async correlatedness/hunk pipeline — but
// the controller runs them exactly ONCE per settled [ChangesetSignature] instead
// of once per `setState`, so the cost is a single sub-frame pass, not a cascade.

import 'dart:isolate';

import '../../backend/file_coupling.dart'
    show
        CouplingReceipt,
        FileCouplingMatrix,
        combinedCouplingScore,
        computeSpectralCoupling;
import '../../backend/repo_native_embedding.dart' show RepoNativeEmbedding;

/// Per-file dim opacity for the changeset, in `[0.55, 1.0]` (1.0 = full
/// presence; lower = dimmed). A pure re-expression of the old
/// `_recomputeFileDimOpacity` so it can run off the build path and be tested in
/// isolation. Returns an empty map (nothing dimmed) when there are too few files
/// to rank, when stats are unavailable, or when the changeset is too uniform to
/// separate a foreground from a background.
///
/// Three axes, blended exactly as before:
///   * surprise   — `1 − volatility / max(volatility)` (calm files stand out),
///   * centrality — mean pairwise coupling to the rest of the changeset,
///   * integrity  — the engine's per-path integrity score.
/// Files whose blended weight falls below the changeset's own median are dimmed
/// proportionally; everything at or above the median renders at full opacity.
Map<String, double> computeFileDimOpacity({
  required List<String> paths,
  required Map<String, double>? volatility,
  required Map<String, double>? integrity,
  required FileCouplingMatrix? coupling,
}) {
  if (volatility == null || paths.length < 3) return const {};

  // ── Axis 1: surprise ──────────────────────────────────────────────
  var volMax = 0.0;
  final volRaw = <double>[];
  for (final p in paths) {
    final v = volatility[p] ?? 0.0;
    volRaw.add(v);
    if (v > volMax) volMax = v;
  }
  final surprise = <String, double>{};
  for (var i = 0; i < paths.length; i++) {
    surprise[paths[i]] = volMax > 0 ? 1.0 - volRaw[i] / volMax : 1.0;
  }

  // ── Axis 2: centrality (mean pairwise coupling) ───────────────────
  final centrality = <String, double>{};
  if (coupling != null && paths.length > 1) {
    for (final p in paths) {
      var sum = 0.0;
      for (final q in paths) {
        if (q == p) continue;
        sum += combinedCouplingScore(p, q, coupling);
      }
      centrality[p] = sum / (paths.length - 1);
    }
  }

  // ── Axis 3: integrity ─────────────────────────────────────────────
  final integrityMap = integrity ?? const <String, double>{};

  // ── Blend ─────────────────────────────────────────────────────────
  final weights = <String, double>{};
  for (final p in paths) {
    final s = surprise[p] ?? 1.0;
    final c = centrality[p] ?? 0.5;
    final g = integrityMap[p] ?? 0.85;
    weights[p] = c * 0.45 + s * 0.35 + g * 0.20;
  }

  // Adaptive threshold from the changeset's own distribution.
  final sorted = weights.values.toList()..sort();
  if (sorted.isEmpty || sorted.last - sorted.first < 0.04) return const {};
  final median = sorted[sorted.length ~/ 2];

  final result = <String, double>{};
  for (final e in weights.entries) {
    if (e.value < median) {
      final t =
          ((median - e.value) / median.clamp(0.01, 1.0)).clamp(0.0, 1.0);
      result[e.key] = 1.0 - 0.45 * t;
    }
  }
  return result;
}

/// The spectral overlay plus its receipts — why each charge-coupled pair
/// couples, as exact shared-token evidence. Both cross the isolate boundary
/// as plain data.
class SpectralOverlayResult {
  final Map<String, Map<String, double>> coupling;
  final Map<String, Map<String, List<CouplingReceipt>>> receipts;
  const SpectralOverlayResult(this.coupling, this.receipts);
  static const empty = SpectralOverlayResult({}, {});
}

/// Run [computeSpectralCoupling] on a background isolate. The function reads
/// every changed file from disk (identifier harvest for the bag + charge
/// sub-signals) — on the UI isolate this was the dominant refresh freeze. All
/// inputs cross the `Isolate.run` boundary cheaply as plain data, and disk
/// reads are safe inside the worker isolate.
Future<SpectralOverlayResult> spectralCouplingIsolated({
  required List<String> paths,
  required String repoRoot,
  RepoNativeEmbedding? embedding,
  Map<String, double>? tokenCharges,
}) {
  if (paths.length < 2) return Future.value(SpectralOverlayResult.empty);
  return Isolate.run(() {
    final receipts = <String, Map<String, List<CouplingReceipt>>>{};
    final spec = computeSpectralCoupling(
      paths,
      repoRoot,
      embedding: embedding,
      tokenCharges: tokenCharges,
      receiptsOut: receipts,
    );
    return SpectralOverlayResult(spec, receipts);
  });
}

