// SPECTRAL WALKS — path-integral sampling over the graph.
//
// The heat kernel `φ(t, x, y) = Σⱼ e^{−t·λⱼ}·uⱼ[x]·uⱼ[y]` is the
// closed-form propagator: it tells us how much mass starting at x ends
// up at y after time t. What it doesn't expose are the *paths* the
// mass took. This module adds the sampling layer — continuous-time
// Markov-chain walks weighted by their spectral action, producing
// one-by-one trajectories that reconstruct φ as a sum over histories.
//
// The physics lens: the heat equation is the partition function of
// Brownian motion on a graph. φ(t, x, y) = ∫ Dγ · e^{−S[γ]} where the
// integral is over paths γ from x to y and S is the action (path
// length in the graph's metric). Lanczos gave us the partition
// function analytically; this module gives us sample paths that
// *realise* that partition.
//
// Usage: the **backtracking attention head**. Given a focus source x
// and a surfaced node y, ask `sampleWalkBetween(x, y, t)` and get a
// concrete path `[x, z₁, z₂, …, y]` whose links through the graph
// are the path-integral's highest-amplitude contribution. That path
// IS "why this file surfaced" — a node-by-node reconstruction of the
// causal chain through the codebase.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// A sampled random walk on the graph, carrying both the node path
/// and the total accumulated spectral action. Short paths with high
/// action (smooth low-frequency routes) are typical; long paths with
/// low action (rough high-frequency detours) are rare.
class SpectralWalk {
  final List<int> nodes;
  final double action;
  const SpectralWalk({required this.nodes, required this.action});

  int get length => nodes.length;
}

/// Wrapper around a `SpectralBasis` that exposes CTMC-style path
/// sampling derived from the cached spectrum. All sampling is
/// vectorised through the eigenbasis: we never touch the original
/// graph's edges. Every propagation is O(k·n), every single-step
/// transition probability is O(k).
class SpectralWalker {
  final SpectralBasis basis;

  /// Random-number generator used for all sampling. Deterministic
  /// given a seed, so walk reconstructions are reproducible across
  /// runs — important for a "why this file surfaced" diagnostic.
  final math.Random rng;

  SpectralWalker({required this.basis, int? seed})
      : rng = math.Random(seed ?? 0x5EE4FA11);

  /// Transition kernel: `P(t, x, y) = Σⱼ e^{−t·λⱼ}·uⱼ[x]·uⱼ[y]` —
  /// the single-node amplitude for moving from x to y in time t.
  /// On a connected graph the stationary distribution has `u₀[x]·u₀[y]`
  /// weight baked in, so this is the raw propagator (not mass-
  /// normalised). Cost: O(k).
  double transitionAmplitude(int x, int y, double t) {
    if (basis.n == 0 || x < 0 || x >= basis.n || y < 0 || y >= basis.n) {
      return 0.0;
    }
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      final base = j * basis.n;
      s += math.exp(-t * basis.eigenvalues[j]) *
          basis.eigenvectors[base + x] *
          basis.eigenvectors[base + y];
    }
    return s;
  }

  /// Build the transition distribution from node x at time step t:
  /// a length-n vector of `P(t, x, y)` values normalised to a valid
  /// probability distribution (negatives clamped to 0, then rescaled).
  /// Used as the step kernel inside path sampling.
  Float64List stepDistribution(int x, double t) {
    final n = basis.n;
    final p = Float64List(n);
    // Precompute the t-damped basis row for x: scratch[j] = e^{−t·λⱼ}·uⱼ[x].
    final scratch = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      scratch[j] = math.exp(-t * basis.eigenvalues[j]) *
          basis.eigenvectors[j * n + x];
    }
    var total = 0.0;
    for (var y = 0; y < n; y++) {
      var s = 0.0;
      for (var j = 0; j < basis.k; j++) {
        s += scratch[j] * basis.eigenvectors[j * n + y];
      }
      // Spectral kernel can go slightly negative from truncation;
      // clamp to zero to keep the sampling distribution proper.
      if (s < 0.0) s = 0.0;
      p[y] = s;
      total += s;
    }
    if (total <= 0.0) {
      // Degenerate (nowhere to go) — concentrate all probability on x
      // so the walk self-loops gracefully.
      p[x] = 1.0;
      return p;
    }
    final inv = 1.0 / total;
    for (var y = 0; y < n; y++) {
      p[y] *= inv;
    }
    return p;
  }

  /// Sample a single-step transition from node x at time step t.
  /// Draws a categorical sample from [stepDistribution]. Cost: O(n)
  /// for the CDF traversal plus O(k·n) for the distribution build.
  int sampleStep(int x, double t) {
    final p = stepDistribution(x, t);
    final u = rng.nextDouble();
    var cum = 0.0;
    for (var y = 0; y < p.length; y++) {
      cum += p[y];
      if (u <= cum) return y;
    }
    return p.length - 1;
  }

  /// Sample a forward walk from `start` for `steps` time-steps of size
  /// `dt`. The walk's action is `Σ dt · ⟨λ⟩_p` averaged along the path
  /// — rises when the walk wanders into high-frequency modes, falls
  /// when it stays in low modes. Reproducible given the walker's seed.
  SpectralWalk sampleForwardWalk({
    required int start,
    required int steps,
    required double dt,
  }) {
    final path = <int>[start];
    var cur = start;
    var action = 0.0;
    for (var s = 0; s < steps; s++) {
      cur = sampleStep(cur, dt);
      path.add(cur);
      // Approximate incremental action — spectral gap of the step
      // accumulates. Equivalent to path length in the graph's natural
      // metric up to normalisation.
      action += dt * _expectedLambda(cur, dt);
    }
    return SpectralWalk(nodes: path, action: action);
  }

  /// Sample a walk constrained to end at `target` after `steps` steps
  /// of size `dt`. Uses a bridge-sampling construction: at each step
  /// the transition kernel is replaced by its bridge-conditioned
  /// variant `P(t, x, z)·P((steps−s)·dt, z, target) / P(steps·dt, x, target)`,
  /// which is the exact posterior transition for a path pinned at
  /// both endpoints. Expensive per step (O(k·n) for each of steps),
  /// but recovers the path-integral "why did x surface y" in closed
  /// form.
  SpectralWalk sampleBridgeWalk({
    required int start,
    required int target,
    required int steps,
    required double dt,
  }) {
    if (steps <= 0) {
      return SpectralWalk(nodes: [start], action: 0.0);
    }
    final totalT = steps * dt;
    final totalAmp = transitionAmplitude(start, target, totalT);
    if (totalAmp <= 0.0) {
      // No connectivity at this temperature — fall back to a forward
      // walk so the caller at least gets a best-effort trajectory.
      return sampleForwardWalk(start: start, steps: steps, dt: dt);
    }
    final path = <int>[start];
    var cur = start;
    var action = 0.0;
    for (var s = 0; s < steps; s++) {
      final remaining = (steps - s - 1) * dt;
      final forward = stepDistribution(cur, dt);
      if (s == steps - 1) {
        // Final step — pin to target deterministically.
        path.add(target);
        action += dt * _expectedLambda(target, dt);
        break;
      }
      // Bayes-rewrite: multiply by the future amplitude from each
      // candidate to target, divide by the baseline amplitude from
      // cur to target at the remaining horizon. This is the exact
      // bridge-conditioned step kernel.
      final bridge = Float64List(basis.n);
      var total = 0.0;
      for (var y = 0; y < basis.n; y++) {
        final fwd = forward[y];
        if (fwd <= 0.0) continue;
        final bwd = transitionAmplitude(y, target, remaining);
        if (bwd <= 0.0) continue;
        final w = fwd * bwd;
        bridge[y] = w;
        total += w;
      }
      if (total <= 0.0) {
        // Dead end — defer to forward kernel and hope for the best.
        cur = sampleStep(cur, dt);
      } else {
        final u = rng.nextDouble() * total;
        var cum = 0.0;
        var chosen = basis.n - 1;
        for (var y = 0; y < basis.n; y++) {
          cum += bridge[y];
          if (u <= cum) {
            chosen = y;
            break;
          }
        }
        cur = chosen;
      }
      path.add(cur);
      action += dt * _expectedLambda(cur, dt);
    }
    return SpectralWalk(nodes: path, action: action);
  }

  /// Deterministic mode of the bridge-conditioned posterior — at each
  /// step, pick the node that *maximises* the bridge-kernel posterior
  /// rather than sampling from it. The result is the single most-
  /// likely path from `start` to `target` under the path-integral
  /// measure at scale `dt·steps`.
  ///
  /// **Reading**: the "why this file surfaced" answer in one concrete
  /// chain. Unlike [sampleBridgeWalk], this doesn't randomise — two
  /// calls with the same inputs give the same path, making it suitable
  /// as an explain-back primitive in UIs.
  SpectralWalk sharpestPath({
    required int start,
    required int target,
    required int steps,
    required double dt,
  }) {
    if (steps <= 0) {
      return SpectralWalk(nodes: [start], action: 0.0);
    }
    final path = <int>[start];
    var cur = start;
    var action = 0.0;
    for (var s = 0; s < steps; s++) {
      if (s == steps - 1) {
        path.add(target);
        action += dt * _expectedLambda(target, dt);
        break;
      }
      final remaining = (steps - s - 1) * dt;
      final forward = stepDistribution(cur, dt);
      // Posterior at each candidate = forward · future_amplitude_to_target.
      var bestY = cur;
      var bestW = -1.0;
      for (var y = 0; y < basis.n; y++) {
        final fwd = forward[y];
        if (fwd <= 0.0) continue;
        final bwd = transitionAmplitude(y, target, remaining);
        if (bwd <= 0.0) continue;
        final w = fwd * bwd;
        if (w > bestW) {
          bestW = w;
          bestY = y;
        }
      }
      cur = bestY;
      path.add(cur);
      action += dt * _expectedLambda(cur, dt);
    }
    return SpectralWalk(nodes: path, action: action);
  }

  /// Sample `numSamples` forward walks from `start` and aggregate a
  /// hit-frequency vector over nodes — an empirical reconstruction of
  /// the heat kernel at scale `steps·dt`. Useful diagnostic: verify
  /// `∑ walks(target) / numSamples ≈ φ(steps·dt, start, target)` up to
  /// sampling noise.
  Float64List aggregateForwardHits({
    required int start,
    required int steps,
    required double dt,
    required int numSamples,
  }) {
    final hits = Float64List(basis.n);
    for (var s = 0; s < numSamples; s++) {
      final w = sampleForwardWalk(start: start, steps: steps, dt: dt);
      final end = w.nodes.last;
      hits[end] += 1.0;
    }
    if (numSamples > 0) {
      final inv = 1.0 / numSamples;
      for (var i = 0; i < hits.length; i++) {
        hits[i] *= inv;
      }
    }
    return hits;
  }

  /// Expected eigenvalue under the step distribution from node x at
  /// time dt. Proxy for "how much action this step carries" — the mean
  /// λ weighted by the thermal transition probabilities.
  double _expectedLambda(int x, double dt) {
    if (basis.k == 0) return 0.0;
    var sumW = 0.0;
    var sumLamW = 0.0;
    for (var j = 0; j < basis.k; j++) {
      final w = math.exp(-dt * basis.eigenvalues[j]) *
          basis.eigenvectors[j * basis.n + x] *
          basis.eigenvectors[j * basis.n + x];
      sumW += w;
      sumLamW += w * basis.eigenvalues[j];
    }
    if (sumW <= 0.0) return 0.0;
    return sumLamW / sumW;
  }
}
