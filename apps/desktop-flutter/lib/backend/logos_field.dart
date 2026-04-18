// LogosField — the unified field type.
//
// A real-valued field `ρ(v, k)` on the (file × commit) space together
// with its hypercomplex dual `Ŝ(j, ω)`. This is the single abstraction
// every generative / Fourier / diffusion primitive in the engine acts
// on. Everywhere else in the codebase we were passing raw `Float64List`
// blobs whose meaning was implicit; here we give those blobs a name, a
// shape, and a full vocabulary of physics-grounded operations.
//
// No new math: every operation delegates to an existing primitive
// (`applyDualSpaceProfile`, `sampleGaussianFreeField`,
// `sampleConditionalGFF`, `forwardLogosTransform`, etc.). LogosField is
// a type-level unification, not a theoretical one.
//
// Design notes:
//
// * **Immutability.** Every operation returns a new LogosField. The
//   wrapped primal buffer is owned by the instance; callers don't get
//   a reference that can mutate internal state.
// * **Laziness.** `primal` is always resident. `dualReal` / `dualImag`
//   are computed on first access and cached. Operations that live
//   more naturally in the dual (filter, bandPass) compute the dual
//   once, operate, inverse-transform, and attach both to the result.
// * **Pure-spatial vs spacetime.** `commitCount = 1` gives a spatial-
//   only field (a focus distribution). `commitCount > 1` gives a full
//   (file × commit) slab. The same operations work for both.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';
import 'logos_git.dart';
import 'logos_git_probe.dart';
import 'logos_hypercomplex.dart';

/// Character classification returned by [LogosField.character]. Values
/// are ordered roughly by "how structurally disruptive" — a concise
/// label the UI can show as a chip.
enum LogosFieldCharacter {
  /// No meaningful energy in either axis. Trivial or empty field.
  silent,

  /// Low-frequency dominated in both axes. Broad, non-specific motion
  /// across many files and many commits. "Maintenance" in a repo.
  diffuse,

  /// Dominated by low spatial / high temporal frequencies. Many
  /// short-lived changes on a small mode group. "Polish / episodic".
  episodic,

  /// Dominated by high spatial / low temporal frequencies. Sharp moves
  /// across many modes at a single commit slot. "Refactor / structural".
  structural,

  /// Both axes carry significant energy — large-scale reshape that
  /// propagates through time. "Architectural break".
  architectural,
}

extension LogosFieldCharacterLabel on LogosFieldCharacter {
  /// Short human label for UI chips. Calm and lowercase — matches the
  /// petrichor minimalism of the rest of the app.
  String get label {
    switch (this) {
      case LogosFieldCharacter.silent:
        return 'silent';
      case LogosFieldCharacter.diffuse:
        return 'maintenance';
      case LogosFieldCharacter.episodic:
        return 'episodic polish';
      case LogosFieldCharacter.structural:
        return 'structural refactor';
      case LogosFieldCharacter.architectural:
        return 'architectural';
    }
  }
}

/// Aggregate energy split of a field's hypercomplex dual.
class LogosFieldEnergy {
  /// Energy weighted by spatial eigenvalue λⱼ. Large when mass sits on
  /// high-λ (short-wavelength, locally-varying) modes.
  final double spatial;

  /// Energy weighted by temporal eigenvalue νω = 1 − cos(2π·ω/N).
  /// Large when mass oscillates fast along the commit axis.
  final double temporal;

  /// Total dual energy Σ|Ŝ|². Parseval-equal to the primal energy.
  final double total;

  const LogosFieldEnergy({
    required this.spatial,
    required this.temporal,
    required this.total,
  });

  double get spatialFraction =>
      total <= 1e-300 ? 0.0 : spatial / (spatial + temporal + 1e-300);

  double get temporalFraction =>
      total <= 1e-300 ? 0.0 : temporal / (spatial + temporal + 1e-300);
}

/// Centroid — the (j, ω) pair with maximum magnitude in the dual.
/// Returned by [LogosField.centroid].
class LogosFieldCentroid {
  final int j;
  final int omega;
  final double magnitude;
  const LogosFieldCentroid({
    required this.j,
    required this.omega,
    required this.magnitude,
  });
}

/// A real-valued field `ρ(v, k)` on (files × commits) with its
/// hypercomplex dual on tap. Every generative / Fourier / diffusion
/// primitive in the engine can be applied to this type.
class LogosField {
  /// The spectral basis whose modes define the spatial axis.
  final SpectralBasis basis;

  /// Number of commit slots along the temporal axis. `1` = pure
  /// spatial field (focus distribution). `>= 2` = spacetime slab.
  final int commitCount;

  /// Primal storage, commit-major: `[kc * n + v]`. Always resident.
  final Float64List _primal;

  /// Lazy dual: `[j * commitCount + ω]`, real part. Null until first
  /// access through [dualReal].
  Float64List? _dualReal;
  Float64List? _dualImag;

  LogosField._({
    required this.basis,
    required this.commitCount,
    required Float64List primal,
    Float64List? dualReal,
    Float64List? dualImag,
  })  : _primal = primal,
        _dualReal = dualReal,
        _dualImag = dualImag {
    if (primal.length != basis.n * commitCount) {
      throw ArgumentError(
          'LogosField: primal length ${primal.length} != n*N '
          '(${basis.n}·$commitCount)');
    }
  }

  // ── Constructors ────────────────────────────────────────────────────

  /// Zero field of the requested shape. `O(n·commitCount)` allocation.
  factory LogosField.zero(SpectralBasis basis, int commitCount) {
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: Float64List(basis.n * commitCount),
    );
  }

  /// Wrap a raw primal buffer. The buffer is **adopted** (not copied);
  /// callers must not mutate it afterwards. Use [LogosField.copyFromPrimal]
  /// when you need a defensive copy.
  factory LogosField.fromPrimal({
    required SpectralBasis basis,
    required Float64List primal,
    required int commitCount,
  }) {
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: primal,
    );
  }

  /// Defensive-copy variant of [LogosField.fromPrimal].
  factory LogosField.copyFromPrimal({
    required SpectralBasis basis,
    required Float64List primal,
    required int commitCount,
  }) {
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: Float64List.fromList(primal),
    );
  }

  /// Build a field from its hypercomplex dual. Inverse-transforms
  /// immediately so `primal` is populated; dual buffers are adopted.
  factory LogosField.fromDual({
    required SpectralBasis basis,
    required Float64List real,
    required Float64List imag,
    required int commitCount,
  }) {
    final primal = inverseLogosTransform(
      basis: basis,
      realJOmega: real,
      imagJOmega: imag,
      commitCount: commitCount,
    );
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: primal,
      dualReal: real,
      dualImag: imag,
    );
  }

  /// Sample a fresh field from the Gaussian Free Field prior. For
  /// `commitCount == 1` uses the spatial GFF; for `commitCount > 1`
  /// uses the joint tensor-product GFF on `L_V ⊗ I + I ⊗ L_T`.
  factory LogosField.gff({
    required SpectralBasis basis,
    int commitCount = 1,
    required math.Random rng,
    double mass = 0.5,
  }) {
    if (commitCount <= 1) {
      final spatial =
          basis.sampleGaussianFreeField(rng: rng, mass: mass);
      return LogosField._(
        basis: basis,
        commitCount: 1,
        primal: spatial,
      );
    }
    final slab = sampleJointGaussianFreeField(
      basis: basis,
      commitCount: commitCount,
      rng: rng,
      mass: mass,
    );
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: slab,
    );
  }

  /// Sample a spatial field conditional on a set of observed node
  /// values (Kriging). Returns a `commitCount == 1` field.
  factory LogosField.conditional({
    required SpectralBasis basis,
    required List<int> observedNodes,
    required Float64List observedValues,
    required math.Random rng,
    double mass = 0.5,
  }) {
    final spatial = basis.sampleConditionalGFF(
      observedNodes: observedNodes,
      observedValues: observedValues,
      rng: rng,
      mass: mass,
    );
    return LogosField._(
      basis: basis,
      commitCount: 1,
      primal: spatial,
    );
  }

  /// Build a spatial field from a [DiffProbe]'s source weights — the
  /// bridge between the git-side probe builder and the generative
  /// primitives.
  ///
  /// `commitCount == 1` (spatial only) by default; pass a larger value
  /// to broadcast the probe into the first time slot, leaving the rest
  /// zero.
  factory LogosField.fromDiffProbe({
    required LogosGit engine,
    required DiffProbe probe,
    int commitCount = 1,
  }) {
    final basis = engine.spectralBasis();
    if (basis == null) {
      throw StateError(
          'LogosField.fromDiffProbe: engine has no spectral basis '
          '(graph too small or not yet materialised)');
    }
    final primal = Float64List(basis.n * commitCount);
    probe.sourceWeights.forEach((path, w) {
      final id = engine.pathToId[path];
      if (id == null || !w.isFinite || w <= 0) return;
      // Place mass in commit slot 0.
      primal[0 * basis.n + id] = w;
    });
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: primal,
    );
  }

  // ── Getters ─────────────────────────────────────────────────────────

  /// Number of graph nodes (files).
  int get n => basis.n;

  /// Number of retained modes (the spectral basis truncation).
  int get k => basis.k;

  /// Raw primal buffer. Do not mutate.
  Float64List get primal => _primal;

  /// Real part of the dual `Ŝ(j, ω)`. Computed on first access.
  Float64List get dualReal {
    _ensureDual();
    return _dualReal!;
  }

  /// Imaginary part of the dual `Ŝ(j, ω)`. Computed on first access.
  Float64List get dualImag {
    _ensureDual();
    return _dualImag!;
  }

  void _ensureDual() {
    if (_dualReal != null && _dualImag != null) return;
    final d = forwardLogosTransform(
      basis: basis,
      fieldCommitMajor: _primal,
      commitCount: commitCount,
    );
    _dualReal = d.real;
    _dualImag = d.imaginary;
  }

  // ── Spatial/temporal operations ─────────────────────────────────────

  /// Apply heat-kernel evolution in the spatial axis for time [t].
  /// Profile: `e^{−t·λⱼ}` per mode, identity in ω.
  LogosField diffuse(double t) {
    final profile = Float64List(k);
    for (var j = 0; j < k; j++) {
      profile[j] = math.exp(-t * basis.eigenvalues[j]);
    }
    final out = applyDualSpaceProfile(
      basis: basis,
      fieldCommitMajor: _primal,
      commitCount: commitCount,
      jProfile: profile,
    );
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Apply Schrödinger evolution (Wick rotation of heat) and return the
  /// Born-rule probability `|ψ(v, k, t)|²` per node. Real-valued by
  /// construction; **mass-conserving**: `Σ |ψ|²(t) = Σ ρ²(0)` at every
  /// commit slot (Parseval on unitary operators).
  ///
  /// Applied per commit slot — each slot is an independent spatial ρ
  /// which evolves unitarily on its own, and we read off the
  /// probability density at time `t`. Use this when you want a
  /// quantum-flavoured observable; for ordinary heat-flow damping use
  /// [diffuse].
  LogosField unitary(double t) {
    final nNodes = basis.n;
    final out = Float64List(nNodes * commitCount);
    final slotBuf = Float64List(nNodes);
    for (var w = 0; w < commitCount; w++) {
      for (var v = 0; v < nNodes; v++) {
        slotBuf[v] = _primal[w * nNodes + v];
      }
      final prob = basis.quantumProbability(slotBuf, t);
      for (var v = 0; v < nNodes; v++) {
        out[w * nNodes + v] = prob[v];
      }
    }
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Apply an arbitrary dual-space filter. `jProfile[j]` multiplies
  /// all (j, ω) cells at that j; `omegaProfile[ω]` multiplies all
  /// (j, ω) cells at that ω. Either can be null (identity on that axis).
  LogosField filter({Float64List? jProfile, Float64List? omegaProfile}) {
    final out = applyDualSpaceProfile(
      basis: basis,
      fieldCommitMajor: _primal,
      commitCount: commitCount,
      jProfile: jProfile,
      omegaProfile: omegaProfile,
    );
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Band-pass filter by index range. Keeps modes `jLo ≤ j < jHi` and
  /// frequencies `omegaLo ≤ ω < omegaHi`; zeros everything else.
  LogosField bandPass({
    int jLo = 0,
    int? jHi,
    int omegaLo = 0,
    int? omegaHi,
  }) {
    final jUpper = jHi ?? k;
    final omegaUpper = omegaHi ?? commitCount;
    final jp = Float64List(k);
    for (var j = jLo; j < jUpper && j < k; j++) jp[j] = 1.0;
    final op = Float64List(commitCount);
    for (var w = omegaLo; w < omegaUpper && w < commitCount; w++) op[w] = 1.0;
    return filter(jProfile: jp, omegaProfile: op);
  }

  /// Scale every primal value by [factor]. Linear on the dual too.
  LogosField scale(double factor) {
    final out = Float64List(_primal.length);
    for (var i = 0; i < _primal.length; i++) {
      out[i] = _primal[i] * factor;
    }
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Pointwise superposition: `(self + other)(v, k) = self(v, k) + other(v, k)`.
  /// Must match in basis identity and commitCount.
  LogosField operator +(LogosField other) {
    _assertCompatible(other);
    final out = Float64List(_primal.length);
    for (var i = 0; i < _primal.length; i++) {
      out[i] = _primal[i] + other._primal[i];
    }
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Pointwise difference.
  LogosField operator -(LogosField other) {
    _assertCompatible(other);
    final out = Float64List(_primal.length);
    for (var i = 0; i < _primal.length; i++) {
      out[i] = _primal[i] - other._primal[i];
    }
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  /// Linear interpolation between two fields: `(1−t)·self + t·other`.
  /// `t` is clamped to [0, 1].
  LogosField interpolate(LogosField other, double t) {
    _assertCompatible(other);
    final c = t.clamp(0.0, 1.0).toDouble();
    final out = Float64List(_primal.length);
    for (var i = 0; i < _primal.length; i++) {
      out[i] = (1.0 - c) * _primal[i] + c * other._primal[i];
    }
    return LogosField._(
      basis: basis,
      commitCount: commitCount,
      primal: out,
    );
  }

  void _assertCompatible(LogosField other) {
    if (!identical(other.basis, basis) || other.commitCount != commitCount) {
      throw ArgumentError(
          'LogosField shape mismatch: basis identical=${identical(other.basis, basis)} '
          'commitCount ${other.commitCount} vs $commitCount');
    }
  }

  // ── Analysis ────────────────────────────────────────────────────────

  /// Split the dual energy by spatial vs temporal frequency weighting.
  /// Spatial weight = `λⱼ`; temporal weight = `1 − cos(2π ω / N)`.
  /// Total = Parseval sum of `|Ŝ|²`.
  LogosFieldEnergy get energy {
    _ensureDual();
    var spatial = 0.0;
    var temporal = 0.0;
    var total = 0.0;
    for (var j = 0; j < k; j++) {
      final lam = basis.eigenvalues[j];
      for (var w = 0; w < commitCount; w++) {
        final idx = j * commitCount + w;
        final mag2 = _dualReal![idx] * _dualReal![idx] +
            _dualImag![idx] * _dualImag![idx];
        total += mag2;
        spatial += lam * mag2;
        final nu = commitCount <= 1
            ? 0.0
            : 1.0 - math.cos(2.0 * math.pi * w / commitCount);
        temporal += nu * mag2;
      }
    }
    return LogosFieldEnergy(
      spatial: spatial,
      temporal: temporal,
      total: total,
    );
  }

  /// Dominant (j, ω) in the dual — the single bin carrying the most
  /// magnitude. Useful as a short fingerprint.
  LogosFieldCentroid get centroid {
    _ensureDual();
    var bestJ = 0;
    var bestOmega = 0;
    var bestMag2 = -1.0;
    for (var j = 0; j < k; j++) {
      for (var w = 0; w < commitCount; w++) {
        final idx = j * commitCount + w;
        final mag2 = _dualReal![idx] * _dualReal![idx] +
            _dualImag![idx] * _dualImag![idx];
        if (mag2 > bestMag2) {
          bestMag2 = mag2;
          bestJ = j;
          bestOmega = w;
        }
      }
    }
    return LogosFieldCentroid(
      j: bestJ,
      omega: bestOmega,
      magnitude: math.sqrt(bestMag2 < 0 ? 0 : bestMag2),
    );
  }

  /// One-shot character classification based on the spatial/temporal
  /// energy split. Thresholds are heuristic but stable.
  LogosFieldCharacter get character {
    final e = energy;
    if (e.total <= 1e-12) return LogosFieldCharacter.silent;
    final denom = e.spatial + e.temporal;
    if (denom <= 1e-12) return LogosFieldCharacter.diffuse;
    final sFrac = e.spatial / denom;
    final tFrac = e.temporal / denom;
    // High in both = architectural break.
    if (sFrac > 0.35 && tFrac > 0.35 && e.total > 1e-6) {
      return LogosFieldCharacter.architectural;
    }
    if (sFrac > 0.65) return LogosFieldCharacter.structural;
    if (tFrac > 0.65) return LogosFieldCharacter.episodic;
    return LogosFieldCharacter.diffuse;
  }

  /// Cosine similarity between the amplitude spectra of two fields'
  /// duals. `+1` = identical dual magnitudes (same "shape of mass");
  /// `0` = orthogonal; negative values are impossible for magnitudes
  /// but we clamp just in case.
  ///
  /// Used to check "do these two fields live in the same mode group?"
  /// — e.g. two PRs that will merge cleanly have low alignment
  /// (orthogonal modes); two PRs competing for the same structure
  /// have high alignment.
  double alignmentWith(LogosField other) {
    _assertCompatible(other);
    _ensureDual();
    other._ensureDual();
    var dot = 0.0;
    var normSelf = 0.0;
    var normOther = 0.0;
    for (var i = 0; i < _dualReal!.length; i++) {
      final mSelf = math.sqrt(_dualReal![i] * _dualReal![i] +
          _dualImag![i] * _dualImag![i]);
      final mOther = math.sqrt(other._dualReal![i] * other._dualReal![i] +
          other._dualImag![i] * other._dualImag![i]);
      dot += mSelf * mOther;
      normSelf += mSelf * mSelf;
      normOther += mOther * mOther;
    }
    if (normSelf <= 1e-300 || normOther <= 1e-300) return 0.0;
    return (dot / (math.sqrt(normSelf) * math.sqrt(normOther)))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// KL-like divergence of the self's dual-magnitude distribution vs a
  /// reference prior. Returns a non-negative scalar — larger means
  /// "this field lives in modes the prior considers rare."
  ///
  /// Both fields are normalised by total dual energy; regions of
  /// near-zero prior mass contribute nothing (we stay numerically
  /// stable instead of diverging).
  double anomalyScore(LogosField prior) {
    _assertCompatible(prior);
    _ensureDual();
    prior._ensureDual();
    var pTotal = 0.0;
    var qTotal = 0.0;
    for (var i = 0; i < _dualReal!.length; i++) {
      pTotal += _dualReal![i] * _dualReal![i] + _dualImag![i] * _dualImag![i];
      qTotal += prior._dualReal![i] * prior._dualReal![i] +
          prior._dualImag![i] * prior._dualImag![i];
    }
    if (pTotal <= 1e-300 || qTotal <= 1e-300) return 0.0;
    var kl = 0.0;
    for (var i = 0; i < _dualReal!.length; i++) {
      final pMag = _dualReal![i] * _dualReal![i] + _dualImag![i] * _dualImag![i];
      final qMag = prior._dualReal![i] * prior._dualReal![i] +
          prior._dualImag![i] * prior._dualImag![i];
      final p = pMag / pTotal;
      final q = qMag / qTotal;
      if (p > 1e-300 && q > 1e-300) kl += p * math.log(p / q);
    }
    return kl < 0 ? 0.0 : kl;
  }

  /// Top files by absolute primal mass (summed across commit slots).
  /// Useful for UI surfaces that need to name the subjects of a field.
  List<({String path, double mass})> topFiles({int topN = 5}) {
    // Sum |primal| per node across all commit slots.
    final totals = Float64List(n);
    for (var w = 0; w < commitCount; w++) {
      for (var v = 0; v < n; v++) {
        totals[v] += _primal[w * n + v].abs();
      }
    }
    final indexed = <({int id, double mass})>[
      for (var v = 0; v < n; v++) (id: v, mass: totals[v]),
    ];
    indexed.sort((a, b) => b.mass.compareTo(a.mass));
    final take = math.min(topN, indexed.length);
    // We can't look up paths here without the engine — caller supplies
    // that. Instead we return node ids + mass; a convenience helper
    // that takes the engine lives in the git bridge above this file.
    return [
      for (var i = 0; i < take; i++)
        (path: 'node:${indexed[i].id}', mass: indexed[i].mass),
    ];
  }

  /// Version of [topFiles] that resolves node ids to paths using an
  /// engine. Convenience for the git-client side.
  List<({String path, double mass})> topPathsViaEngine(
    LogosGit engine, {
    int topN = 5,
  }) {
    final totals = Float64List(n);
    for (var w = 0; w < commitCount; w++) {
      for (var v = 0; v < n; v++) {
        totals[v] += _primal[w * n + v].abs();
      }
    }
    final indexed = <({int id, double mass})>[
      for (var v = 0; v < n; v++) (id: v, mass: totals[v]),
    ];
    indexed.sort((a, b) => b.mass.compareTo(a.mass));
    final take = math.min(topN, indexed.length);
    final paths = engine.nodePaths;
    return [
      for (var i = 0; i < take; i++)
        (path: paths[indexed[i].id], mass: indexed[i].mass),
    ];
  }
}
