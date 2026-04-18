// LOGOS STATE — unified snapshot of the spectral engine.
//
// Scope: this is the outer primitive of the SPECTRAL ENGINE
// specifically — file spectrum, commit spectrum, joint spacetime
// basis, plus revision counter. It does NOT include the UI theme, the
// blame cache, the Alexandria brain, or other app-level state; those
// live elsewhere on purpose.
//
// Three practical uses:
//   - cross-machine state compare (sync): equal signatures ⇒ same
//     spectra at the same revision
//   - disk cache addressing: keyed by signature
//   - ratchet checkpointing: forward-only evolution from one value
//     to the next
//
// The fields are nullable because building a spectrum is
// amortisation-gated (see `kDefaultSpectralMinNodes`): tiny graphs
// skip the Lanczos pass and the field stays null. `signature` mixes
// whatever is populated, so a null-vs-not-null difference across
// states produces distinct signatures.

import 'logos_core.dart';
import 'logos_signature.dart';
import 'spectral_spacetime.dart';

/// Immutable snapshot of a Logos engine's spectral state.
///
/// Any subset of the fields can be null — a newly-built engine on a
/// small graph has no file spectrum (below the amortisation
/// threshold); a fresh repo has no commit spectrum yet; the joint
/// spacetime basis is computed only when both factors exist. The
/// signature mixes whatever is present, so two states with the same
/// populated fields and matching signatures are structurally
/// identical; two states with different populated fields have
/// different signatures by construction.
///
/// Observables fan out across the populated levels. When both file
/// and joint are available, joint is preferred (it factors through
/// file). When neither is, the observable returns zero.
class LogosState {
  LogosState({
    required this.fileSpectrum,
    required this.commitSpectrum,
    required this.joint,
    required this.revision,
  }) : signature = _computeSignature(
          fileSpectrum?.signature ?? Signature.zero,
          commitSpectrum?.signature ?? Signature.zero,
          joint?.signature ?? Signature.zero,
          revision,
        );

  /// File-level spectral identity. Null when the file graph is below
  /// the spectral-amortisation threshold or hasn't been built.
  final SpectralBasis? fileSpectrum;

  /// Commit-level spectral identity. Null when `perFileCommitIndices`
  /// is empty or below the threshold.
  final SpectralBasis? commitSpectrum;

  /// Joint spacetime basis (file × commit Kronecker sum). Null when
  /// either factor is unavailable. When populated, heat-trace and
  /// joint-diffuse observables flow through this factor.
  final SpacetimeBasis? joint;

  /// Monotonic revision counter. Carries no content — two states with
  /// the same spectra at different revisions have different
  /// signatures so observers can pin a moment in time.
  final int revision;

  /// Unified identity fingerprint. Mixed from the three factor
  /// signatures + revision via FNV-1a on both halves. Used for
  /// equality, Map/Set keys, disk cache addressing, and ratchet
  /// diagnose fast-path.
  final Signature signature;

  /// Empty state — no spectra, revision 0. Used as the initial state
  /// before anything has been built, and as the neutral element for
  /// comparisons.
  factory LogosState.empty() => LogosState(
        fileSpectrum: null,
        commitSpectrum: null,
        joint: null,
        revision: 0,
      );

  /// True when no spectra have been materialised and revision is 0.
  bool get isEmpty =>
      fileSpectrum == null &&
      commitSpectrum == null &&
      joint == null &&
      revision == 0;

  // ── Withers ──────────────────────────────────────────────────────

  LogosState withFileSpectrum(SpectralBasis? next) => LogosState(
        fileSpectrum: next,
        commitSpectrum: commitSpectrum,
        joint: joint,
        revision: revision,
      );

  LogosState withCommitSpectrum(SpectralBasis? next) => LogosState(
        fileSpectrum: fileSpectrum,
        commitSpectrum: next,
        joint: joint,
        revision: revision,
      );

  LogosState withJoint(SpacetimeBasis? next) => LogosState(
        fileSpectrum: fileSpectrum,
        commitSpectrum: commitSpectrum,
        joint: next,
        revision: revision,
      );

  LogosState withRevision(int next) => LogosState(
        fileSpectrum: fileSpectrum,
        commitSpectrum: commitSpectrum,
        joint: joint,
        revision: next,
      );

  // ── Fan-out observables ──────────────────────────────────────────

  /// Heat trace at scale t, preferring the joint spacetime basis when
  /// available (because joint.heatTrace factors as file×time so it
  /// contains both factors' information). Falls back to file then
  /// commit. Returns 0 when the state has no spectra.
  double heatTrace(double t) {
    if (joint != null) return joint!.heatTrace(t);
    if (fileSpectrum != null) return fileSpectrum!.heatTrace(t);
    if (commitSpectrum != null) return commitSpectrum!.heatTrace(t);
    return 0.0;
  }

  /// Spectral gap from whichever basis is available. Joint's gap is
  /// the minimum of its two factors' gaps (since joint eigenvalues
  /// are λᵢ + μⱼ, the smallest non-trivial one is min(λ₁, μ₁)).
  double get spectralGap {
    double? tryRead(SpectralBasis? b) => b?.spectralGap;
    final f = tryRead(fileSpectrum);
    final c = tryRead(commitSpectrum);
    final gaps = <double>[
      if (f != null) f,
      if (c != null) c,
    ];
    if (gaps.isEmpty) return 0.0;
    return gaps.reduce((a, b) => a < b ? a : b);
  }

  /// Signature-based equality. Two states match iff they project
  /// through the same spectra at the same revision.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LogosState && signature == other.signature);

  @override
  int get hashCode => signature.hashCode;

  /// Hierarchical divergence report against another state.
  LogosStateDiff diff(LogosState other) =>
      LogosStateDiff.compare(this, other);

  @override
  String toString() => 'LogosState('
      'signature=0x${signature.toHex()}, '
      'revision=$revision, '
      'file=${fileSpectrum == null ? "null" : "sig=0x${fileSpectrum!.signature.toHex()}"}, '
      'commit=${commitSpectrum == null ? "null" : "sig=0x${commitSpectrum!.signature.toHex()}"}, '
      'joint=${joint == null ? "null" : "sig=0x${joint!.signature.toHex()}"})';
}

/// Hierarchical difference between two LogosStates. Follows the same
/// "coarse → fine" pattern as [RatchetDiagnostics]: cheapest checks
/// first, then narrow the scope. Used for cross-machine sync (send
/// only the factors that actually diverged) and for "what changed
/// between HEAD~1 and HEAD" introspection.
class LogosStateDiff {
  const LogosStateDiff({
    required this.signatureMatch,
    required this.revisionDelta,
    required this.fileSpectrumChanged,
    required this.commitSpectrumChanged,
    required this.jointChanged,
    required this.filePerNodeHamming,
  });

  /// True iff the two states share a signature. When true, nothing
  /// else in this diff is informative.
  final bool signatureMatch;

  /// `other.revision - this.revision`. Positive means `other` is
  /// further along the ratchet; negative means stale.
  final int revisionDelta;

  /// Which factors differ between the two states. Populated only
  /// when `signatureMatch` is false.
  final bool fileSpectrumChanged;
  final bool commitSpectrumChanged;
  final bool jointChanged;

  /// Per-path Hamming distance on the 8-bit spectral fingerprint
  /// between the two file spectra. Populated only when
  /// `fileSpectrumChanged` is true AND both file spectra are labeled
  /// with the same paths; empty otherwise. This is the
  /// finest-grained localisation the math exposes without doing
  /// per-node eigenvector comparisons.
  final Map<String, int> filePerNodeHamming;

  /// Fully consistent — both states agree everywhere.
  bool get inSync => signatureMatch;

  static LogosStateDiff compare(LogosState a, LogosState b) {
    if (a.signature == b.signature) {
      return LogosStateDiff(
        signatureMatch: true,
        revisionDelta: b.revision - a.revision,
        fileSpectrumChanged: false,
        commitSpectrumChanged: false,
        jointChanged: false,
        filePerNodeHamming: const {},
      );
    }
    final fileChanged = (a.fileSpectrum?.signature ?? Signature.zero) !=
        (b.fileSpectrum?.signature ?? Signature.zero);
    final commitChanged = (a.commitSpectrum?.signature ?? Signature.zero) !=
        (b.commitSpectrum?.signature ?? Signature.zero);
    final jointChanged = (a.joint?.signature ?? Signature.zero) !=
        (b.joint?.signature ?? Signature.zero);

    final perPath = <String, int>{};
    if (fileChanged &&
        a.fileSpectrum != null &&
        b.fileSpectrum != null &&
        a.fileSpectrum!.n == b.fileSpectrum!.n &&
        a.fileSpectrum!.nodePaths != null) {
      final fpA = a.fileSpectrum!.spectralFingerprintTable();
      final fpB = b.fileSpectrum!.spectralFingerprintTable();
      final paths = a.fileSpectrum!.nodePaths!;
      final limit = fpA.length < fpB.length ? fpA.length : fpB.length;
      for (var i = 0; i < limit && i < paths.length; i++) {
        final d = popcount8(fpA[i] ^ fpB[i]);
        if (d > 0) perPath[paths[i]] = d;
      }
    }
    return LogosStateDiff(
      signatureMatch: false,
      revisionDelta: b.revision - a.revision,
      fileSpectrumChanged: fileChanged,
      commitSpectrumChanged: commitChanged,
      jointChanged: jointChanged,
      filePerNodeHamming: perPath,
    );
  }
}

/// Two-stream FNV-1a combining four input signatures into one
/// [Signature]. Each input Signature contributes both halves to both
/// output streams with different per-slot salts so the mixing reaches
/// the full combined entropy even when some inputs are zero.
Signature _computeSignature(
    Signature file, Signature commit, Signature joint, int revision) {
  const mask = 0x7fffffff;
  var hLo = 0x811c9dc5 ^ revision;
  var hHi = 0xdeadbeef ^ revision;
  for (final (part, saltLo, saltHi) in [
    (file, 0x01020304, 0x11121314),
    (commit, 0x05060708, 0x15161718),
    (joint, 0x090a0b0c, 0x191a1b1c),
  ]) {
    hLo = (hLo ^ part.lo ^ saltLo) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hLo = (hLo ^ part.hi) & mask;
    hLo = ((hLo * 0x01000193) ^ (hLo >> 13)) & mask;
    hHi = (hHi ^ part.hi ^ saltHi) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
    hHi = (hHi ^ part.lo) & mask;
    hHi = ((hHi * 0x01000193) ^ (hHi >> 13)) & mask;
  }
  return Signature(lo: hLo, hi: hHi);
}

