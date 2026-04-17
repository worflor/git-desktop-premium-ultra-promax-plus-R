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

  // --- polyhedron spin (radians per breath cycle)
  /// Baseline rotation rate for every polyhedron — the "idle breath".
  /// Expressed in fractions of a full turn per breath cycle so the
  /// tempo is tied to the same clock as everything else.
  static const double spinBaseTurnsPerCycle = 0.15;
  /// Extra rotation rate added for nodes with low [strength]: weaker
  /// evidence = more fidgety spin. Anchor (strength 1) gets none of
  /// this lift; peripheral nodes (strength ~0.3) take the full add.
  static const double spinWeaknessLift = 0.40;
  /// Per-node variance lift sourced from harmonic energy. Two nodes
  /// with identical strength still differ because their harmonics
  /// (PCA or spectral) don't match — prevents lockstep rotation.
  static const double spinHarmonicJitter = 0.10;
  /// Hard bounds so no node either freezes or hums — both read as
  /// broken states.
  static const double spinMinTurnsPerCycle = 0.08;
  static const double spinMaxTurnsPerCycle = 0.55;

  // --- polyhedron spin axis composition (unit-vector weights before
  // normalization; ratios between them decide the axis's character,
  // individual magnitudes are arbitrary)
  /// Weight of the phase-circle contribution (axis components drift
  /// around the unit circle as the node's `phase` rotates). Dominant
  /// term — this is what gives each path its own rotation axis.
  static const double spinAxisPhaseWeight = 0.62;
  /// Weight of `harmonics[1..2]` in the lateral (x, y) axis
  /// components. Lets the engine's spectral basis (or rhyme PCA) tilt
  /// the spin axis laterally — same file seen through different
  /// perspectives rotates around the same real spectral axis.
  static const double spinAxisHarmonicLateralWeight = 0.30;
  /// Weight of `harmonics[3]` in the longitudinal (z) component.
  static const double spinAxisHarmonicLongitudinalWeight = 0.85;
  /// Constant forward bias on the longitudinal component. Prevents
  /// the axis from ever collapsing into the screen plane, which
  /// would produce degenerate "edge-on spin" with no visible motion.
  static const double spinAxisLongitudinalBias = 0.45;

  // --- base-pose phase multipliers (irrational ratios so pitch,
  // roll, and yaw never synchronize and shapes don't "re-hit" the
  // same silhouette at regular intervals)
  /// Multiplier from base `phase` to pitch phase. √3 — irrational,
  /// keeps pitch decoupled from yaw's integer-period harmonics.
  static const double posePitchPhaseMult = 1.7320508075688772;
  /// Multiplier from base `phase` to roll phase. √2 — irrational and
  /// coprime-ish with [posePitchPhaseMult] so all three pose axes
  /// decorrelate even across long time spans.
  static const double poseRollPhaseMult = 1.4142135623730951;
  /// Pitch amplitude (radians). Together with [poseRollAmp] bounds
  /// the per-node base tilt so no node drifts more than this many
  /// radians from its "neutral" pose.
  static const double posePitchAmp = 0.55;
  static const double poseRollAmp = 0.45;

  // --- support-driven presence
  /// Radius multiplier per unit of evidence support. A node with
  /// support = 8 gets (1 + 8 × lift) × its baseline radius. Scales
  /// with the polyhedron's actual topology so an icosa with heavy
  /// support reads as PHYSICALLY larger than a nearby cube — not
  /// just more-faceted at the same size. Counting vertices is slow;
  /// comparing sizes is instant.
  static const double supportPresenceLift = 0.055;

  // --- intro ease character (per-node)
  /// How much the per-node intro ease blends toward a snap curve
  /// (easeOutExpo) vs the default easeOutCubic. Weight comes from
  /// `comet.strength`: at blend=0.55 and strength=1.0, the anchor
  /// lands on a fully snap-heavy ease so its arrival feels decisive;
  /// a weak tetra (strength ≈ 0.4) arrives soft. Confidence becomes
  /// tempo, not just topology.
  static const double introSnapBlend = 0.55;

  // --- ghost spin amplification
  /// Max multiplier on a ghost's `spinTurnsPerCycle`, keyed to its
  /// strength within the ghost score range. A ghost at the top of
  /// the range (almost-present) spins up to this × faster; one at
  /// the bottom (deep background) gets no boost. The almost-
  /// presence fidgets; the forgotten sits still.
  static const double ghostSpinAmplification = 1.8;

  // --- link droplet tempo
  /// Base travel speed for link droplets, expressed as cycles per
  /// breath cycle. 1.0 = one full traversal per breath; 0.7 = gentle.
  static const double dropletBaseSpeed = 0.7;
  /// Additional speed added proportionally to the link's strength.
  /// A strong transport edge (pull = 1.0) gets base + this extra —
  /// visibly more urgent than a weak one, which stays near base.
  /// Urgency reads as tempo, not label.
  static const double dropletPullSpeedLift = 0.6;

  // --- slerp settle overshoot (fused landing)
  /// Fraction of slerp duration over which the settle-overshoot
  /// fires at the end of a perspective transition. During this
  /// window, positions push past their target by
  /// [slerpSettleOvershoot] then return to exact target at t=1.0,
  /// giving the scene a small "landed" recoil instead of stopping
  /// flat.
  static const double slerpSettleWindow = 0.12;
  /// Overshoot amplitude — how far positions push past their target
  /// during the settle window, as a fraction of the morph delta.
  /// 0.09 is visible without looking like a glitch.
  static const double slerpSettleOvershoot = 0.09;

  // --- focus ring tempo
  /// Motion multiplier for the focus-ring acquisition animation
  /// (relative to the active theme's `shader.duration`). One unit
  /// is snappy by design — the ring should feel like a confirmed
  /// click, not a slow fade-in. Lands in ~80–180ms depending on
  /// theme.
  static const int focusRingDurationMult = 1;

  // --- polyhedron vertex stretch (from harmonics)
  /// Lateral (x, y) stretch scale — how much a unit harmonic coord
  /// squashes or elongates the polyhedron along that axis.
  static const double vertexStretchLateral = 0.28;
  /// Longitudinal (z) stretch scale — held slightly lower so depth
  /// squash doesn't dominate the silhouette.
  static const double vertexStretchLongitudinal = 0.22;
  /// Clamps on the post-stretch scale factor per axis.
  static const double vertexStretchMinLateral = 0.70;
  static const double vertexStretchMaxLateral = 1.30;
  static const double vertexStretchMinLongitudinal = 0.78;
  static const double vertexStretchMaxLongitudinal = 1.22;
}
