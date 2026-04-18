// LogosMind — the AI synthesis.
//
// A facade over [LogosGit] + per-file engrams + the generative spectral
// primitives. Three inference modes:
//
//   • `ask(query)`    — retrieval-augmented inference (heat kernel +
//                       grounding)
//   • `dream(query)`  — generative inference (conditional GFF samples)
//   • `evolve(query)` — dynamical inference (Langevin chain)
//
// Every answer is a deterministic function of (engine state, rng seed).
// Every candidate carries a grounding trace — which seeds contributed,
// which coupling edges fired, which engram matched — so the host app
// can cite without hallucination.
//
// See `docs/architecture/logos-mind.md` for the architecture and
// `docs/architecture/spectral-generative.md` for the generative math.

import 'dart:math' as math;
import 'dart:typed_data';

import 'engram_fit.dart';
import 'logos_core.dart';
import 'logos_git.dart';

/// A query to the mind. Sealed — every variant has a deterministic
/// translation into seed weights on the engine's nodes.
sealed class MindQuery {
  const MindQuery();

  /// A single file as the anchor. One-hot on that node if it exists.
  const factory MindQuery.path(String path) = PathMindQuery;

  /// A file + line pair. The line is display-only for now; the seed
  /// weight is still one-hot on the path.
  const factory MindQuery.line(String path, int line) = LineMindQuery;

  /// A list of code symbols / tokens. Matches them against the
  /// engine's `symbolEdges` to find paths that share any of the
  /// tokens; weights each path by overlap count.
  const factory MindQuery.tokens(List<String> tokens) = TokensMindQuery;

  /// Free-form text. Split into whitespace tokens (lower-cased),
  /// then as if `MindQuery.tokens(...)`.
  const factory MindQuery.text(String text) = TextMindQuery;

  /// Explicit weight distribution. Use this when upstream logic has
  /// already built a source — e.g. the diff-probe axis blend.
  const factory MindQuery.weighted(Map<String, double> weights) =
      WeightedMindQuery;
}

final class PathMindQuery extends MindQuery {
  final String path;
  const PathMindQuery(this.path);
}

final class LineMindQuery extends MindQuery {
  final String path;
  final int line;
  const LineMindQuery(this.path, this.line);
}

final class TokensMindQuery extends MindQuery {
  final List<String> tokens;
  const TokensMindQuery(this.tokens);
}

final class TextMindQuery extends MindQuery {
  final String text;
  const TextMindQuery(this.text);
}

final class WeightedMindQuery extends MindQuery {
  final Map<String, double> weights;
  const WeightedMindQuery(this.weights);
}

/// One ranked answer from the mind. Carries enough grounding that the
/// host app can render it without re-querying the engine.
class MindCandidate {
  /// The file path.
  final String path;

  /// Primary score — the heat-kernel amplitude `φ(node)` at the
  /// diffusion temperature chosen for this query. Positive; higher is
  /// more relevant. Not normalised across queries.
  final double score;

  /// Wentzell-Freidlin effective action (gravitational potential)
  /// between the query's seed centroid and this candidate, at the
  /// chosen temperature. Low = strongly bound; high = weakly coupled;
  /// `double.infinity` when disconnected. `null` when the basis has
  /// no seed to compare against.
  final double? gravity;

  /// Spectral participation entropy (normalised, 0..1) at this node.
  /// Wide reach = the node sits across many modes.
  final double? reach;

  /// Boost from engram memory — cosine similarity of the AR(2)
  /// damping/orbit between seed and candidate. `null` when either
  /// lacks a non-trivial engram fit.
  final double? engramBoost;

  /// Per-axis contribution breakdown: why this candidate surfaced.
  /// Each axis sits in [0, 1]; the whole tuple is not normalised
  /// (candidates can be strong on multiple axes at once). `null` when
  /// the candidate was built from a path that isn't in the engine's
  /// coupling/activity maps.
  final MindAxisContribution? axis;

  /// Human-readable grounding. Each string is derived from a specific
  /// numerical signal (edge weight, engram match, mode attribution).
  /// Safe to show in a UI.
  final List<String> grounding;

  const MindCandidate({
    required this.path,
    required this.score,
    this.gravity,
    this.reach,
    this.engramBoost,
    this.axis,
    this.grounding = const [],
  });
}

/// Per-axis contribution to a candidate's ranking. Each axis reads a
/// different source of "why this file surfaced":
///
/// * `f0` — activity mass. The candidate is touched often in general.
/// * `cc` — coupling (jaccard). Candidate shares commits with the seed.
/// * `m`  — modifier (shared-directory / same-package). Structural
///          adjacency to the seed.
/// * `ab` — semantic similarity. Candidate shares symbols / tokens
///          with the seed.
/// * `en` — engram memory. Temporal pattern of touches matches the
///          seed's AR(2) fit.
///
/// Each value lives in [0, 1]; higher = stronger contribution.
/// Consumers (e.g. verb-register selection in `logos_dream.dart`) can
/// read the dominant axis to pick a vocabulary class without heuristics.
class MindAxisContribution {
  final double f0;
  final double cc;
  final double m;
  final double ab;
  final double en;

  const MindAxisContribution({
    this.f0 = 0.0,
    this.cc = 0.0,
    this.m = 0.0,
    this.ab = 0.0,
    this.en = 0.0,
  });

  static const uniform =
      MindAxisContribution(f0: 0.2, cc: 0.2, m: 0.2, ab: 0.2, en: 0.2);

  /// Name of the dominant axis — the single strongest signal. Returns
  /// null when every axis is effectively zero.
  String? get dominant {
    final entries = {
      'f0': f0, 'cc': cc, 'm': m, 'ab': ab, 'en': en,
    };
    String? best;
    double bestV = 1e-9;
    entries.forEach((name, v) {
      if (v > bestV) {
        bestV = v;
        best = name;
      }
    });
    return best;
  }

  /// Dot product — the scalar that a bias vector produces when applied
  /// to this contribution. Used in [MindSession.reinforce] to nudge
  /// ranking toward the axes the user has previously preferred.
  double dot(MindAxisContribution other) =>
      f0 * other.f0 +
      cc * other.cc +
      m * other.m +
      ab * other.ab +
      en * other.en;

  /// Linear interpolation toward `other` by `t ∈ [0, 1]`. Used to
  /// smoothly drift the session's axis bias toward an accepted
  /// candidate's contribution profile.
  MindAxisContribution lerp(MindAxisContribution other, double t) {
    final clamped = t.clamp(0.0, 1.0).toDouble();
    return MindAxisContribution(
      f0: f0 + (other.f0 - f0) * clamped,
      cc: cc + (other.cc - cc) * clamped,
      m: m + (other.m - m) * clamped,
      ab: ab + (other.ab - ab) * clamped,
      en: en + (other.en - en) * clamped,
    );
  }
}

/// Full response from [LogosMind.ask]. Bundles the ranked candidates,
/// the propagated field, and provenance.
class MindResponse {
  /// Ranked candidates, highest relevance first. Excludes seed paths.
  final List<MindCandidate> candidates;

  /// Propagated source field `φ(node)`. Length = `engine.graph.n`.
  final Float64List focus;

  /// Seed paths derived from the query. Empty if the query couldn't
  /// be grounded in any node.
  final Set<String> seedPaths;

  /// Diffusion temperature actually used (may differ from request if
  /// snapped to a heat-capacity peak — see `logos_git_probe`).
  final double temperature;

  /// Self-critique signal in [0, 1]. `null` on a simple `ask`; populated
  /// by [MindSession.consensus] which cross-checks against a dream
  /// pass. High = ask and dream agree; low = engine is uncertain.
  final double? confidence;

  /// Prose summary: one or two sentences describing the top result.
  final String explanation;

  const MindResponse({
    required this.candidates,
    required this.focus,
    required this.seedPaths,
    required this.temperature,
    required this.explanation,
    this.confidence,
  });

  /// Quick accessor for the top path, or null when no candidates.
  String? get topPath => candidates.isEmpty ? null : candidates.first.path;

  /// Returns a copy with fields overridden. Used by [MindSession] to
  /// attach confidence + re-ranking without building a whole new
  /// response from scratch.
  MindResponse copyWith({
    List<MindCandidate>? candidates,
    double? confidence,
    String? explanation,
  }) {
    return MindResponse(
      candidates: candidates ?? this.candidates,
      focus: focus,
      seedPaths: seedPaths,
      temperature: temperature,
      explanation: explanation ?? this.explanation,
      confidence: confidence ?? this.confidence,
    );
  }
}

/// A single dream — one sample from the GFF posterior conditional on
/// the query's seeds.
class MindDream {
  /// Full sampled field on all nodes.
  final Float64List field;

  /// Top contributors in this dream (excluding seeds), ranked.
  final List<MindCandidate> top;

  /// Residual energy — L² norm of the dream excluding observed nodes.
  /// Larger = this dream is more "original" relative to the seeds.
  final double residualEnergy;

  const MindDream({
    required this.field,
    required this.top,
    required this.residualEnergy,
  });
}

/// A Langevin trajectory — the query evolved under the repo's
/// stochastic physics.
class MindEvolution {
  /// Snapshots of ρ over the chain. `trajectory.first` is ρ₀; the
  /// last element is the final (possibly mixed) state.
  final List<Float64List> trajectory;

  /// Ranked candidates at the final step.
  final List<MindCandidate> finalRanking;

  /// Approximate mixing indicator: the L² distance between the last
  /// two snapshots, normalised. Small = chain has settled.
  final double finalStepDelta;

  const MindEvolution({
    required this.trajectory,
    required this.finalRanking,
    required this.finalStepDelta,
  });
}

/// The AI synthesis — composes the Logos engine, per-file engrams, and
/// the generative spectral primitives into a single query surface.
///
/// Construction: just `LogosMind(engine: engine)`. Every inference
/// method is pure — no internal mutable state, no caching beyond what
/// the wrapped [LogosGit] already caches.
class LogosMind {
  final LogosGit engine;

  const LogosMind({required this.engine});

  // ─── Perception ────────────────────────────────────────────────────

  /// Translate any [MindQuery] into a weight distribution over paths.
  /// Pure function of the query + the engine's vocabulary.
  ///
  /// Returns an empty map when the query cannot be grounded — e.g.
  /// a path that isn't in the graph, or tokens that match nothing.
  Map<String, double> resolveQuery(MindQuery query) {
    switch (query) {
      case PathMindQuery q:
        return engine.pathToId.containsKey(q.path)
            ? {q.path: 1.0}
            : const {};
      case LineMindQuery q:
        return engine.pathToId.containsKey(q.path)
            ? {q.path: 1.0}
            : const {};
      case TokensMindQuery q:
        return _weightsFromTokens(q.tokens);
      case TextMindQuery q:
        final toks = q.text
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9_]+'))
            .where((t) => t.length >= 3)
            .toList();
        return _weightsFromTokens(toks);
      case WeightedMindQuery q:
        // Keep only paths the engine knows.
        final out = <String, double>{};
        q.weights.forEach((path, w) {
          if (engine.pathToId.containsKey(path) && w.isFinite && w > 0) {
            out[path] = w;
          }
        });
        return out;
    }
  }

  Map<String, double> _weightsFromTokens(List<String> tokens) {
    if (tokens.isEmpty) return const {};
    final lcTokens = {for (final t in tokens) t.toLowerCase()};
    final scores = <String, double>{};
    engine.symbolEdges.forEach((path, syms) {
      if (!engine.pathToId.containsKey(path)) return;
      var overlap = 0.0;
      syms.forEach((sym, w) {
        if (lcTokens.contains(sym.toLowerCase())) {
          overlap += w;
        }
      });
      if (overlap > 0) scores[path] = overlap;
    });
    if (scores.isEmpty) return const {};
    // Normalise so the total mass is 1 — keeps diffusion amplitudes
    // comparable across queries of different token counts.
    final total = scores.values.reduce((a, b) => a + b);
    return {for (final e in scores.entries) e.key: e.value / total};
  }

  // ─── Ask — retrieval-augmented inference ───────────────────────────

  /// Propagate a query through the heat kernel; rank non-seed nodes by
  /// amplitude; enrich with gravity, reach, engram boost; ground the
  /// top N. Deterministic (no rng usage).
  MindResponse ask(
    MindQuery query, {
    double temperature = 1.0,
    int topN = 10,
  }) {
    final seeds = resolveQuery(query);
    if (seeds.isEmpty) {
      return MindResponse(
        candidates: const [],
        focus: Float64List(engine.graph.n),
        seedPaths: const {},
        temperature: temperature,
        explanation: 'no seed in graph',
      );
    }

    // Propagate — let the engine pick the snapped temperature. Fetch
    // more than topN because `diffuseWeighted` can surface symbol-edge
    // pseudo-paths we need to filter out.
    final rawScored = engine.diffuseWeighted(
      seeds,
      t: temperature,
      excludePaths: seeds.keys.toSet(),
      topK: topN * 4,
    );
    // Keep only results that are actual graph nodes.
    final scored = [
      for (final s in rawScored)
        if (engine.pathToId.containsKey(s.path)) s
    ];

    final basis = engine.spectralBasis();
    final focus = _buildFocusField(seeds, temperature, basis);
    final seedCenter = _seedCentroid(seeds, basis);

    // Enrich each candidate.
    final enriched = <MindCandidate>[];
    for (final s in scored.take(topN)) {
      final id = engine.pathToId[s.path];
      double? gravity;
      double? reach;
      double? engramBoost;
      final grounding = <String>[];

      if (basis != null && id != null) {
        if (seedCenter != null) {
          gravity = basis.gravitationalPotential(
              seedCenter, id, temperature);
        }
        reach = _reachAtNode(basis, id);
      }

      // Engram match: compare AR(2) fit of seed cluster to candidate.
      engramBoost = _engramMatchAgainstSeeds(s.path, seeds.keys);

      // Axis attribution — which of F0/CC/M/Ab/EN surfaced this one.
      final axis =
          _axisAttributionFor(s.path, seeds, engramBoost: engramBoost);

      // Grounding — strongest coupling contributors + engram + gravity.
      _populateGrounding(
        grounding: grounding,
        candidate: s.path,
        seeds: seeds,
        gravity: gravity,
        engramBoost: engramBoost,
      );

      enriched.add(MindCandidate(
        path: s.path,
        score: s.phi,
        gravity: gravity,
        reach: reach,
        engramBoost: engramBoost,
        axis: axis,
        grounding: grounding,
      ));
    }

    return MindResponse(
      candidates: enriched,
      focus: focus,
      seedPaths: seeds.keys.toSet(),
      temperature: temperature,
      explanation: _synthesizeExplanation(enriched, seeds),
    );
  }

  // ─── Dream — generative inference ──────────────────────────────────

  /// Sample [samples] conditional GFF draws, each pinned at the query's
  /// seeds. Returns each sample with its top contributors. Deterministic
  /// given [rng].
  ///
  /// `mass` regularises the zero mode — use a small positive value
  /// (0.3–1.0) to keep samples finite on graphs with disconnected
  /// components or near-zero spectral gap.
  List<MindDream> dream(
    MindQuery query, {
    int samples = 8,
    math.Random? rng,
    double mass = 0.5,
    int topN = 5,
  }) {
    final basis = engine.spectralBasis();
    if (basis == null) return const [];
    final seeds = resolveQuery(query);
    if (seeds.isEmpty) return const [];

    final observedNodes = <int>[];
    final observedValues = <double>[];
    seeds.forEach((path, w) {
      final id = engine.pathToId[path];
      if (id != null) {
        observedNodes.add(id);
        observedValues.add(w);
      }
    });
    if (observedNodes.isEmpty) return const [];

    final r = rng ?? math.Random(0x10605);
    final out = <MindDream>[];
    for (var s = 0; s < samples; s++) {
      final field = basis.sampleConditionalGFF(
        observedNodes: observedNodes,
        observedValues: Float64List.fromList(observedValues),
        rng: r,
        mass: mass,
      );
      // Rank non-seed nodes by |field|.
      final top = _rankFieldNonSeed(field, seeds.keys.toSet(), topN);
      final residual = _residualEnergy(field, observedNodes);
      out.add(MindDream(
        field: field,
        top: top,
        residualEnergy: residual,
      ));
    }
    return out;
  }

  // ─── Evolve — dynamical inference ──────────────────────────────────

  /// Run Langevin dynamics from the query's seed ρ for [steps] steps.
  /// Returns the full trajectory and the final ranking.
  ///
  /// Typical parameters:
  /// * `dt ≈ 0.1` (stable for most graphs)
  /// * `beta ≈ 1.0` (temperature scale)
  /// * `mass ≈ 0.5` (zero-mode regulariser)
  /// * `steps ≈ 100–500` (mixing time ~ 1/λ₁)
  MindEvolution evolve(
    MindQuery query, {
    int steps = 100,
    double dt = 0.1,
    double beta = 1.0,
    double mass = 0.5,
    math.Random? rng,
    int topN = 10,
  }) {
    final basis = engine.spectralBasis();
    if (basis == null) {
      return MindEvolution(
        trajectory: const [],
        finalRanking: const [],
        finalStepDelta: 0.0,
      );
    }
    final seeds = resolveQuery(query);
    if (seeds.isEmpty) {
      return MindEvolution(
        trajectory: const [],
        finalRanking: const [],
        finalStepDelta: 0.0,
      );
    }

    final r = rng ?? math.Random(0x10010);
    final n = basis.n;
    var rho = Float64List(n);
    seeds.forEach((path, w) {
      final id = engine.pathToId[path];
      if (id != null) rho[id] = w;
    });

    final trajectory = <Float64List>[Float64List.fromList(rho)];
    for (var s = 0; s < steps; s++) {
      final next = basis.langevinStep(
        rho: rho,
        dt: dt,
        beta: beta,
        rng: r,
        mass: mass,
      );
      trajectory.add(Float64List.fromList(next));
      rho = next;
    }

    // Final-step delta as mixing indicator.
    double delta = 0.0;
    if (trajectory.length >= 2) {
      final prev = trajectory[trajectory.length - 2];
      final last = trajectory.last;
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < n; i++) {
        final d = last[i] - prev[i];
        num += d * d;
        den += last[i] * last[i];
      }
      delta = den > 1e-12 ? math.sqrt(num / den) : 0.0;
    }

    // Rank final state.
    final ranking = _rankFieldNonSeed(rho, seeds.keys.toSet(), topN);
    return MindEvolution(
      trajectory: trajectory,
      finalRanking: ranking,
      finalStepDelta: delta,
    );
  }

  // ─── Internals ─────────────────────────────────────────────────────

  Float64List _buildFocusField(
    Map<String, double> seeds,
    double t,
    SpectralBasis? basis,
  ) {
    final n = engine.graph.n;
    if (n == 0 || basis == null) return Float64List(n);
    final rho = Float64List(n);
    seeds.forEach((path, w) {
      final id = engine.pathToId[path];
      if (id != null) rho[id] = w;
    });
    return basis.diffuse(rho, t);
  }

  /// Pick a seed-centroid node: the seed with the greatest raw weight.
  /// Used as the reference for `gravitationalPotential` — gives us a
  /// single number per candidate rather than a multi-source sum.
  int? _seedCentroid(Map<String, double> seeds, SpectralBasis? basis) {
    if (basis == null || seeds.isEmpty) return null;
    String? best;
    double bestW = -1;
    seeds.forEach((path, w) {
      if (w > bestW && engine.pathToId.containsKey(path)) {
        bestW = w;
        best = path;
      }
    });
    if (best == null) return null;
    return engine.pathToId[best!];
  }

  double _reachAtNode(SpectralBasis basis, int nodeId) {
    // 1-hot projection in O(k).
    final k = basis.k;
    if (k == 0) return 0.0;
    var z = 0.0;
    final weighted = Float64List(k);
    for (var j = 0; j < k; j++) {
      final c = basis.eigenvectors[j * basis.n + nodeId];
      final w = math.exp(-1.0 * basis.eigenvalues[j]) * c * c;
      weighted[j] = w;
      z += w;
    }
    if (z <= 1e-300) return 0.0;
    final invZ = 1.0 / z;
    var s = 0.0;
    for (var j = 0; j < k; j++) {
      final p = weighted[j] * invZ;
      if (p > 1e-300) s -= p * math.log(p);
    }
    final sMax = math.log(k.toDouble());
    return sMax > 0 ? (s / sMax).clamp(0.0, 1.0).toDouble() : 0.0;
  }

  /// Engram match: maximum cosine between the candidate's AR(2) fit
  /// parameters and any seed's fit. Returns null when neither side
  /// has a non-fallback fit.
  double? _engramMatchAgainstSeeds(
      String candidate, Iterable<String> seeds) {
    final metrics = engine.perFileMetrics;
    final candFit = metrics[candidate];
    if (candFit == null || candFit.isLinearFallback) return null;
    double best = -1.0;
    var matched = false;
    for (final seed in seeds) {
      final seedFit = metrics[seed];
      if (seedFit == null || seedFit.isLinearFallback) continue;
      final sim = _engramCosine(candFit, seedFit);
      if (sim > best) best = sim;
      matched = true;
    }
    return matched ? best : null;
  }

  /// Cosine similarity in the (K, G) engram plane. Both fits live on
  /// the same 2D parameter space; cosine gives a bounded [-1, 1] match.
  double _engramCosine(EngramFit a, EngramFit b) {
    final na = math.sqrt(a.k * a.k + a.g * a.g);
    final nb = math.sqrt(b.k * b.k + b.g * b.g);
    if (na <= 1e-12 || nb <= 1e-12) return 0.0;
    return ((a.k * b.k + a.g * b.g) / (na * nb)).clamp(-1.0, 1.0);
  }

  void _populateGrounding({
    required List<String> grounding,
    required String candidate,
    required Map<String, double> seeds,
    double? gravity,
    double? engramBoost,
  }) {
    // Gravity tier — mirrors the diff-manifold language.
    if (gravity != null && gravity.isFinite) {
      if (gravity < 1.5) {
        grounding.add('tightly bound to seed');
      } else if (gravity < 4.0) {
        grounding.add('orbiting seed');
      } else {
        grounding.add('weakly coupled to seed');
      }
    }
    // Coupling to the strongest seed — reads from symbolEdges.
    String? strongestSeed;
    double strongestCoupling = 0.0;
    for (final seed in seeds.keys) {
      final syms = engine.symbolEdges[seed];
      if (syms == null) continue;
      final candSyms = engine.symbolEdges[candidate];
      if (candSyms == null) continue;
      var shared = 0.0;
      candSyms.forEach((sym, w) {
        final sw = syms[sym];
        if (sw != null) shared += math.min(w, sw);
      });
      if (shared > strongestCoupling) {
        strongestCoupling = shared;
        strongestSeed = seed;
      }
    }
    if (strongestSeed != null && strongestCoupling > 0) {
      grounding.add(
          'co-moves with ${_displayPath(strongestSeed!)} '
          '(coupling ${strongestCoupling.toStringAsFixed(2)})');
    }
    // Engram — only when match is meaningful.
    if (engramBoost != null && engramBoost > 0.7) {
      grounding.add(
          'shares temporal pattern (engram match ${engramBoost.toStringAsFixed(2)})');
    }
  }

  List<MindCandidate> _rankFieldNonSeed(
    Float64List field,
    Set<String> seeds,
    int topN,
  ) {
    final paths = engine.nodePaths;
    final ranked = <({int id, double amp})>[];
    for (var i = 0; i < field.length; i++) {
      final path = paths[i];
      if (seeds.contains(path)) continue;
      ranked.add((id: i, amp: field[i].abs()));
    }
    ranked.sort((a, b) => b.amp.compareTo(a.amp));
    final take = math.min(topN, ranked.length);
    return [
      for (var i = 0; i < take; i++)
        MindCandidate(
          path: paths[ranked[i].id],
          score: ranked[i].amp,
        ),
    ];
  }

  double _residualEnergy(Float64List field, List<int> observedNodes) {
    final observed = observedNodes.toSet();
    var e = 0.0;
    for (var i = 0; i < field.length; i++) {
      if (observed.contains(i)) continue;
      e += field[i] * field[i];
    }
    return e;
  }

  String _synthesizeExplanation(
      List<MindCandidate> cands, Map<String, double> seeds) {
    if (cands.isEmpty) return 'no results';
    final top = cands.first;
    final buf = StringBuffer();
    buf.write('nearest: ${_displayPath(top.path)}');
    if (top.grounding.isNotEmpty) {
      buf.write(' (${top.grounding.first})');
    }
    return buf.toString();
  }

  String _displayPath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    if (parts.length <= 2) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  /// Read-off axis attribution: per-axis contribution of this
  /// candidate relative to the seeds. Each axis is computed from a
  /// different signal already cached on the engine — no extra SpMV.
  /// Values are squashed into [0, 1] by heuristic but monotone maps,
  /// so the *dominant* axis is always the one contributing most in
  /// absolute terms.
  MindAxisContribution _axisAttributionFor(
    String candidate,
    Map<String, double> seeds, {
    double? engramBoost,
  }) {
    // F0: activity mass, normalised against the max touch in the repo.
    final maxTouches = engine.stats.touches.values.fold<int>(
        0, (a, b) => b > a ? b : a);
    final f0 = maxTouches <= 0
        ? 0.0
        : ((engine.stats.touches[candidate] ?? 0) / maxTouches).clamp(0.0, 1.0).toDouble();

    // CC: best jaccard coupling to any seed.
    var cc = 0.0;
    for (final seed in seeds.keys) {
      final row = engine.stats.coupling.jaccardEntriesOf(seed);
      for (final e in row) {
        if (e.key == candidate && e.value > cc) cc = e.value;
      }
    }
    cc = cc.clamp(0.0, 1.0).toDouble();

    // M: structural proximity — shared parent directory depth with any
    // seed, normalised against the candidate's own depth.
    var m = 0.0;
    final candParts = candidate.replaceAll('\\', '/').split('/');
    for (final seed in seeds.keys) {
      final seedParts = seed.replaceAll('\\', '/').split('/');
      var shared = 0;
      final lim = math.min(candParts.length, seedParts.length) - 1;
      for (var i = 0; i < lim; i++) {
        if (candParts[i] == seedParts[i]) {
          shared++;
        } else {
          break;
        }
      }
      final depth = (candParts.length - 1).clamp(1, 100);
      final frac = shared / depth;
      if (frac > m) m = frac;
    }

    // Ab: symbol-edge overlap with any seed.
    var ab = 0.0;
    final candSyms = engine.symbolEdges[candidate];
    if (candSyms != null) {
      for (final seed in seeds.keys) {
        final seedSyms = engine.symbolEdges[seed];
        if (seedSyms == null) continue;
        var shared = 0.0;
        var denom = 0.0;
        candSyms.forEach((sym, w) {
          denom += w;
          final sw = seedSyms[sym];
          if (sw != null) shared += math.min(w, sw);
        });
        if (denom > 0) {
          final frac = shared / denom;
          if (frac > ab) ab = frac;
        }
      }
    }

    // EN: engram cosine similarity (0 when null, otherwise clamped to
    // [0, 1] — negative cosines collapse to 0).
    final en = engramBoost == null
        ? 0.0
        : engramBoost.clamp(0.0, 1.0).toDouble();

    return MindAxisContribution(f0: f0, cc: cc, m: m, ab: ab, en: en);
  }
}

// ───────────────────────────────────────────────────────────────────
// MindSession — stateful multi-turn reasoning
// ───────────────────────────────────────────────────────────────────

/// One turn in a session: the query, what came back, and whether the
/// user accepted a candidate (null if they haven't answered yet).
class MindTurn {
  final MindQuery query;
  final MindResponse response;
  final String? acceptedPath;
  const MindTurn({
    required this.query,
    required this.response,
    this.acceptedPath,
  });
}

/// Stateful multi-turn wrapper over [LogosMind]. Tracks history,
/// chains queries via [drill], cross-checks ask against dream via
/// [consensus], and biases future rankings via [reinforce].
///
/// Unlike [LogosMind] (which is pure), [MindSession] carries mutable
/// state: the turn history and an axis-weight bias that accumulates
/// from user feedback. Use it when you want the engine to get better
/// per user per session; use bare [LogosMind] for one-shot inference.
class MindSession {
  final LogosMind mind;
  final List<MindTurn> _history = [];
  MindAxisContribution _axisBias = MindAxisContribution.uniform;

  MindSession({required this.mind});

  /// Read-only view of turns in chronological order.
  List<MindTurn> get history => List.unmodifiable(_history);

  /// Current axis-bias vector. Updated by [reinforce] each time the
  /// user accepts a candidate.
  MindAxisContribution get axisBias => _axisBias;

  /// Ask a query; re-rank the response against the session's current
  /// axis bias; append the turn to history.
  MindResponse ask(MindQuery query, {double temperature = 1.0, int topN = 10}) {
    final base = mind.ask(query, temperature: temperature, topN: topN);
    final reranked = _applyAxisBias(base.candidates);
    final response = base.copyWith(candidates: reranked);
    _history.add(MindTurn(query: query, response: response));
    return response;
  }

  /// Run ask + dream in parallel and fuse them into a single response
  /// whose `confidence` reflects agreement between the two paths.
  /// Dreams are conditioned on the query's seeds; the overlap between
  /// the ask top-K and dream top-K contributors defines confidence.
  MindResponse consensus(
    MindQuery query, {
    double temperature = 1.0,
    int topN = 10,
    int dreamSamples = 6,
    math.Random? rng,
    double mass = 0.5,
  }) {
    final base = mind.ask(query, temperature: temperature, topN: topN);
    if (base.candidates.isEmpty) {
      final response = base.copyWith(confidence: 0.0);
      _history.add(MindTurn(query: query, response: response));
      return response;
    }
    final dreams = mind.dream(
      query,
      samples: dreamSamples,
      rng: rng,
      mass: mass,
      topN: topN,
    );
    final askSet = base.candidates.map((c) => c.path).toSet();
    // Count how often each ask-path shows up in the dream tops.
    final dreamHits = <String, int>{};
    for (final d in dreams) {
      for (final c in d.top) {
        dreamHits[c.path] = (dreamHits[c.path] ?? 0) + 1;
      }
    }
    var agreed = 0;
    for (final p in askSet) {
      if ((dreamHits[p] ?? 0) >= (dreamSamples / 2).ceil()) agreed++;
    }
    final confidence = askSet.isEmpty ? 0.0 : agreed / askSet.length;
    final reranked = _applyAxisBias(base.candidates);
    final response = base.copyWith(
      candidates: reranked,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
    );
    _history.add(MindTurn(query: query, response: response));
    return response;
  }

  /// Chain a query: take the top candidate of the previous response
  /// (or an explicit path) and make IT the new seed. Appends a new
  /// turn to history. Returns the new response.
  MindResponse drill({
    String? path,
    double temperature = 1.0,
    int topN = 10,
  }) {
    final seed = path ?? _history.lastOrNull?.response.topPath;
    if (seed == null) {
      throw StateError(
          'drill() requires either a path arg or a previous response with '
          'at least one candidate');
    }
    return ask(MindQuery.path(seed), temperature: temperature, topN: topN);
  }

  /// Reinforce the user's preference: find the most recent turn where
  /// [acceptedPath] appeared as a candidate, nudge the session's axis
  /// bias toward that candidate's axis profile.
  ///
  /// The nudge is a linear interpolation by `strength` (default 0.2).
  /// Over multiple accepts, the bias drifts toward the axis mixture
  /// the user consistently prefers — without changing the engine.
  void reinforce(String acceptedPath, {double strength = 0.2}) {
    for (final turn in _history.reversed) {
      MindCandidate? cand;
      for (final c in turn.response.candidates) {
        if (c.path == acceptedPath) {
          cand = c;
          break;
        }
      }
      if (cand == null) continue;
      if (cand.axis != null) {
        _axisBias = _axisBias.lerp(cand.axis!, strength);
      }
      // Also mark the turn as accepted.
      final idx = _history.indexOf(turn);
      if (idx >= 0) {
        _history[idx] = MindTurn(
          query: turn.query,
          response: turn.response,
          acceptedPath: acceptedPath,
        );
      }
      return;
    }
  }

  /// Drop all state — history, axis bias, etc. Leaves the wrapped
  /// [LogosMind] untouched.
  void forget() {
    _history.clear();
    _axisBias = MindAxisContribution.uniform;
  }

  List<MindCandidate> _applyAxisBias(List<MindCandidate> raw) {
    if (raw.isEmpty) return raw;
    // Small additive boost proportional to axis·bias.
    final boosted = <MindCandidate>[
      for (final c in raw)
        MindCandidate(
          path: c.path,
          score: c.score *
              (1.0 +
                  (c.axis == null
                      ? 0.0
                      : _axisBias.dot(c.axis!) * 0.5)),
          gravity: c.gravity,
          reach: c.reach,
          engramBoost: c.engramBoost,
          axis: c.axis,
          grounding: c.grounding,
        ),
    ];
    boosted.sort((a, b) => b.score.compareTo(a.score));
    return boosted;
  }
}
