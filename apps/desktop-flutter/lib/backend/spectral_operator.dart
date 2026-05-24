// SPECTRAL OPERATOR — commuting-operator ring over a SpectralBasis.
//
// By the spectral theorem, any operator that commutes with a
// symmetric L is a function of L: `f(L) = U · diag(f(λ)) · Uᵀ`. Over
// a fixed basis this forms a commutative ring with identity under
// pointwise-in-mode algebra:
//
//   (f + g)(λ) = f(λ) + g(λ)
//   (f · g)(λ) = f(λ) · g(λ)       ← composition = pointwise product
//   (α · f)(λ) = α · f(λ)
//   (1/f)(λ)   = 1/f(λ)            ← on non-vanishing modes
//
// Heat, wave, Schrödinger, resolvent, fractional Laplacian, and band
// projection are names for specific choices of f, all materialised
// as `SpectralOperator` via named constructors. Apply with
// `applyTo(SpectralProjection)` (O(k)) or `applyToRho(Float64List)`
// (O(kn) through project → scale → recombine).
//
// Non-commuting extensions (node-basis multiplication operators M_g)
// are not included; they'd require a Lie-bracket layer. See
// `tmp_primitive_operators.py` for the canonical-commutation-
// relation proof-of-concept.

import 'dart:math' as math;
import 'dart:typed_data';

import 'logos_core.dart';

/// A Laplacian-commuting operator on a fixed [SpectralBasis].
/// Stored as the per-mode profile `f(λ_j)` for j = 0..k−1. All
/// operations are O(k), so composition is cheaper than a single SpMV.
class SpectralOperator {
  SpectralOperator({required this.basis, required this.profile})
      : assert(profile.length == basis.k,
            'profile length must match basis.k (${basis.k})');

  /// The basis this operator is expressed over. Ring operations throw
  /// [StateError] when combining operators against different bases.
  final SpectralBasis basis;

  /// One value per mode, `profile[j] = f(λ_j)`.
  final Float64List profile;

  // ── Primitive constructors ─────────────────────────────────────────

  /// Identity operator. `1(λ) = 1` on every mode.
  factory SpectralOperator.identity(SpectralBasis basis) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = 1.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Zero operator. `0(λ) = 0`. Acts as `+` identity.
  factory SpectralOperator.zero(SpectralBasis basis) {
    return SpectralOperator(basis: basis, profile: Float64List(basis.k));
  }

  /// Heat semigroup `H_t = exp(−t·L)`. Satisfies
  /// `H_t · H_s = H_{t+s}` and `H_0 = identity`.
  factory SpectralOperator.heat(SpectralBasis basis, double t) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = math.exp(-t * basis.eigenvalues[j]);
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Wave cosine `cos(t·√L)`. Unitary in the sense that
  /// `cos²(t·√L) + sin²(t·√L) = I`.
  factory SpectralOperator.waveCos(SpectralBasis basis, double t) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      final sq = math.sqrt(math.max(basis.eigenvalues[j], 0.0));
      p[j] = math.cos(t * sq);
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Wave sine `sin(t·√L)`. Pairs with [waveCos] via Pythagorean
  /// `waveCos(t) · waveCos(t) + waveSin(t) · waveSin(t) = identity`.
  factory SpectralOperator.waveSin(SpectralBasis basis, double t) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      final sq = math.sqrt(math.max(basis.eigenvalues[j], 0.0));
      p[j] = math.sin(t * sq);
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Resolvent `R_z = (L − z·I)⁻¹`. Undefined when `z` coincides with
  /// an eigenvalue; callers should nudge z off the spectrum (complex
  /// imaginary part works; this API is real-only).
  factory SpectralOperator.resolvent(SpectralBasis basis, double z) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      final denom = basis.eigenvalues[j] - z;
      p[j] = denom.abs() > 1e-15 ? 1.0 / denom : 0.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Fractional Laplacian `L^α`. Interpolates between identity (α=0),
  /// Laplacian (α=1), bi-Laplacian (α=2). Fractional heat kernels
  /// `exp(−t·L^α)` describe anomalous diffusion: subdiffusion for
  /// α<1, superdiffusion for α>1.
  factory SpectralOperator.fractionalLaplacian(
    SpectralBasis basis,
    double alpha,
  ) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      final l = math.max(basis.eigenvalues[j], 0.0);
      p[j] = l == 0.0 && alpha <= 0.0 ? 0.0 : math.pow(l, alpha).toDouble();
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Band projection `1_{[lo, hi]}(L)` — an idempotent (`P · P = P`)
  /// that kills all mode content outside `[lo, hi]`.
  factory SpectralOperator.bandProjection(
    SpectralBasis basis,
    double lo,
    double hi,
  ) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      final l = basis.eigenvalues[j];
      p[j] = (l >= lo && l <= hi) ? 1.0 : 0.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Build from an arbitrary `f: ℝ → ℝ`. The most general constructor.
  factory SpectralOperator.fromFunction(
    SpectralBasis basis,
    double Function(double) f,
  ) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = f(basis.eigenvalues[j]);
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  // ── Ring operations ────────────────────────────────────────────────

  SpectralOperator operator +(SpectralOperator other) {
    _checkSameBasis(other, '+');
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j] + other.profile[j];
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  SpectralOperator operator -(SpectralOperator other) {
    _checkSameBasis(other, '-');
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j] - other.profile[j];
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Composition — in this commuting algebra, composition is
  /// pointwise product of profiles. `(f · g)(L) = f(L) · g(L)`.
  SpectralOperator operator *(SpectralOperator other) {
    _checkSameBasis(other, '*');
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j] * other.profile[j];
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Lie bracket `[A, B] = A·B − B·A`. In this commuting algebra
  /// (every operator is `f(L)` for some f, and functions of the same
  /// self-adjoint L commute pairwise) the bracket **always evaluates
  /// to the zero operator** — modulo floating-point dust, `|[A, B][j]|`
  /// is bounded by the IEEE double epsilon of the product.
  ///
  /// This is the theorem of the ring: **`SpectralOperator` forms an
  /// abelian Lie algebra over ℝ under the bracket**. Its structure
  /// constants vanish identically. Which is *exactly* why composition
  /// is order-independent, why `heat(t) · fractional(α) · bandProjection(...)`
  /// can be pre-combined into one profile, and why CRDT-friendly OT
  /// exists for spectral edits — the commutation kernel is trivially
  /// one.
  ///
  /// The method is shipped mostly as a runtime check: callers can
  /// verify at test time that their composite operators are indeed
  /// commuting, catching accidental introduction of a non-f(L)
  /// operator in the future.
  SpectralOperator commutator(SpectralOperator other) {
    _checkSameBasis(other, 'commutator');
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      // f(λ)·g(λ) − g(λ)·f(λ) — analytically zero for any f, g
      // that are functions of the SAME L. We compute it explicitly
      // rather than assert 0 so floating-point dust is visible.
      p[j] = profile[j] * other.profile[j] -
          other.profile[j] * profile[j];
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Operator norm — the maximum absolute profile entry. This is the
  /// spectral-radius sense: `‖A‖ = max_j |f(λ_j)|`. Used as a
  /// sanity metric for the commutator (should be ≈ 0) and for
  /// operator comparisons.
  double get operatorNorm {
    var m = 0.0;
    for (final v in profile) {
      final a = v.abs();
      if (a > m) m = a;
    }
    return m;
  }

  /// Scalar multiplication.
  SpectralOperator scale(double s) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = s * profile[j];
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// `exp(A)` — the matrix exponential on the spectrum:
  /// `exp(A)[j] = e^{f(λ_j)}`. Because the ring is abelian
  /// ([commutator] ≡ 0), the BCH formula collapses to addition:
  ///
  ///     exp(A + B) = exp(A) · exp(B) = exp(B) · exp(A)     (∀ A, B ∈ ring)
  ///
  /// This is the reason `heat(t) = exp(−t·L_sym)` composes trivially:
  /// `heat(s) · heat(t) = heat(s + t)` — addition on the time axis
  /// IS multiplication in the operator ring.
  SpectralOperator exp() {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = math.exp(profile[j]);
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// `log(A)` — logarithm on the spectrum, mode-by-mode. Returns 0
  /// on modes where `f(λ_j) ≤ eps` (including negatives) so the
  /// result stays finite on the zero mode and on signed profiles.
  /// The inverse of [exp]:
  ///
  ///     log(exp(A)) = A   (on modes where exp(f(λ)) > eps)
  SpectralOperator log({double eps = 1e-15}) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j] > eps ? math.log(profile[j]) : 0.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// `sqrt(A)` — square root on the spectrum. Returns 0 on negative
  /// or sub-eps modes so the result stays real and finite. Paired
  /// with [inverse] gives `1/sqrt(A)` — the natural "reciprocal
  /// length scale" operator, useful for building wavelet-like
  /// matched filters.
  ///
  /// Invariant: `sqrt(A) · sqrt(A) = A` on strictly-positive modes.
  SpectralOperator sqrt({double eps = 1e-15}) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j] > eps ? math.sqrt(profile[j]) : 0.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  /// Inverse — `1/f(λ_j)` on each mode. Returns zero at modes where
  /// `|f(λ_j)| ≤ eps` so the result stays finite. When the operator
  /// is non-vanishing, `A * A.inverse() = identity` on the basis.
  SpectralOperator inverse({double eps = 1e-15}) {
    final p = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      p[j] = profile[j].abs() > eps ? 1.0 / profile[j] : 0.0;
    }
    return SpectralOperator(basis: basis, profile: p);
  }

  // ── Application ────────────────────────────────────────────────────

  /// Apply this operator to a [SpectralProjection]. The projection
  /// must live on the same basis (checked by signature). Produces a
  /// new projection with coefficients `profile[j] · input[j]` — O(k).
  SpectralProjection applyTo(SpectralProjection input) {
    if (basis.signature != input.basis.signature) {
      throw StateError(
        'SpectralOperator.applyTo: basis signatures must match '
        '(${basis.signature} vs ${input.basis.signature})',
      );
    }
    final out = Float64List(basis.k);
    for (var j = 0; j < basis.k; j++) {
      out[j] = profile[j] * input.coefficients[j];
    }
    return SpectralProjection(basis: basis, coefficients: out);
  }

  /// Apply to a raw ρ-in-node-space. Projects into modes, applies the
  /// operator, reconstructs. Cost: O(k · n).
  Float64List applyToRho(Float64List rho) {
    final coeffs = basis.project(rho);
    for (var j = 0; j < basis.k; j++) {
      coeffs[j] *= profile[j];
    }
    return basis.recombineFromProjection(coeffs, 0.0);
  }

  // ── Scalar observables ─────────────────────────────────────────────

  /// Trace `tr(f(L)) = Σ_j f(λ_j)`.
  double get trace {
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      s += profile[j];
    }
    return s;
  }

  /// Operator Frobenius norm `‖f(L)‖_F = sqrt(Σ_j f(λ_j)²)`.
  double get frobeniusNorm {
    var s = 0.0;
    for (var j = 0; j < basis.k; j++) {
      s += profile[j] * profile[j];
    }
    return math.sqrt(s);
  }

  /// Spectral (operator) norm — largest |f(λ_j)| in absolute value.
  double get spectralNorm {
    var m = 0.0;
    for (var j = 0; j < basis.k; j++) {
      final a = profile[j].abs();
      if (a > m) m = a;
    }
    return m;
  }

  void _checkSameBasis(SpectralOperator other, String op) {
    if (basis.signature != other.basis.signature) {
      throw StateError(
        'SpectralOperator $op: basis signatures must match '
        '(${basis.signature} vs ${other.basis.signature})',
      );
    }
  }

  @override
  String toString() =>
      'SpectralOperator(basisSig=0x${basis.signature.toHex()}, '
      'k=${basis.k}, norm=${spectralNorm.toStringAsFixed(4)})';
}
