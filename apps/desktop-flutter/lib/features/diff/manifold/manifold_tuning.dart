// Tuning knobs for the Manifold drawer.
//
// Every named constant has a single home here so the painter, the
// pane, and anything downstream reference one source of truth.
// Motion values are expressed as multiples of the active theme's
// `shader.duration` so snappy/fluid/elastic themes each get their
// own timing character — no arbitrary millisecond literals scattered
// through widget code.

/// Just-intonation interval ratios. Every pitch assigned to a comet
/// comes from this set so consonant pairs reinforce cleanly and
/// dissonant pairs read as tension.
class JustIntonation {
  JustIntonation._();
  static const double tonic = 1.0;
  static const double majorSecond = 9 / 8;
  static const double majorThird = 5 / 4;
  static const double perfectFourth = 4 / 3;
  static const double perfectFifth = 3 / 2;
  static const double majorSixth = 5 / 3;
  static const double majorSeventh = 15 / 8;
  static const double octave = 2.0;

  /// Below the tonic — used for ghosts so absence rings under the
  /// voicing instead of within it.
  static const double subharmonicFourth = 3 / 4;
}

/// Tuning constants for the Manifold drawer. Nothing here is an
/// arbitrary literal scattered through the code — every value has a
/// name and a rationale.
class ManifoldTuning {
  ManifoldTuning._();

  // --- motion (multiplied by shader.duration via context.motion)
  static const int introDurationMult = 4;
  static const int slerpDurationMult = 5;

  /// Theme-independent ambient drift clock. Fixed so time-dependent
  /// motion (breath, traveling droplets) moves at a predictable pace
  /// across themes.
  static const Duration breathCycle = Duration(seconds: 5);

  // --- chart geometry (fractions of pane size)
  static const double rhymeShellRadius = 0.22;
  static const double rhymeShellDepth = 0.20;
  static const double relatedShellRadius = 0.36;
  static const double relatedShellDepth = 0.28;

  /// Vertical compression — pane is wider than tall, so y positions
  /// multiply by this to keep shells as flattened ellipses instead
  /// of overflowing.
  static const double shellAspect = 0.72;

  // --- tangent geometry
  static const double tangentFanRadius = 0.34;
  static const double tangentFanDepth = 0.30;

  /// Drawer pane body height in logical pixels. Fixed so the drawer
  /// keeps a predictable footprint regardless of content density.
  static const double paneHeight = 202.0;

  // --- PCA → harmonic amplification
  /// PCA coords arrive in ~[-0.35, 0.35]. Multiply by this when
  /// pushing into h2/h3 Fourier coefficients so harmonics are
  /// audible without eclipsing the fundamental.
  static const double harmonicXYAmplification = 2.6;
  static const double harmonicZAmplification = 2.0;
  static const double harmonicClamp = 0.9;
  static const double harmonicPhaseClamp = 1.0;

  // --- score clamps
  static const double scoreMinRhyme = 0.4;
  static const double scoreMaxRhyme = 0.92;
  static const double scoreMinRelated = 0.3;
  static const double scoreMaxRelated = 0.9;
  static const double scoreMinTangent = 0.28;
  static const double scoreMaxTangent = 0.95;
  static const double scoreMinGhost = 0.22;
  static const double scoreMaxGhost = 0.55;

  // --- transport-pull interval thresholds
  static const double pullStrong = 0.7;
  static const double pullMedium = 0.5;
  static const double pullWeak = 0.3;
}
