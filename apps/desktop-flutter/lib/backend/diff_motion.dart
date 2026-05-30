// DIFF MOTION — the diff read as the next operator on the trajectory.
//
// Every commit reshapes the file-coupling graph by adding co-touch
// edges between the files it modifies. The diff IS the next operator
// about to be applied to the graph. Hellmann-Feynman gives a closed-
// form derivative of each eigenvalue with respect to an edge-weight
// perturbation:
//
//     dλⱼ / dw_{ab}  =  (uⱼ[a] − uⱼ[b])²
//
// Summing this over the pairs the diff touches yields the predicted
// **spectral velocity** — the Δλ vector this diff is about to add to
// the trajectory. From there every other reading follows by
// composition with the trajectory primitive:
//
//   continuation   = cos(predicted_tangent, last_actual_tangent)
//   curvature      = acos(continuation)            [0, π]
//   archetype_shift = nearest archetype on (λ + tangent) vs. (λ)
//   regime_risk    = z(|tangent|, trajectory step-distance distribution)
//
// Pure derivation — no knobs, no magic constants. The diff is the
// operator; the motion is what the math says the operator does.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart' show SpectralBasis;
import 'logos_sensitivity.dart' show eigenvalueSensitivity;
import 'logos_spectrogeometry.dart' show spectrogeometryFromBasis;
import 'spectral_trajectory.dart';

/// One-step prediction of the spectrum's motion under the diff. All
/// fields degrade gracefully — NaN / null / empty when the underlying
/// observable can't be computed (no trajectory, no touched paths in
/// the engine, no recent tangent, etc.).
class DiffMotion {
  /// Per-mode predicted eigenvalue shift, length [k]. Empty when no
  /// touched paths resolve into the engine's path table.
  final Float64List predictedTangent;

  /// Norm of [predictedTangent]. Zero when empty.
  final double tangentMagnitude;

  /// Cosine of predicted tangent vs. the trajectory's most recent
  /// actual tangent. Range `[-1, +1]`:
  ///   +1 → diff continues recent motion exactly
  ///   0  → orthogonal (rotation in mode-space)
  ///   −1 → diff fully reverses recent motion
  /// NaN when there's no recent tangent (trajectory too short).
  final double continuation;

  /// Angle between predicted tangent and last actual tangent, in
  /// `[0, π]`. acos(continuation). NaN when [continuation] is NaN.
  final double curvature;

  /// Nearest archetype on the perturbed basis (`λ + tangent`). Null
  /// when the engine couldn't surface a current spectrogeometry.
  final String? predictedArchetype;

  /// True iff [predictedArchetype] differs from the current archetype.
  /// Implies the diff is pushing the repo across an archetype boundary.
  final bool archetypeShift;

  /// Pre-perturbation archetype for the comparison. Null when current
  /// spectrogeometry isn't available.
  final String? currentArchetype;

  /// Distance the diff moves the universality vector through `[0,1]^6`
  /// space (Euclidean). 0 = no archetype-vector motion; ~1 = maximum
  /// possible drift. NaN when the comparison isn't computable.
  final double universalityDrift;

  /// Z-score of [tangentMagnitude] against the trajectory's actual
  /// step-distance distribution. >2 = anomalous step relative to the
  /// repo's recent rhythm; >3 = sharp. NaN when the trajectory has
  /// too few steps to fit a distribution.
  final double regimeRiskZ;

  /// Count of touched paths the engine could resolve to file ids.
  /// Helps the caller calibrate the reading — a tangent built from
  /// 2 mapped files is weaker evidence than one built from 20.
  final int mappedTouchedCount;

  /// Touched paths the engine couldn't map (new files outside its
  /// path table). Surfaced so the synthesis prompt can mention them
  /// honestly — the engine has no spectral reading for them.
  final List<String> unmappedTouched;

  const DiffMotion({
    required this.predictedTangent,
    required this.tangentMagnitude,
    required this.continuation,
    required this.curvature,
    required this.predictedArchetype,
    required this.archetypeShift,
    required this.currentArchetype,
    required this.universalityDrift,
    required this.regimeRiskZ,
    required this.mappedTouchedCount,
    required this.unmappedTouched,
  });

  static final DiffMotion empty = DiffMotion(
    predictedTangent: Float64List(0),
    tangentMagnitude: 0.0,
    continuation: double.nan,
    curvature: double.nan,
    predictedArchetype: null,
    archetypeShift: false,
    currentArchetype: null,
    universalityDrift: double.nan,
    regimeRiskZ: double.nan,
    mappedTouchedCount: 0,
    unmappedTouched: const <String>[],
  );

  bool get isEmpty =>
      predictedTangent.isEmpty && mappedTouchedCount == 0;
}

/// Compute the diff's predicted spectral velocity vector — Δλⱼ for
/// every mode j in the basis. Pure Hellmann-Feynman: each pair of
/// touched files contributes one unit of edge perturbation (matching
/// the trajectory builder's per-commit co-touch convention).
///
/// Returns an empty list when fewer than two touched paths resolve
/// into [pathToId] — a single touched path produces no co-touch
/// edges and no tangent.
Float64List predictDiffTangent({
  required SpectralBasis basis,
  required Map<String, int> pathToId,
  required Iterable<String> touchedPaths,
  double edgeDelta = 1.0,
}) {
  final ids = <int>{};
  for (final path in touchedPaths) {
    final id = pathToId[path];
    if (id != null && id >= 0 && id < basis.n) ids.add(id);
  }
  if (ids.length < 2) return Float64List(0);

  final sortedIds = ids.toList()..sort();
  final tangent = Float64List(basis.k);
  for (var i = 0; i < sortedIds.length; i++) {
    final a = sortedIds[i];
    for (var j = i + 1; j < sortedIds.length; j++) {
      final b = sortedIds[j];
      for (var modeIdx = 0; modeIdx < basis.k; modeIdx++) {
        tangent[modeIdx] +=
            edgeDelta * eigenvalueSensitivity(basis, a, b, modeIdx);
      }
    }
  }
  return tangent;
}

/// Construct a virtual perturbed basis: same eigenvectors, eigenvalues
/// shifted by [tangent]. Eigenvalues clamp to non-negative so the
/// spectrogeometry lenses (zeta, spectral dim) stay well-defined under
/// large perturbations. The k of the returned basis matches the
/// minimum of `basis.k` and `tangent.length`.
SpectralBasis _perturbedBasis(SpectralBasis basis, Float64List tangent) {
  final k = math.min(basis.k, tangent.length);
  final newEigs = Float64List(k);
  for (var j = 0; j < k; j++) {
    final shifted = basis.eigenvalues[j] + tangent[j];
    newEigs[j] = shifted < 0 ? 0.0 : shifted;
  }
  // Take only the first k * n eigenvectors when k differs.
  final vecLen = k * basis.n;
  final newVecs = Float64List(vecLen);
  for (var i = 0; i < vecLen; i++) {
    newVecs[i] = basis.eigenvectors[i];
  }
  return SpectralBasis(
    n: basis.n,
    k: k,
    eigenvalues: newEigs,
    eigenvectors: newVecs,
    nodePaths: basis.nodePaths,
  );
}

double _vectorNorm(Float64List v) {
  var s = 0.0;
  for (var i = 0; i < v.length; i++) {
    s += v[i] * v[i];
  }
  return math.sqrt(s);
}

double _cosineSimilarity(Float64List a, Float64List b) {
  final n = math.min(a.length, b.length);
  if (n == 0) return double.nan;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na <= 1e-300 || nb <= 1e-300) return double.nan;
  return (dot / (math.sqrt(na) * math.sqrt(nb))).clamp(-1.0, 1.0);
}

double _universalityDistance({
  required ({double toBulk, double toCrystalline, double toGoe,
            double toModular, double toPoisson, double toTree}) a,
  required ({double toBulk, double toCrystalline, double toGoe,
            double toModular, double toPoisson, double toTree}) b,
}) {
  var s = 0.0;
  s += (a.toCrystalline - b.toCrystalline) *
      (a.toCrystalline - b.toCrystalline);
  s += (a.toPoisson - b.toPoisson) * (a.toPoisson - b.toPoisson);
  s += (a.toGoe - b.toGoe) * (a.toGoe - b.toGoe);
  s += (a.toTree - b.toTree) * (a.toTree - b.toTree);
  s += (a.toBulk - b.toBulk) * (a.toBulk - b.toBulk);
  s += (a.toModular - b.toModular) * (a.toModular - b.toModular);
  return math.sqrt(s);
}

/// Compute a full [DiffMotion] reading. Composes the per-edge
/// Hellmann-Feynman tangent, the trajectory's most recent actual
/// tangent (for continuation / curvature), the perturbed
/// spectrogeometry (for archetype shift + universality drift), and
/// the trajectory's step-distance distribution (for regime risk).
DiffMotion readDiffMotion({
  required SpectralBasis basis,
  required Map<String, int> pathToId,
  required Iterable<String> touchedPaths,
  required SpectralTrajectory? trajectory,
}) {
  final touchedList = touchedPaths.toList(growable: false);
  final unmapped = <String>[];
  final mapped = <String>[];
  for (final p in touchedList) {
    if (pathToId.containsKey(p)) {
      mapped.add(p);
    } else {
      unmapped.add(p);
    }
  }

  final tangent = predictDiffTangent(
    basis: basis,
    pathToId: pathToId,
    touchedPaths: mapped,
  );
  final magnitude = _vectorNorm(tangent);

  // Continuation + curvature against the trajectory's most recent
  // actual tangent (the last step in the trajectory).
  double continuation = double.nan;
  double curvature = double.nan;
  if (trajectory != null && trajectory.length >= 2 && tangent.isNotEmpty) {
    final recentTangent = trajectory.tangentAt(trajectory.length - 2);
    if (recentTangent.isNotEmpty) {
      continuation = _cosineSimilarity(tangent, recentTangent);
      if (continuation.isFinite) {
        curvature = math.acos(continuation.clamp(-1.0, 1.0));
      }
    }
  }

  // Predicted archetype + universality drift via spectrogeometry of
  // the perturbed basis. Requires k >= 2 for the lenses to resolve.
  String? currentArchetype;
  String? predictedArchetype;
  bool archetypeShift = false;
  double universalityDrift = double.nan;
  if (tangent.isNotEmpty && basis.k >= 2) {
    final currentGeometry = spectrogeometryFromBasis(basis);
    currentArchetype = currentGeometry.universality.nearest.name;
    final perturbed = _perturbedBasis(basis, tangent);
    final perturbedGeometry = spectrogeometryFromBasis(perturbed);
    predictedArchetype = perturbedGeometry.universality.nearest.name;
    archetypeShift = predictedArchetype != currentArchetype;
    universalityDrift = _universalityDistance(
      a: (
        toCrystalline: currentGeometry.universality.toCrystalline,
        toPoisson: currentGeometry.universality.toPoisson,
        toGoe: currentGeometry.universality.toGoe,
        toTree: currentGeometry.universality.toTree,
        toBulk: currentGeometry.universality.toBulk,
        toModular: currentGeometry.universality.toModular,
      ),
      b: (
        toCrystalline: perturbedGeometry.universality.toCrystalline,
        toPoisson: perturbedGeometry.universality.toPoisson,
        toGoe: perturbedGeometry.universality.toGoe,
        toTree: perturbedGeometry.universality.toTree,
        toBulk: perturbedGeometry.universality.toBulk,
        toModular: perturbedGeometry.universality.toModular,
      ),
    );
  }

  // Regime risk: z-score of the tangent's L1-mean against the
  // trajectory's distribution of step distances. The trajectory's
  // eigenvalueStepDistances() returns (sum |Δλⱼ|) / k — an L1-mean —
  // so we score the diff's tangent on the same statistic for a
  // like-for-like comparison.
  double regimeRiskZ = double.nan;
  if (trajectory != null && tangent.isNotEmpty) {
    final stepDistances = trajectory
        .eigenvalueStepDistances()
        .where((d) => d.isFinite)
        .toList(growable: false);
    if (stepDistances.length >= 3) {
      var mean = 0.0;
      for (final d in stepDistances) {
        mean += d;
      }
      mean /= stepDistances.length;
      var variance = 0.0;
      for (final d in stepDistances) {
        final dev = d - mean;
        variance += dev * dev;
      }
      variance /= stepDistances.length;
      final std = math.sqrt(variance);
      var tangentL1 = 0.0;
      for (var j = 0; j < tangent.length; j++) {
        tangentL1 += tangent[j].abs();
      }
      tangentL1 /= tangent.length;
      if (std > 1e-12) {
        regimeRiskZ = (tangentL1 - mean) / std;
      }
    }
  }

  return DiffMotion(
    predictedTangent: tangent,
    tangentMagnitude: magnitude,
    continuation: continuation,
    curvature: curvature,
    predictedArchetype: predictedArchetype,
    archetypeShift: archetypeShift,
    currentArchetype: currentArchetype,
    universalityDrift: universalityDrift,
    regimeRiskZ: regimeRiskZ,
    mappedTouchedCount: mapped.length,
    unmappedTouched: unmapped,
  );
}

/// Label the diff's predicted motion by its angle against the
/// trajectory's recent direction. Partition is the natural π/3
/// trichotomy of the half-circle of possible angles:
///
///   angle <   π/3   →  continuation  (cos > 0.5)
///   π/3  ≤ angle ≤ 2π/3 → rotation      (cos in [-0.5, 0.5])
///   angle >  2π/3   →  reversal      (cos < -0.5)
///
/// Each regime occupies the same arc length (π/3 radians = 60°).
/// The cosine thresholds are the algebraic image of the angle
/// thirds — no editorial knob.
String _motionLabel(double continuation) {
  if (continuation > 0.5) return 'continuation';
  if (continuation < -0.5) return 'reversal';
  return 'rotation';
}

/// Compact one-line summary for the brainstorm prompt. Less detail
/// than the full reading — just the operator's character so the
/// divergent model can seed motion-aware ideas without bloating the
/// cheap call.
///
/// Empty when [motion] carries no signal (no mapped paths, no
/// computed tangent).
String formatDiffMotionCompact(DiffMotion motion) {
  if (motion.isEmpty) return '';
  final parts = <String>[];
  if (motion.continuation.isFinite) {
    parts.add(
        '${_motionLabel(motion.continuation)}=${motion.continuation.toStringAsFixed(2)}');
  }
  if (motion.archetypeShift &&
      motion.currentArchetype != null &&
      motion.predictedArchetype != null) {
    parts.add('${motion.currentArchetype}→${motion.predictedArchetype}');
  } else if (motion.currentArchetype != null) {
    parts.add('archetype=${motion.currentArchetype}');
  }
  if (motion.regimeRiskZ.isFinite) {
    parts.add('regime_z=${motion.regimeRiskZ.toStringAsFixed(1)}');
  }
  if (parts.isEmpty) return '';
  return parts.join(' · ');
}

/// Full motion-reading block for the synthesis prompt. Multi-line,
/// each line a real measurement with documented meaning. Empty when
/// [motion] carries no signal.
String formatDiffMotionBlock(DiffMotion motion) {
  if (motion.isEmpty) return '';
  final buf = StringBuffer();
  buf.writeln('mapped_touched=${motion.mappedTouchedCount}');
  if (motion.continuation.isFinite) {
    buf.writeln('motion=${_motionLabel(motion.continuation)} '
        '(continuation_cos=${motion.continuation.toStringAsFixed(3)}, '
        'curvature_rad=${motion.curvature.toStringAsFixed(3)})');
  }
  buf.writeln(
      'predicted_tangent_norm=${motion.tangentMagnitude.toStringAsFixed(4)}');
  if (motion.currentArchetype != null) {
    if (motion.archetypeShift) {
      buf.writeln(
          'archetype_shift=${motion.currentArchetype}→${motion.predictedArchetype}');
    } else {
      buf.writeln('archetype_stable=${motion.currentArchetype}');
    }
  }
  if (motion.universalityDrift.isFinite) {
    buf.writeln(
        'universality_drift=${motion.universalityDrift.toStringAsFixed(3)}');
  }
  if (motion.regimeRiskZ.isFinite) {
    buf.writeln('regime_risk_z=${motion.regimeRiskZ.toStringAsFixed(2)}');
  }
  if (motion.unmappedTouched.isNotEmpty) {
    // Cap the line; new files outside the engine's path table have no
    // spectral reading, so listing them surfaces the gap honestly.
    final preview = motion.unmappedTouched.take(6).join(', ');
    final suffix = motion.unmappedTouched.length > 6
        ? ' (+${motion.unmappedTouched.length - 6} more)'
        : '';
    buf.writeln('unmapped_new_files=$preview$suffix');
  }
  return buf.toString().trimRight();
}
