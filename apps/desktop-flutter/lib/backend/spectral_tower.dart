// SPECTRAL TOWER — multi-scale spectral decomposition of the codebase.
//
// Every unit of code, from a chunk up through the full file graph,
// lives in a graph whose normalised Laplacian has an eigenbasis. This
// module composes those eigenbases into a single coherent tower: the
// chunk-level basis restricts to the hunk level, which restricts to
// the file level, and cross-level observables read phase relationships
// between scales.
//
// The guiding structural claim: OG Logos (entropy coder on bytes) and
// our Logos (diffusion on files) are the same math at different levels
// of the same tower. A byte is a vector in Λ*(R⁸); a file is a vector
// in the graph-Laplacian eigenspace. The chain rule `P(byte) = ∏
// P(bit_k | higher bits)` is Möbius inversion on the boolean lattice
// — a graph Fourier transform. Our file-level Fourier transform is
// literally the same operation on a larger, coarser graph. Stacking
// those graphs with explicit restriction/prolongation operators makes
// the tower explicit.
//
// Restriction `R : V_fine → V_coarse` aggregates fine-graph functions
// onto the coarse graph (e.g. a file's function value = weighted sum
// of its hunks'). Prolongation `P : V_coarse → V_fine` (the formal
// adjoint) spreads coarse functions down (e.g. a file's focus value
// broadcast to all of its hunks). Mass-preservation: `Σ R(v) = Σ v`.
//
// Cross-level coherence is the scalar "does the file's internal
// structure (hunk-level Fiedler) agree with its external position
// (file-level community)?". An architectural defect you can measure.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// A single-level membership: a coarse node that owns a list of fine
/// node ids and their per-fine weights. Used by the tower's restriction
/// and prolongation matrices. Weights default to `1/|members|` when
/// omitted so restriction is a mass-preserving average.
class CoarseMembership {
  final int coarseId;
  final List<int> fineIds;
  final List<double> fineWeights;
  const CoarseMembership({
    required this.coarseId,
    required this.fineIds,
    required this.fineWeights,
  });
}

/// A linear operator that maps `V_fine → V_coarse`. Stored sparse by
/// coarse node — each coarse node owns the list of fine nodes it
/// aggregates, with per-fine weights. Applied as
/// `coarse[c] = Σ_{f ∈ members(c)} w[f] · fine[f]`.
/// Its adjoint (prolongation) scatters a coarse value back across its
/// fine members with the same weights.
class RestrictionOperator {
  /// Number of coarse nodes.
  final int nCoarse;

  /// Number of fine nodes.
  final int nFine;

  /// Membership list — one entry per coarse node.
  final List<CoarseMembership> memberships;

  const RestrictionOperator({
    required this.nCoarse,
    required this.nFine,
    required this.memberships,
  });

  /// Restrict a fine-level function to the coarse level.
  /// `coarse[c] = Σ_f w[f] · fine[f]` for f ∈ coarse c's members.
  Float64List restrict(Float64List fine) {
    assert(fine.length == nFine, 'fine vector length must equal nFine');
    final out = Float64List(nCoarse);
    for (final m in memberships) {
      var s = 0.0;
      for (var i = 0; i < m.fineIds.length; i++) {
        s += m.fineWeights[i] * fine[m.fineIds[i]];
      }
      out[m.coarseId] = s;
    }
    return out;
  }

  /// Prolongate a coarse-level function down to the fine level — the
  /// formal adjoint of [restrict]. Distributes each coarse value to
  /// its fine members with the same weights. Not mass-preserving by
  /// default (each fine node receives the full coarse value times its
  /// weight, which scatters mass if weights sum to more than 1).
  Float64List prolongate(Float64List coarse) {
    assert(coarse.length == nCoarse, 'coarse vector length must equal nCoarse');
    final out = Float64List(nFine);
    for (final m in memberships) {
      final cv = coarse[m.coarseId];
      if (cv == 0.0) continue;
      for (var i = 0; i < m.fineIds.length; i++) {
        out[m.fineIds[i]] += m.fineWeights[i] * cv;
      }
    }
    return out;
  }

  /// Build a uniform-weight restriction from a membership map (coarse
  /// node → list of fine node ids). Each member gets weight `1/|members|`
  /// so restriction is a mass-preserving average.
  factory RestrictionOperator.uniform({
    required int nCoarse,
    required int nFine,
    required Map<int, List<int>> membersByCoarse,
  }) {
    final memberships = <CoarseMembership>[];
    for (var c = 0; c < nCoarse; c++) {
      final members = membersByCoarse[c] ?? const <int>[];
      if (members.isEmpty) {
        memberships.add(CoarseMembership(
          coarseId: c,
          fineIds: const [],
          fineWeights: const [],
        ));
        continue;
      }
      final w = 1.0 / members.length;
      memberships.add(CoarseMembership(
        coarseId: c,
        fineIds: List<int>.unmodifiable(members),
        fineWeights: List<double>.filled(members.length, w),
      ));
    }
    return RestrictionOperator(
      nCoarse: nCoarse,
      nFine: nFine,
      memberships: memberships,
    );
  }
}

/// A multi-level spectral decomposition — the "tower" — composing a
/// chain of `SpectralBasis` objects at successive coarsening scales
/// with explicit `RestrictionOperator`s between levels. Enables
/// cross-level queries that read the phase relationship between a
/// fine-level structural feature (e.g. a file's internal hunk-Fiedler
/// split) and a coarse-level positional feature (which file-graph
/// community the file belongs to).
///
/// Conventions: `bases[0]` is the coarsest (file), `bases[levels-1]`
/// is the finest (chunk or byte). `restrict[i]` maps `bases[i+1] →
/// bases[i]` (fine-to-coarse), equivalently prolongate does coarse-to-
/// fine. The user is responsible for supplying consistent memberships
/// — this class only provides the linear-algebra plumbing.
class SpectralTower {
  /// Bases at each level, coarsest first.
  final List<SpectralBasis> bases;

  /// Restriction operators between adjacent levels. `restrictions[i]`
  /// maps `bases[i+1] → bases[i]`. Length = `bases.length - 1`.
  final List<RestrictionOperator> restrictions;

  const SpectralTower({
    required this.bases,
    required this.restrictions,
  });

  /// Number of levels in the tower.
  int get levels => bases.length;

  /// Lift a fine-level function through each restriction up to the
  /// top (coarsest) level, returning the entire lift sequence.
  /// Useful for "watch how this focus aggregates at every scale."
  List<Float64List> liftToTop(Float64List fine) {
    assert(fine.length == bases.last.n, 'fine vector must match finest basis');
    final out = <Float64List>[fine];
    for (var i = restrictions.length - 1; i >= 0; i--) {
      out.insert(0, restrictions[i].restrict(out.first));
    }
    return out;
  }

  /// Project a fine-level function onto every level's spectral basis,
  /// returning a list of coefficient vectors (one per level). The
  /// coefficients at coarse level `i` come from first restricting to
  /// that level and then projecting onto its eigenbasis.
  ///
  /// **Reading**: a multi-scale Fourier transform. Dominant coefficients
  /// at coarse levels mean the focus lives in the codebase's macro
  /// structure; dominant coefficients at fine levels mean the focus
  /// lives in local micro structure. This is the tower's analog of
  /// OG Logos's spectral tower (O2 → Z → E as position → velocity →
  /// trajectory) — same layered decomposition, read top-down instead
  /// of bottom-up.
  List<Float64List> multiscaleProject(Float64List fine) {
    final lifted = liftToTop(fine);
    final out = <Float64List>[];
    for (var i = 0; i < levels; i++) {
      out.add(bases[i].project(lifted[i]));
    }
    return out;
  }

  /// Cross-level coherence between level `coarseIdx` and level
  /// `fineIdx` (coarseIdx < fineIdx), at scale t: the inner product of
  /// the normalised coarse-Fiedler with the normalised aggregated-
  /// fine-Fiedler, each restricted to the coarse graph.
  ///
  /// **Reading**: +1 = the fine level's internal Fiedler split agrees
  /// exactly with the coarse level's positional split (the file's
  /// internal structure says the same thing as its architectural
  /// position). −1 = they disagree (the file is internally organised
  /// against its architectural grain). 0 = orthogonal (the fine and
  /// coarse cleavages are independent). An architectural defect you
  /// can measure without heuristics.
  double crossLevelCoherence({
    required int coarseIdx,
    required int fineIdx,
    double t = 1.0,
  }) {
    assert(coarseIdx < fineIdx, 'coarseIdx must be strictly finer than fineIdx');
    final coarse = bases[coarseIdx];
    final fine = bases[fineIdx];
    if (coarse.k < 2 || fine.k < 2) return 0.0;
    // Coarse Fiedler at t=0 is just u₁.
    final coarseFiedler = coarse.fiedlerVector!;
    // Aggregate the fine Fiedler through the restrictions to coarse
    // space. Each `restrictions[i]` maps `bases[i+1] → bases[i]`, so
    // to lift a vector from `fineIdx` up to `coarseIdx` we apply
    // `restrictions[fineIdx - 1] → restrictions[coarseIdx]` in order.
    // The earlier version started at `restrictions.length - 1` and
    // silently fell through the length-mismatch guard when the fine
    // level wasn't the bottom of the tower — fixed here.
    Float64List lifted = Float64List.fromList(fine.fiedlerVector!);
    for (var i = fineIdx - 1; i >= coarseIdx; i--) {
      lifted = restrictions[i].restrict(lifted);
    }
    if (lifted.length != coarseFiedler.length) return 0.0;
    // Thermal damping at scale t (both sides weighted by e^{−t·λ₁}).
    final damping = coarse.k >= 2
        ? _dampFactor(coarse.eigenvalues[1], t)
        : 1.0;

    var dot = 0.0;
    var nc = 0.0;
    var nf = 0.0;
    for (var i = 0; i < coarseFiedler.length; i++) {
      dot += coarseFiedler[i] * lifted[i];
      nc += coarseFiedler[i] * coarseFiedler[i];
      nf += lifted[i] * lifted[i];
    }
    final denom = _safeSqrt(nc) * _safeSqrt(nf);
    if (denom == 0.0) return 0.0;
    return damping * (dot / denom);
  }

  /// Number of nodes at each level, coarsest first.
  List<int> sizesByLevel() => [for (final b in bases) b.n];
}

double _dampFactor(double lambda, double t) {
  final x = -t * lambda;
  if (x < -40.0) return 0.0;
  return math.exp(x);
}

double _safeSqrt(double x) => x > 0.0 ? math.sqrt(x) : 0.0;
