// LOGOS HYPERCOMPLEX — the forward & inverse 2-axis Fourier transform
// that unifies everything this engine computes.
//
// A Logos observable is any scalar field S(v, k) where v ∈ V is a
// node (file) and k ∈ {0, …, N−1} is a commit index. Its
// hypercomplex dual is:
//
//     Ŝ(j, ω) = (1/√(nN)) · Σ_{v,k} u_j(v) · S(v, k) · e^{−2πi·ωk/N}
//
//     S(v, k) = (1/√(nN)) · Σ_{j,ω} u_j(v) · Ŝ(j, ω) · e^{+2πi·ωk/N}
//
// The forward composes the graph Fourier transform [SpectralBasis.project]
// with the classical DFT over the commit axis. Every operator in the
// engine is a scalar profile in (j, ω) dual space:
//
//   heat(t)        ↔  e^{−t·λ_j}              (j only)
//   Schrödinger(t) ↔  e^{−i·t·λ_j}            (j only)
//   fractional(α)  ↔  e^{−t·λ_j^α}            (j only)
//   wave cosine    ↔  cos(t·√λ_j)             (j only)
//   resolvent(z)   ↔  1/(λ_j − z)             (j only)
//   band [a, b]    ↔  𝟙[a ≤ λ_j ≤ b]          (j only)
//   deconvolve(t)  ↔  e^{+t·λ_j} · 𝟙[λ_j ≤ Λ] (j only, regularised)
//   temporal band  ↔  𝟙[ω_a ≤ ω ≤ ω_b]        (ω only)
//
// Non-commuting operators (outside the abelian ring) act on S
// directly, not through scalar profiles:
//
//   groverAmplify    — oracle × uniform-reflection rotation in
//                      node×mode plane
//   ricciFlowStep    — motion on the base manifold of graph metrics
//   OT transform     — permutation on the k-axis domain itself
//
// Everything else is Hadamard pointwise multiplication in the dual,
// which is why the operator ring is abelian, functional calculus
// closes under exp/log/sqrt, and composition is O(k) instead of
// O(k^2).

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// Real-to-complex unitary forward DFT `X[k] = (1/√N) · Σⱼ x[j] · e^{-2πi·k·j/N}`.
/// Returned as parallel `(real, imaginary)` Float64Lists of length
/// `curve.length`.
///
/// Non-finite inputs are treated as zero so the transform is safe on
/// curves with sparse NaN entries (common when a trajectory has some
/// points with missing file spectra). Satisfies Parseval: `‖x‖² = ‖X‖²`.
///
/// Cost: O(N²). Fine for N up to a few thousand. Callers wanting
/// FFT speeds on long histories can plug in an external FFT; the
/// interface is stable.
///
/// This is THE unifying DFT in the engine — used both by
/// [SpectralTrajectory.dftOfCurve] (single-axis use) and by
/// [forwardLogosTransform]'s temporal stage (2-axis composition).
({Float64List real, Float64List imaginary}) realDftForward(
  List<double> curve,
) {
  final n = curve.length;
  final re = Float64List(n);
  final im = Float64List(n);
  if (n == 0) return (real: re, imaginary: im);
  final invSqrtN = 1.0 / math.sqrt(n);
  final clean = Float64List(n);
  for (var j = 0; j < n; j++) {
    clean[j] = curve[j].isFinite ? curve[j] : 0.0;
  }
  for (var k = 0; k < n; k++) {
    var sumRe = 0.0;
    var sumIm = 0.0;
    final omega = -2.0 * math.pi * k / n;
    for (var j = 0; j < n; j++) {
      final phase = omega * j;
      sumRe += clean[j] * math.cos(phase);
      sumIm += clean[j] * math.sin(phase);
    }
    re[k] = sumRe * invSqrtN;
    im[k] = sumIm * invSqrtN;
  }
  return (real: re, imaginary: im);
}

/// Complex inverse DFT that, when given the output of
/// [realDftForward] on a real signal, recovers the original signal
/// to `1e-12` precision.
///
///     x[j] = (1/√N) · Σ_k (X_re[k]·cos + X_im[k]·(-sin))·e^{+2πi·k·j/N}
///
/// Returns a real Float64List (the imaginary part is discarded; for
/// signals that came from a real forward transform it's numerical
/// noise at the ~1e-15 level anyway).
Float64List realDftInverse({
  required Float64List real,
  required Float64List imaginary,
}) {
  final n = real.length;
  final out = Float64List(n);
  if (n == 0) return out;
  final invSqrtN = 1.0 / math.sqrt(n);
  for (var j = 0; j < n; j++) {
    var sum = 0.0;
    final phaseBase = 2.0 * math.pi * j / n;
    for (var k = 0; k < n; k++) {
      final phase = phaseBase * k;
      sum += real[k] * math.cos(phase) - imaginary[k] * math.sin(phase);
    }
    out[j] = sum * invSqrtN;
  }
  return out;
}

/// Forward Logos Transform on a row-major `[k, v]` field of shape
/// `commitCount × basis.n`. Returns the dual-space representation as
/// row-major `[j, ω]` pair of Float64Lists (real + imaginary) of
/// shape `basis.k × commitCount`.
///
/// Stage 1: per-commit, project the node-space slice onto the mode
/// basis — an in-place graph Fourier transform.
/// Stage 2: per-mode, DFT the resulting time-series of coefficients.
///
/// The order of the two stages is interchangeable (the two Fourier
/// axes commute), but project-then-DFT is cheaper when the basis is
/// pre-computed and k ≪ n.
({Float64List real, Float64List imaginary}) forwardLogosTransform({
  required SpectralBasis basis,
  required Float64List fieldCommitMajor,
  required int commitCount,
}) {
  final n = basis.n;
  final k = basis.k;
  if (fieldCommitMajor.length != n * commitCount) {
    throw StateError(
        'forwardLogosTransform: field length ${fieldCommitMajor.length} '
        '!= n*N (${n * commitCount})');
  }

  // Stage 1: project each commit onto the mode basis.
  // Result: coefficient matrix of shape [N, k], row-major.
  final coeffs = Float64List(commitCount * k);
  for (var kc = 0; kc < commitCount; kc++) {
    final slice = Float64List.view(
        fieldCommitMajor.buffer,
        fieldCommitMajor.offsetInBytes + kc * n * 8,
        n);
    final c = basis.project(slice);
    for (var j = 0; j < k; j++) {
      coeffs[kc * k + j] = c[j];
    }
  }

  // Stage 2: per-mode, run DFT across the commit axis via the
  // shared [realDftForward] helper. Result laid out [k, N], row-
  // major by j.
  final re = Float64List(k * commitCount);
  final im = Float64List(k * commitCount);
  final modeCurve = Float64List(commitCount);
  for (var j = 0; j < k; j++) {
    for (var kc = 0; kc < commitCount; kc++) {
      modeCurve[kc] = coeffs[kc * k + j];
    }
    final dft = realDftForward(modeCurve);
    for (var omega = 0; omega < commitCount; omega++) {
      re[j * commitCount + omega] = dft.real[omega];
      im[j * commitCount + omega] = dft.imaginary[omega];
    }
  }
  return (real: re, imaginary: im);
}

/// Inverse Logos Transform: recover the real-valued `[k, v]` field
/// from its dual-space representation. Because the forward transform
/// on a real field produces conjugate-symmetric duals, the inverse
/// of such a dual is real to numerical precision.
Float64List inverseLogosTransform({
  required SpectralBasis basis,
  required Float64List realJOmega,
  required Float64List imagJOmega,
  required int commitCount,
}) {
  final n = basis.n;
  final k = basis.k;
  if (realJOmega.length != k * commitCount) {
    throw StateError(
        'inverseLogosTransform: real length ${realJOmega.length} '
        '!= k*N (${k * commitCount})');
  }
  if (imagJOmega.length != k * commitCount) {
    throw StateError(
        'inverseLogosTransform: imaginary length ${imagJOmega.length} '
        '!= k*N (${k * commitCount})');
  }

  // Stage 1': inverse DFT per mode via the shared [realDftInverse]
  // helper — recover the coefficient time-series of each mode.
  final coeffs = Float64List(commitCount * k);
  final reSlice = Float64List(commitCount);
  final imSlice = Float64List(commitCount);
  for (var j = 0; j < k; j++) {
    for (var omega = 0; omega < commitCount; omega++) {
      reSlice[omega] = realJOmega[j * commitCount + omega];
      imSlice[omega] = imagJOmega[j * commitCount + omega];
    }
    final timeSeries =
        realDftInverse(real: reSlice, imaginary: imSlice);
    for (var kc = 0; kc < commitCount; kc++) {
      coeffs[kc * k + j] = timeSeries[kc];
    }
  }

  // Stage 2': per-commit, recombine coefficients into node-space.
  // recombineFromProjection(coeffs, 0.0) is the unweighted inverse GFT.
  final out = Float64List(n * commitCount);
  for (var kc = 0; kc < commitCount; kc++) {
    final cSlice = Float64List(k);
    for (var j = 0; j < k; j++) {
      cSlice[j] = coeffs[kc * k + j];
    }
    final rho = basis.recombineFromProjection(cSlice, 0.0);
    for (var v = 0; v < n; v++) {
      out[kc * n + v] = rho[v];
    }
  }
  return out;
}

/// **Apply a dual-space profile** to a field — the full hypercomplex
/// operator. Forward-transforms the field, multiplies by the (j, ω)
/// profile pointwise, and inverse-transforms back.
///
///     S'(v, k) = InvLogos[ jProfile(j) · ωProfile(ω) · Logos[S](j, ω) ]
///
/// This is the generalisation of [SpectralOperator] from a ring of
/// j-only profiles to a ring of full (j, ω) profiles. Where an
/// existing [SpectralOperator.heat] multiplies by $e^{-t\lambda_j}$
/// (j only), this lets callers **compose a spatial filter with a
/// temporal filter** in one pass — for example, "heat-smooth the
/// spatial axis at t=0.5 while band-passing the commit axis to
/// weekly cycles only."
///
/// Parameters:
/// * [basis] — the spectral basis for the spatial axis.
/// * [fieldCommitMajor] — the input field, row-major `[k, v]` of
///   length `basis.n · commitCount`.
/// * [jProfile] — per-mode scalar weights, length `basis.k`. Pass
///   `null` for no spatial filtering (identity).
/// * [omegaProfile] — per-commit-frequency scalar weights, length
///   `commitCount`. Pass `null` for no temporal filtering.
/// * [commitCount] — the length of the temporal axis.
///
/// Both profiles default to identity (no filtering) when null.
/// Cost: `O(commitCount · basis.n · basis.k + basis.k · commitCount²)`
/// — the forward + inverse LogosTransform is the dominant term.
Float64List applyDualSpaceProfile({
  required SpectralBasis basis,
  required Float64List fieldCommitMajor,
  required int commitCount,
  Float64List? jProfile,
  Float64List? omegaProfile,
}) {
  if (jProfile != null && jProfile.length != basis.k) {
    throw StateError(
        'applyDualSpaceProfile: jProfile length ${jProfile.length} '
        '!= basis.k ${basis.k}');
  }
  if (omegaProfile != null && omegaProfile.length != commitCount) {
    throw StateError(
        'applyDualSpaceProfile: omegaProfile length ${omegaProfile.length} '
        '!= commitCount $commitCount');
  }
  final dual = forwardLogosTransform(
    basis: basis,
    fieldCommitMajor: fieldCommitMajor,
    commitCount: commitCount,
  );
  final re = Float64List.fromList(dual.real);
  final im = Float64List.fromList(dual.imaginary);
  for (var j = 0; j < basis.k; j++) {
    final jw = jProfile?[j] ?? 1.0;
    for (var omega = 0; omega < commitCount; omega++) {
      final ow = omegaProfile?[omega] ?? 1.0;
      final w = jw * ow;
      final idx = j * commitCount + omega;
      re[idx] *= w;
      im[idx] *= w;
    }
  }
  return inverseLogosTransform(
    basis: basis,
    realJOmega: re,
    imagJOmega: im,
    commitCount: commitCount,
  );
}

/// Parseval energy of a real `[k, v]` field — `Σ_{v,k} |S(v, k)|²`.
/// Must equal the energy of its dual under [forwardLogosTransform]
/// (the Parseval identity on both axes simultaneously).
double logosFieldEnergy(Float64List fieldCommitMajor) {
  var s = 0.0;
  for (final v in fieldCommitMajor) {
    s += v * v;
  }
  return s;
}

/// Parseval energy of a dual-space field — `Σ_{j,ω} |Ŝ(j, ω)|²`.
double logosDualEnergy(Float64List real, Float64List imaginary) {
  var s = 0.0;
  for (var i = 0; i < real.length; i++) {
    s += real[i] * real[i] + imaginary[i] * imaginary[i];
  }
  return s;
}

/// Sample a real-valued `[k, v]` field from the **joint Gaussian Free
/// Field** on the tensor-product space (files × commits). This is the
/// full spatiotemporal prior of the Logos engine — a single draw is a
/// plausible "slab of repo state across both axes."
///
/// ## Derivation
///
/// The spatial Laplacian `L_V` has eigenvalues `λⱼ`; the temporal
/// Laplacian on the commit-cycle `C_N` has eigenvalues
/// `νω = 1 − cos(2π·ω/N)`. The joint Laplacian on `V × commits` is
/// the Kronecker sum `L_joint = L_V ⊗ I + I ⊗ L_T`, whose eigenvalues
/// are `μ_{j,ω} = λⱼ + νω` and whose eigenvectors are outer products
/// `u_j(v)·w_ω(k)` (mode × DFT-basis).
///
/// The joint GFF is the Gaussian with covariance `(L_joint + m²I)⁻¹`,
/// and a sample in dual coordinates is
///
///     ξ_{j,ω} ~ N(0, 1 / (λⱼ + νω + m²))      (complex Gaussian)
///
/// We draw in the dual (j, ω) representation respecting conjugate
/// symmetry (Ŝ(j, N−ω) = conj(Ŝ(j, ω))), then apply the inverse Logos
/// transform to get the real-valued field.
///
/// See `docs/architecture/spectral-generative.md` Chapter 5 for the
/// full derivation.
Float64List sampleJointGaussianFreeField({
  required SpectralBasis basis,
  required int commitCount,
  required math.Random rng,
  double mass = 0.0,
}) {
  final k = basis.k;
  final N = commitCount;
  final real = Float64List(k * N);
  final imag = Float64List(k * N);
  if (k == 0 || N == 0) {
    return Float64List(basis.n * N);
  }
  double g() {
    final u1 = rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1.clamp(1e-300, 1.0))) *
        math.cos(2.0 * math.pi * u2);
  }

  final m2 = mass * mass;
  for (var j = 0; j < k; j++) {
    final lam = basis.eigenvalues[j];
    // ω = 0: purely real, variance 1/denom.
    final denom0 = lam + 0.0 + m2;
    if (denom0 > 1e-300) {
      real[j * N + 0] = g() / math.sqrt(denom0);
    }
    // Interior ω: draw complex, mirror to N−ω as conjugate.
    final half = N ~/ 2;
    for (var omega = 1; omega < half; omega++) {
      final nu = 1.0 - math.cos(2.0 * math.pi * omega / N);
      final denom = lam + nu + m2;
      if (denom <= 1e-300) continue;
      // Split variance evenly between real and imag parts so the total
      // per-mode variance matches the GFF formula.
      final s = 1.0 / math.sqrt(2.0 * denom);
      final re = g() * s;
      final im = g() * s;
      real[j * N + omega] = re;
      imag[j * N + omega] = im;
      real[j * N + (N - omega)] = re;
      imag[j * N + (N - omega)] = -im;
    }
    // Nyquist mode (only when N is even): purely real.
    if (N.isEven) {
      final nu = 1.0 - math.cos(math.pi); // = 2
      final denom = lam + nu + m2;
      if (denom > 1e-300) {
        real[j * N + half] = g() / math.sqrt(denom);
      }
    }
  }

  return inverseLogosTransform(
    basis: basis,
    realJOmega: real,
    imagJOmega: imag,
    commitCount: N,
  );
}
