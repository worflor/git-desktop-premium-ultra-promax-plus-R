// HyperhealthText — the repo title's sheen-based F-state visualisation.
//
// Design decisions:
//
// * **No ambient color tint.** Base text colour is exactly what the
//   caller passes — the engine's F state never silently repaints the
//   letters. Colour changes only happen for user-caused events
//   (hover, etc.), which the caller drives by adjusting `baseColor`.
//
// * **Sheen morphs with universality.** The repo's *universality
//   vector* (which archetype the spectrum matches — crystalline,
//   poisson, goe, tree, bulk, modular) dictates the sheen's shape:
//   how many bands, their width, tilt, palette. The sheen on a
//   path-like codebase looks structurally different from the sheen
//   on a chaotic one — because the spectra DO differ, and the light
//   picks that up.
//
// * **Each sweep is different.** Per-cycle seed + smooth noise
//   modulation means consecutive ambient sweeps never trace the same
//   path twice. Tilt, phase offset, hue rotation all drift. It
//   reads as alive, not as a loop.
//
// * **Refresh is a distinct gesture.** When the user kicks off a
//   fetch, the sheen doesn't just play faster — it changes SHAPE:
//   two bands converge from the edges, meet in the centre with a
//   brightness spike, dissolve outward as chromatic fringes. Reads
//   as "synchronising," not "scanning again."
//
// * **No breathing.** No scale oscillation. No passive color pulse.
//   If the widget looks still, it IS still.
//
// Technique: layered ShaderMask shimmer. Each band is a `ShaderMask`
// with `BlendMode.srcIn` over a chromatic gradient. Multi-band
// profiles stack one Mask per band, each with its own phase — they
// read as parallax-separated surface interference. Cost stays
// bounded: a title is ~100px wide, at most 3 masks per frame.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../backend/logos_spectrogeometry.dart' show UniversalityVector;
import 'motion.dart';
import 'tokens.dart';

/// Period of a single ambient sheen cycle at motion-rate = 1.0. Per-
/// archetype `speedScale` in the [_SheenProfile] can dilate/compress
/// this, so a "chaotic" repo breathes differently from an "ordered"
/// one without needing a second constant.
const Duration _kAmbientPeriodBase = Duration(milliseconds: 9500);

/// Period of a refresh sheen. Fast, deliberate — reads as a "go"
/// gesture tied to the user's click.
const Duration _kRefreshPeriod = Duration(milliseconds: 680);

/// The visible fraction of a cycle during which the band crosses the
/// text (the rest of the cycle is approach/exit off-screen). Ambient
/// sheens use a short window so most of the time is "still"; refresh
/// sheens use the full window to read as a decisive swoosh.
const double _kAmbientVisibleFraction = 0.18;

class HyperhealthText extends StatefulWidget {
  /// The text to render.
  final String text;

  /// Base text colour — the caller controls this completely. The widget
  /// NEVER changes it on its own. Health state only drives the sheen
  /// overlay; the underlying typography remains what the caller said.
  final Color baseColor;

  /// Text style minus colour.
  final TextStyle style;

  /// Continuous health anomaly in `[0, 1]`. `0.0` = no sheen at all.
  /// Higher values produce a wider, brighter, more chromatic swoosh.
  final double intensity;

  /// When `true`, a fast bright sheen sweeps the title on a refresh
  /// cadence until `refreshing` flips back to `false`. Uses a
  /// structurally distinct gesture from the ambient sheen.
  final bool refreshing;

  /// Universality classification of the repo's spectrum. When
  /// supplied, the sheen's shape — band count, width, palette mix,
  /// tilt — is derived from the nearest archetype. Without it, a
  /// neutral profile is used.
  final UniversalityVector? universality;

  /// Overflow for the underlying `Text` widgets.
  final TextOverflow overflow;

  const HyperhealthText({
    super.key,
    required this.text,
    required this.baseColor,
    required this.style,
    this.intensity = 0.0,
    this.refreshing = false,
    this.universality,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  State<HyperhealthText> createState() => _HyperhealthTextState();
}

class _HyperhealthTextState extends State<HyperhealthText>
    with TickerProviderStateMixin {
  /// Slow ambient cycle — runs whenever `intensity > 0` and motion is
  /// enabled. Controller value in `[0, 1]` maps to sheen band x-offset.
  AnimationController? _ambient;

  /// Fast refresh cycle — runs while `refreshing` is true.
  AnimationController? _refresh;

  /// Bumped each time the ambient controller completes a cycle. Seeds
  /// the per-sweep noise so consecutive sweeps differ in tilt, phase,
  /// and hue rotation.
  int _sweepSeed = 0;

  /// Period scale the current ambient controller was built for. Kept
  /// so we can detect archetype changes and rebuild the controller
  /// at the new tempo without disrupting the ongoing sweep visibly.
  double _ambientPeriodScale = 1.0;

  double _clampedIntensity() => widget.intensity.clamp(0.0, 1.0).toDouble();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickers();
  }

  @override
  void didUpdateWidget(covariant HyperhealthText old) {
    super.didUpdateWidget(old);
    if (old.intensity != widget.intensity ||
        old.refreshing != widget.refreshing ||
        (_periodScaleFor(old.universality) -
                    _periodScaleFor(widget.universality))
                .abs() >
            1e-6) {
      _syncTickers();
    }
  }

  void _syncTickers() {
    final intensity = _clampedIntensity();
    final motionRate = context.motionRate;
    final motionActive = motionRate > 0.05;
    final rate = motionRate.clamp(0.1, 2.0);

    // Resolve the archetype-blended period once per sync. Pure
    // function of universality → weighted mix over the archetype
    // templates, same weights the profile uses.
    final periodScale = _periodScaleFor(widget.universality);

    // Ambient sheen runs continuously while the repo is anomalous.
    // When the archetype's period changes we rebuild the controller
    // at the new tempo — this is how the sheen's *rhythm* carries
    // the repo's nature, not just its look.
    final shouldAmbient = intensity > 0.001 && motionActive;
    if (shouldAmbient) {
      final needsRebuild =
          _ambient == null || (_ambientPeriodScale - periodScale).abs() > 1e-6;
      if (needsRebuild) {
        _ambient?.dispose();
        final ms = (_kAmbientPeriodBase.inMilliseconds * periodScale / rate)
            .round();
        _ambient = AnimationController(
          vsync: this,
          duration: Duration(milliseconds: ms),
        )
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed ||
                s == AnimationStatus.dismissed) {
              // Bump sweep seed at the boundary so the NEXT cycle
              // picks up fresh noise phases.
              _sweepSeed = (_sweepSeed + 1) & 0xFFFF;
            }
          })
          ..repeat();
        _ambientPeriodScale = periodScale;
      }
    } else {
      _ambient?.dispose();
      _ambient = null;
    }

    // Refresh sheen runs while the user has a fetch in flight. Its
    // period stays constant across archetypes — a fetch is a user
    // affordance and needs consistent feel.
    final shouldRefresh = widget.refreshing && motionActive;
    if (shouldRefresh) {
      _refresh ??= AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (_kRefreshPeriod.inMilliseconds / rate).round(),
        ),
      )..repeat();
    } else {
      _refresh?.dispose();
      _refresh = null;
    }
  }

  /// Archetype-blended period scale. Returns the weighted average of
  /// each archetype's `periodScale`, with weights from the same
  /// distance-based mix the sheen profile uses. Kept in sync with the
  /// profile's temporal character so ticker rebuilds happen exactly
  /// when the blended tempo shifts — not when `nearest` flips between
  /// two close-tied archetypes.
  double _periodScaleFor(UniversalityVector? u) {
    if (u == null) return 1.0;
    final weights = _archetypeWeights(u);
    var sum = 0.0;
    weights.forEach((name, w) {
      sum += w * _archetypeTemplates[name]!.periodScale;
    });
    return sum;
  }

  @override
  void dispose() {
    _ambient?.dispose();
    _refresh?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style.copyWith(color: widget.baseColor);

    // Plain text when there's nothing to sheen about.
    if (_ambient == null && _refresh == null) {
      return Text(
        widget.text,
        style: effectiveStyle,
        overflow: widget.overflow,
        maxLines: 1,
      );
    }

    final tokens = context.tokens;
    final intensity = _clampedIntensity();
    final profile = _SheenProfile.fromContext(
      universality: widget.universality,
      intensity: intensity,
      chroma1: tokens.hyperChromatic1,
      chroma2: tokens.hyperChromatic2,
      core: tokens.hyperCore,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([
        if (_ambient != null) _ambient!,
        if (_refresh != null) _refresh!,
      ]),
      builder: (context, _) {
        // Refresh takes precedence when active — it's a decisive
        // gesture that shouldn't be diluted by ambient layers.
        final refreshing = _refresh != null;
        if (refreshing) {
          return _RefreshSheenStack(
            text: widget.text,
            baseStyle: effectiveStyle,
            overlayStyle: widget.style.copyWith(color: Colors.white),
            overflow: widget.overflow,
            phase: _refresh!.value,
            chroma1: tokens.hyperChromatic1,
            chroma2: tokens.hyperChromatic2,
            core: tokens.hyperCore,
          );
        }

        return _AmbientSheenStack(
          text: widget.text,
          baseStyle: effectiveStyle,
          overlayStyle: widget.style.copyWith(color: Colors.white),
          overflow: widget.overflow,
          phase: _ambient!.value,
          sweepSeed: _sweepSeed,
          profile: profile,
          tier: _sheenTier(intensity),
        );
      },
    );
  }
}

// ── Ambient sheen ─────────────────────────────────────────────────
//
// A layered sweep. Each band in the profile gets its own ShaderMask,
// with a per-band phase offset so the bands drift through the text
// at slightly different times. This reads as depth — like specular
// highlights on a faceted surface, where each facet catches light at
// a slightly different angle.

class _AmbientSheenStack extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final TextStyle overlayStyle;
  final TextOverflow overflow;
  final double phase;
  final int sweepSeed;
  final _SheenProfile profile;

  /// Severity tier (0-4). Each rung adds a distinct visual feature:
  /// tier 2 bloom, tier 3 echo band, tier 4 heartbeat pulse. Archetype
  /// shape is unchanged by tier — they're orthogonal axes.
  final int tier;

  const _AmbientSheenStack({
    required this.text,
    required this.baseStyle,
    required this.overlayStyle,
    required this.overflow,
    required this.phase,
    required this.sweepSeed,
    required this.profile,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    final baseText = Text(
      text,
      style: baseStyle,
      overflow: overflow,
      maxLines: 1,
    );
    // Build N band overlays. Each consults the profile for its own
    // phase offset, colour shift, and width jitter. Degradation is
    // the same across all bands of a given tier — the whole sheen
    // drains together, not band-by-band.
    final degradation = _tierDegradation(tier);
    final layers = <Widget>[baseText];
    for (var i = 0; i < profile.bandCount; i++) {
      final bandPhase = (phase + profile.bandPhaseOffset(i)) % 1.0;
      final center = _bandCenter(bandPhase);
      if (center == null) continue;
      final seedForBand = sweepSeed * 7 + i * 13;
      final layer = _SheenBandLayer(
        text: text,
        overlayStyle: overlayStyle,
        overflow: overflow,
        center: center,
        profile: profile,
        bandIndex: i,
        sweepSeed: seedForBand,
        bandPhase: bandPhase,
        desaturation: degradation,
        // Tier 2+ injects high-frequency alpha jitter — the band's
        // peak stops being a clean bell and starts flickering.
        // Reads as "the signal is noisy," not "the signal got
        // shinier."
        jitterAmp: tier >= 2 ? (0.10 + 0.06 * (tier - 2)) : 0.0,
      );
      layers.add(Positioned.fill(child: layer));
    }

    // Tier 3 — shadow echo. A trailing band that's HEAVILY
    // desaturated (closer to grey than the primary). Reads as a
    // washed-out ghost tracking behind the light, not a twin
    // reflection. Still half-alpha, but the greyed palette is what
    // really sells it as "degraded."
    if (tier >= 3) {
      final echoPhase = (phase - 0.40 * _kAmbientVisibleFraction) % 1.0;
      final echoCenter = _bandCenter(echoPhase);
      if (echoCenter != null) {
        layers.add(Positioned.fill(
          child: _SheenBandLayer(
            text: text,
            overlayStyle: overlayStyle,
            overflow: overflow,
            center: echoCenter,
            profile: profile,
            bandIndex: 0,
            sweepSeed: sweepSeed * 11 + 42,
            bandPhase: echoPhase,
            alphaScale: 0.50,
            // Echo compounds the primary's desaturation with its own
            // extra drain — always reads as a colourless shadow.
            desaturation: math.min(1.0, degradation + 0.35),
            jitterAmp: 0.0,
          ),
        ));
      }
    }

    // Tier 4 — chromatic undertow. The band's fringe colours can't
    // stay contained: they leak into the whole word as a slow, wide
    // chromatic gradient that drifts at its own cadence, completely
    // independent of the primary sweep. Always visible (never zero-
    // alpha), noise-modulated so it shimmers organically, with the
    // gradient direction slowly crawling over the text.
    //
    // Physically this maps to spectral broadening: when a repo's
    // coherence collapses, the peak isn't the only thing radiating —
    // the whole spectrum glows. The undertow is that radiation made
    // visible, bleeding from chroma1 through the neutral toward
    // chroma2, with the balance point wandering continuously.
    if (tier >= 4) {
      // Independent cadence. Multiplier is irrational-ish so the
      // undertow never re-aligns with the sweep — there's no point
      // where the user perceives "the loop restarted."
      final undertowT = (phase * 2.37 + 0.17) % 1.0;
      // Smooth balance-point drift: gradient centre walks from the
      // left edge through the right edge and wraps. Noise adds
      // subtle hesitation so the motion isn't mechanical.
      final drift = _noise(undertowT, sweepSeed + 21.0);
      final center = ((undertowT + 0.08 * drift) * 1.4 - 0.2)
          .clamp(-0.25, 1.25)
          .toDouble();

      // Alpha breathes on its own noise envelope — never zero, but
      // rises and falls so the undertow isn't a static tint.
      final breath = _noise(undertowT * 1.6, sweepSeed + 34.5);
      final undertowAlpha =
          (0.13 + 0.06 * breath).clamp(0.07, 0.22).toDouble();

      // Gradient spans the whole text. Three stops:
      //   before `center` → chroma1 (cyan side)
      //   at `center`     → fully transparent (neutral pivot)
      //   after `center`  → chroma2 (magenta side)
      // The neutral pivot prevents the undertow from tinting the
      // whole word at once; at any instant, one side of the word
      // leans chroma1 and the other leans chroma2, with the pivot
      // slowly walking across.
      //
      // CRITICAL: never use `.clamp(lo, hi)` where `lo` could exceed
      // `hi` — Dart throws ArgumentError and the ShaderMask paints
      // a grey ErrorWidget for that frame, which reads as a full-
      // app grey flash every few seconds. Compute each pivot with
      // an INDEPENDENT clamp into [0, 1], then resolve any collision
      // with plain math.min / math.max.
      //
      // The stops array ([0.0, pivotLeft, pivotRight, 1.0]) must be
      // STRICTLY increasing, not just non-decreasing. Skia tolerates
      // duplicates without throwing, but a `stops[0] == stops[1]`
      // collision collapses the leading colour band to zero width —
      // leaving the left edge of the text uncoloured, the opposite of
      // the design intent. The clamps below pin each pivot off the
      // boundaries (≥ eps, ≤ 1-eps) so stops[0] < stops[1] and
      // stops[2] < stops[3] always hold; the collision guard then
      // covers the interior pivotLeft / pivotRight case.
      const eps = 1e-6;
      var pivotLeft = (center - 0.08).clamp(0.0, 1.0).toDouble();
      var pivotRight = (center + 0.08).clamp(0.0, 1.0).toDouble();
      // Edge clamps — keep pivots strictly inside (0, 1).
      if (pivotLeft < eps) pivotLeft = eps;
      if (pivotRight > 1.0 - eps) pivotRight = 1.0 - eps;
      // Interior collision — after edge clamping a residual inversion
      // is only possible when center is inside the band where both
      // pivots land on the same near-edge; resolve with math so we
      // never risk an inverted clamp.
      if (pivotRight <= pivotLeft) {
        if (pivotLeft >= 1.0 - eps) {
          pivotLeft = 1.0 - 2 * eps;
          pivotRight = 1.0 - eps;
        } else {
          pivotRight = math.min(pivotLeft + eps, 1.0 - eps);
        }
      }
      final stops = <double>[0.0, pivotLeft, pivotRight, 1.0];
      // Undertow colours carry the full tier-4 degradation — the
      // most drained state. At tier 4, degradation is ~0.78, so the
      // chromatic bleed reads as muted dissonance, not vibrant
      // coherence. The dissonance is the point: coherence has
      // collapsed, and we're seeing grey-ish ghosts of what the
      // theme's chromatics looked like when the spectrum was
      // healthy.
      final undertowC1 = _desaturate(profile.chroma1, degradation);
      final undertowC2 = _desaturate(profile.chroma2, degradation);
      final colors = <Color>[
        undertowC1.withValues(alpha: undertowAlpha),
        undertowC1.withValues(alpha: undertowAlpha * 0.15),
        undertowC2.withValues(alpha: undertowAlpha * 0.15),
        undertowC2.withValues(alpha: undertowAlpha),
      ];

      layers.add(Positioned.fill(
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
            stops: stops,
          ).createShader(bounds),
          child: Text(
            text,
            style: overlayStyle,
            overflow: overflow,
            maxLines: 1,
          ),
        ),
      ));
    }

    if (layers.length == 1) return baseText;
    return Stack(children: layers);
  }

  /// Map a band's phase `[0, 1]` to its x-centre, or `null` when the
  /// band is currently off-screen (outside the visible fraction of
  /// its cycle).
  double? _bandCenter(double p) {
    if (p > _kAmbientVisibleFraction) return null;
    final local = p / _kAmbientVisibleFraction;
    return -0.1 + local * 1.2;
  }
}

/// Single band overlay. Takes care of its own gradient + shader. The
/// profile + seed decide tilt, palette, width, and noise-modulated
/// wobble. Tier-driven degradation is injected via `desaturation`
/// (drains colour as intensity rises), `jitterAmp` (high-frequency
/// alpha noise on the peak), and `alphaScale` (used by the echo band
/// to render at half strength).
class _SheenBandLayer extends StatelessWidget {
  final String text;
  final TextStyle overlayStyle;
  final TextOverflow overflow;
  final double center;
  final _SheenProfile profile;
  final int bandIndex;
  final int sweepSeed;
  final double bandPhase; // [0, visibleFraction]

  /// HSL-saturation drain in `[0, 1]`. 0 = theme's full vibrance,
  /// 1 = grayscale. Higher tiers push this up so the sheen reads as
  /// losing colour along with coherence.
  final double desaturation;

  /// Amplitude of high-frequency alpha jitter on the peak. 0 = clean
  /// bell envelope; tier 2+ injects noise here so the peak flickers
  /// instead of gliding. Reads as signal instability.
  final double jitterAmp;

  /// Multiplicative scale on the entire band alpha envelope. Used
  /// by tier 3's shadow echo to render at half strength.
  final double alphaScale;

  const _SheenBandLayer({
    required this.text,
    required this.overlayStyle,
    required this.overflow,
    required this.center,
    required this.profile,
    required this.bandIndex,
    required this.sweepSeed,
    required this.bandPhase,
    this.desaturation = 0.0,
    this.jitterAmp = 0.0,
    this.alphaScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Noise wobble — cheap sum of three incommensurate sines. The
    // result drifts smoothly in ~[-1, 1] with no visible period, so
    // per-sweep modulation never feels like a loop. Per-archetype
    // amplitude: crystalline gets almost none (uniform surface);
    // GOE gets more (the surface is rougher).
    final tNorm = bandPhase / _kAmbientVisibleFraction;
    final noiseW = _noise(tNorm, sweepSeed + 0.3) * profile.noiseAmp;
    final noiseHue = _noise(tNorm, sweepSeed + 1.7) * profile.noiseAmp;

    // Width: base + intensity scale + noise wobble.
    final baseHalfWidth = profile.baseWidthFor(bandIndex);
    final halfWidth =
        (baseHalfWidth + 0.03 * noiseW).clamp(0.03, 0.28).toDouble();

    // Alpha envelope: rise and fall across the sweep window so the
    // band fades in on arrival and out on exit instead of hard-cut.
    //   envelope(0) = 0,  envelope(0.5) = 1,  envelope(1) = 0
    final envelope = math.sin(math.pi * tNorm.clamp(0.0, 1.0)).toDouble();
    // Jitter factor: tier 2+ multiplies a high-frequency noise into
    // the alpha. The noise is fast (phase-scaled ×6) so the eye
    // reads it as instability, not wobble. `1 - jitterAmp * |noise|`
    // only dips the alpha — never boosts it — so jitter drains the
    // band rather than making it prettier.
    final jitterNoise = jitterAmp > 0
        ? _noise(tNorm * 6.0, sweepSeed + 101.0).abs()
        : 0.0;
    final jitterFactor =
        (1.0 - jitterAmp * jitterNoise).clamp(0.0, 1.0).toDouble();
    final centerAlpha =
        (profile.centerAlpha * envelope * alphaScale * jitterFactor)
            .clamp(0.0, 1.0)
            .toDouble();
    final edgeAlpha =
        (profile.edgeAlpha * envelope * alphaScale * jitterFactor)
            .clamp(0.0, 1.0)
            .toDouble();

    // Gradient stop positions with forced monotonicity.
    final outer = halfWidth;
    final inner = halfWidth * 0.45;
    double clamp01(double x) => x.clamp(0.0, 1.0).toDouble();
    final stops = <double>[
      0.0,
      clamp01(center - outer),
      clamp01(center - inner),
      clamp01(center),
      clamp01(center + inner),
      clamp01(center + outer),
      1.0,
    ];
    for (var i = 1; i < stops.length; i++) {
      if (stops[i] <= stops[i - 1]) {
        stops[i] = (stops[i - 1] + 1e-6).clamp(0.0, 1.0).toDouble();
      }
    }

    final palette = profile.paletteForBand(bandIndex, hueShift: noiseHue);
    // Drain the chromatic fringes toward grayscale by the tier's
    // desaturation factor. The PEAK (theme core) is NOT desaturated
    // here — the repo's own radiant colour stays legible even as
    // the fringes go dull. What the eye picks up: the chromatic
    // aura is dying while the core still glows faintly through it.
    final approach = _desaturate(palette.approach, desaturation);
    final innerApproach = _desaturate(palette.innerApproach, desaturation);
    final innerExit = _desaturate(palette.innerExit, desaturation);
    final exit = _desaturate(palette.exit, desaturation);
    final colors = <Color>[
      const Color(0x00000000),
      approach.withValues(alpha: edgeAlpha * 0.35),
      innerApproach.withValues(alpha: edgeAlpha),
      palette.peak.withValues(alpha: centerAlpha),
      innerExit.withValues(alpha: edgeAlpha),
      exit.withValues(alpha: edgeAlpha * 0.35),
      const Color(0x00000000),
    ];

    // Tilt — base archetype tilt + a per-sweep jitter scaled by the
    // archetype's noise amplitude. Crystalline surfaces barely
    // wobble; chaotic ones get visibly turbulent tilt. Still bounded
    // (±~5°) so text never looks "twisted."
    final tiltDeg = profile.tiltDeg +
        3.0 * profile.noiseAmp * _noise(tNorm * 0.6, sweepSeed + 4.1);
    final tiltRad = tiltDeg * math.pi / 180.0;
    final begin = Alignment(-math.cos(tiltRad), -math.sin(tiltRad));
    final end = Alignment(math.cos(tiltRad), math.sin(tiltRad));

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: begin,
        end: end,
        colors: colors,
        stops: stops,
      ).createShader(bounds),
      child: Text(
        text,
        style: overlayStyle,
        overflow: overflow,
        maxLines: 1,
      ),
    );
  }
}

// ── Refresh sheen — convergent gesture ────────────────────────────
//
// Structurally distinct from the ambient sweep. Three phases:
//   0.00–0.40  two bands converge inward from both edges
//   0.40–0.55  they meet at centre; brightness spikes
//   0.55–1.00  bands dissolve outward as chromatic fringes
//
// Reads as "synchronising" — information collapsing to the present,
// then dispersing as the user's mental state catches up.

class _RefreshSheenStack extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final TextStyle overlayStyle;
  final TextOverflow overflow;
  final double phase;
  final Color chroma1;
  final Color chroma2;
  final Color core;

  const _RefreshSheenStack({
    required this.text,
    required this.baseStyle,
    required this.overlayStyle,
    required this.overflow,
    required this.phase,
    required this.chroma1,
    required this.chroma2,
    required this.core,
  });

  @override
  Widget build(BuildContext context) {
    final baseText = Text(
      text,
      style: baseStyle,
      overflow: overflow,
      maxLines: 1,
    );

    // Three phases.
    const tConverge = 0.40;
    const tFlash = 0.55;
    final double leftCenter;
    final double rightCenter;
    final double halfWidth;
    final double centerAlpha;
    final double edgeAlpha;
    final double midBurstAlpha;

    if (phase < tConverge) {
      // Phase A — approach. Left band travels -0.1 → 0.5,
      // right band travels 1.1 → 0.5. Both have moderate width.
      final p = phase / tConverge;
      leftCenter = -0.1 + p * 0.6;
      rightCenter = 1.1 - p * 0.6;
      halfWidth = 0.14;
      centerAlpha = 0.9;
      edgeAlpha = 0.60;
      midBurstAlpha = 0.0;
    } else if (phase < tFlash) {
      // Phase B — meeting point. Bands converge to the same centre,
      // brightness spikes, a brief centre burst lights the whole
      // word.
      final p = (phase - tConverge) / (tFlash - tConverge);
      leftCenter = 0.5 - 0.02 * (1.0 - p);
      rightCenter = 0.5 + 0.02 * (1.0 - p);
      halfWidth = 0.14 + 0.06 * p;
      centerAlpha = 1.0;
      edgeAlpha = 0.75;
      // Burst ramps up then holds briefly.
      midBurstAlpha = 0.55 * math.sin(math.pi * p).clamp(0.0, 1.0);
    } else {
      // Phase C — dispersion. The single centre band expands outward
      // and fades as chromatic fringes, like thin-film interference
      // loosening its grip.
      final p = (phase - tFlash) / (1.0 - tFlash);
      // Centre stays put, but width grows and alpha falls.
      leftCenter = 0.5 - 0.08 * p;
      rightCenter = 0.5 + 0.08 * p;
      halfWidth = (0.20 + 0.28 * p).clamp(0.0, 0.5).toDouble();
      centerAlpha = (1.0 - p).clamp(0.0, 1.0).toDouble() * 0.8;
      edgeAlpha = (1.0 - p * 0.7).clamp(0.0, 1.0).toDouble() * 0.65;
      midBurstAlpha = 0.0;
    }

    final layers = <Widget>[baseText];

    // Mid-burst layer during phase B — uniformly illuminates the word
    // for a ~70ms window. Gives the convergence its "click" moment.
    // Painted with the theme's radiant core so the flash wears the
    // theme's own light instead of a neutral white.
    if (midBurstAlpha > 0.01) {
      layers.add(Positioned.fill(
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              core.withValues(alpha: midBurstAlpha),
              core.withValues(alpha: midBurstAlpha),
            ],
          ).createShader(bounds),
          child: Text(
            text,
            style: overlayStyle,
            overflow: overflow,
            maxLines: 1,
          ),
        ),
      ));
    }

    layers.add(Positioned.fill(
      child: _RefreshBandLayer(
        text: text,
        overlayStyle: overlayStyle,
        overflow: overflow,
        center: leftCenter,
        halfWidth: halfWidth,
        peakAlpha: centerAlpha,
        edgeAlpha: edgeAlpha,
        // Left band leads with the theme's cooler chromatic.
        chromaApproach: chroma1,
        chromaExit: chroma2,
        peak: core,
      ),
    ));
    layers.add(Positioned.fill(
      child: _RefreshBandLayer(
        text: text,
        overlayStyle: overlayStyle,
        overflow: overflow,
        center: rightCenter,
        halfWidth: halfWidth,
        peakAlpha: centerAlpha,
        edgeAlpha: edgeAlpha,
        // Right band leads with the warmer chromatic (mirror palette).
        chromaApproach: chroma2,
        chromaExit: chroma1,
        peak: core,
      ),
    ));

    return Stack(children: layers);
  }
}

class _RefreshBandLayer extends StatelessWidget {
  final String text;
  final TextStyle overlayStyle;
  final TextOverflow overflow;
  final double center;
  final double halfWidth;
  final double peakAlpha;
  final double edgeAlpha;
  final Color chromaApproach;
  final Color chromaExit;

  /// Peak colour at the band's brightest point. Theme-owned — the
  /// caller passes `hyperCore` so the flash matches the title's
  /// colour identity instead of defaulting to neutral white.
  final Color peak;

  const _RefreshBandLayer({
    required this.text,
    required this.overlayStyle,
    required this.overflow,
    required this.center,
    required this.halfWidth,
    required this.peakAlpha,
    required this.edgeAlpha,
    required this.chromaApproach,
    required this.chromaExit,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final outer = halfWidth;
    final inner = halfWidth * 0.45;
    double clamp01(double x) => x.clamp(0.0, 1.0).toDouble();
    final stops = <double>[
      0.0,
      clamp01(center - outer),
      clamp01(center - inner),
      clamp01(center),
      clamp01(center + inner),
      clamp01(center + outer),
      1.0,
    ];
    for (var i = 1; i < stops.length; i++) {
      if (stops[i] <= stops[i - 1]) {
        stops[i] = (stops[i - 1] + 1e-6).clamp(0.0, 1.0).toDouble();
      }
    }
    final colors = <Color>[
      const Color(0x00000000),
      chromaApproach.withValues(alpha: edgeAlpha * 0.35),
      chromaApproach.withValues(alpha: edgeAlpha),
      peak.withValues(alpha: peakAlpha),
      chromaExit.withValues(alpha: edgeAlpha),
      chromaExit.withValues(alpha: edgeAlpha * 0.35),
      const Color(0x00000000),
    ];
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
        stops: stops,
      ).createShader(bounds),
      child: Text(
        text,
        style: overlayStyle,
        overflow: overflow,
        maxLines: 1,
      ),
    );
  }
}

// ── Profile derivation ────────────────────────────────────────────

/// Visual parameters derived from universality + intensity. Each
/// archetype has a distinct "feel" because its spectrum genuinely
/// differs — crystalline codebases get tight, ordered bands; chaotic
/// ones get broader, turbulent sweeps.
///
/// The profile covers BOTH the visual geometry (band count, width,
/// tilt, palette) AND the temporal character (period, noise
/// amplitude). Visual geometry makes the sheen LOOK different per
/// repo; temporal character makes it FEEL different — a crystalline
/// repo breathes slowly and steadily, a chaotic one is quicker and
/// more turbulent. No glyph or label tells you which; you just
/// perceive the repo's nature through how its light moves.
///
/// Every colour comes from the theme — `chroma1`/`chroma2` are the
/// theme's cool-chromatic fringe colours (cyan/magenta in most
/// themes, rose/lavender in others); `core` is the theme's radiant
/// peak tone (amber, honey, ivory — whatever the theme names as its
/// centre-of-light). No hardcoded whites anywhere in the sheen;
/// every pixel is paint the theme chose.
class _SheenProfile {
  final int bandCount;
  final double baseWidth;
  final double tiltDeg;
  final double centerAlpha;
  final double edgeAlpha;
  final Color chroma1;
  final Color chroma2;
  final Color core;

  /// Multiplier on the ambient cycle period. `<1.0` = faster;
  /// `>1.0` = slower. Applied to [_kAmbientPeriodBase] in the
  /// controller's duration so archetypes breathe at different rates.
  final double periodScale;

  /// Amplitude of per-sweep noise modulation. Scales the `_noise`
  /// function's output before it modulates tilt, width, and hue.
  /// `<1.0` = calmer (the surface is uniform); `>1.0` = more
  /// turbulent (irregular reflections as light catches a rough
  /// surface).
  final double noiseAmp;

  const _SheenProfile({
    required this.bandCount,
    required this.baseWidth,
    required this.tiltDeg,
    required this.centerAlpha,
    required this.edgeAlpha,
    required this.chroma1,
    required this.chroma2,
    required this.core,
    this.periodScale = 1.0,
    this.noiseAmp = 1.0,
  });

  factory _SheenProfile.fromContext({
    required UniversalityVector? universality,
    required double intensity,
    required Color chroma1,
    required Color chroma2,
    required Color core,
  }) {
    // Intensity drives overall alpha envelope across every profile.
    final centerAlphaBase =
        (0.35 + 0.65 * intensity).clamp(0.30, 1.0).toDouble();
    final edgeAlphaBase =
        (0.15 + 0.55 * intensity).clamp(0.08, 0.85).toDouble();

    // No universality signal yet — use the neutral template as-is.
    if (universality == null) {
      return _buildProfileFrom(
        template: _neutralTemplate,
        bandCount: _neutralTemplate.bandCount,
        intensity: intensity,
        centerAlphaBase: centerAlphaBase,
        edgeAlphaBase: edgeAlphaBase,
        chroma1: chroma1,
        chroma2: chroma2,
        core: core,
      );
    }

    // Blended archetype mix. A repo at the edge between crystalline
    // and poisson renders as a hybrid whose tilt, period, and
    // chromatic wobble sit between the two — it doesn't snap to the
    // winner. The continuous params are weighted sums; bandCount
    // can't blend (discrete count) so it tracks the dominant
    // archetype alone.
    final weights = _archetypeWeights(universality);

    var bWidth = 0.0;
    var bTilt = 0.0;
    var bCenterBias = 0.0;
    var bEdgeMult = 0.0;
    var bPeriod = 0.0;
    var bNoise = 0.0;
    var dominant = 'poisson';
    var topWeight = -1.0;
    weights.forEach((name, w) {
      final t = _archetypeTemplates[name]!;
      // Width is clamped PER-archetype before blending so each class
      // contributes at its own visually-sane scale. A crystalline
      // partner can't push the blended width past its own 0.18 cap.
      final perArchetypeWidth = (t.widthA + t.widthB * intensity)
          .clamp(t.widthMin, t.widthMax)
          .toDouble();
      bWidth += w * perArchetypeWidth;
      bTilt += w * t.tiltDeg;
      bCenterBias += w * t.centerAlphaBias;
      bEdgeMult += w * t.edgeAlphaMult;
      bPeriod += w * t.periodScale;
      bNoise += w * t.noiseAmp;
      if (w > topWeight) {
        topWeight = w;
        dominant = name;
      }
    });
    final bandCount = _archetypeTemplates[dominant]!.bandCount;

    return _SheenProfile(
      bandCount: bandCount,
      baseWidth: bWidth,
      tiltDeg: bTilt,
      centerAlpha:
          (centerAlphaBase + bCenterBias).clamp(0.0, 1.0).toDouble(),
      edgeAlpha: (edgeAlphaBase * bEdgeMult).clamp(0.0, 1.0).toDouble(),
      chroma1: chroma1,
      chroma2: chroma2,
      core: core,
      periodScale: bPeriod,
      noiseAmp: bNoise,
    );
  }

  /// Build a profile from a single archetype template — used for the
  /// neutral / unknown-universality path. The blended path skips this
  /// and composes scalars directly.
  static _SheenProfile _buildProfileFrom({
    required _ArchetypeTemplate template,
    required int bandCount,
    required double intensity,
    required double centerAlphaBase,
    required double edgeAlphaBase,
    required Color chroma1,
    required Color chroma2,
    required Color core,
  }) {
    final width = (template.widthA + template.widthB * intensity)
        .clamp(template.widthMin, template.widthMax)
        .toDouble();
    return _SheenProfile(
      bandCount: bandCount,
      baseWidth: width,
      tiltDeg: template.tiltDeg,
      centerAlpha: (centerAlphaBase + template.centerAlphaBias)
          .clamp(0.0, 1.0)
          .toDouble(),
      edgeAlpha: (edgeAlphaBase * template.edgeAlphaMult)
          .clamp(0.0, 1.0)
          .toDouble(),
      chroma1: chroma1,
      chroma2: chroma2,
      core: core,
      periodScale: template.periodScale,
      noiseAmp: template.noiseAmp,
    );
  }

  /// Per-band phase offset in `[0, 1]` — bands are spaced evenly
  /// across the ambient cycle so they don't all hit at once. The
  /// offsets are small enough that multiple bands still appear in
  /// the same sweep window.
  double bandPhaseOffset(int bandIndex) {
    if (bandCount <= 1) return 0.0;
    // Spread bands across ~60% of the visible fraction — enough
    // separation to read as multiple, not enough to feel "scattered."
    const spread = 0.08;
    return bandIndex * (spread / (bandCount - 1).clamp(1, 1000));
  }

  /// Per-band base width — slightly narrower for bands at the back
  /// of the stack, reinforcing the parallax/depth cue.
  double baseWidthFor(int bandIndex) {
    if (bandCount <= 1) return baseWidth;
    final taper = 1.0 - 0.15 * bandIndex;
    return (baseWidth * taper).clamp(0.03, 0.28).toDouble();
  }

  /// Palette for a specific band with an optional hue rotation.
  /// Bands further back in the stack get muted hues and the stack
  /// reads as layered.
  _BandPalette paletteForBand(int bandIndex, {double hueShift = 0.0}) {
    // hueShift ∈ [-1, 1]. Positive shifts rotate toward chroma1's
    // complement; negative toward chroma2's. The effect is gentle —
    // the tokens already carry the core colour identity.
    final mix = (0.5 + 0.35 * hueShift).clamp(0.0, 1.0).toDouble();
    final approach = Color.lerp(chroma1, chroma2, mix * 0.2) ?? chroma1;
    final exit = Color.lerp(chroma2, chroma1, mix * 0.2) ?? chroma2;
    final innerApproach = approach;
    final innerExit = exit;
    // Back layers get a hint of muting.
    final muteFactor = 1.0 - 0.2 * bandIndex;
    Color mute(Color c) =>
        c.withValues(alpha: (c.a * muteFactor).clamp(0.0, 1.0).toDouble());
    return _BandPalette(
      approach: mute(approach),
      innerApproach: mute(innerApproach),
      // Peak comes from the theme's radiant core. Warm themes get an
      // amber/honey peak; cool ones get ivory; the sheen always wears
      // the theme's own luminous identity instead of a neutral white.
      peak: core,
      innerExit: mute(innerExit),
      exit: mute(exit),
    );
  }
}

class _BandPalette {
  final Color approach;
  final Color innerApproach;
  final Color peak;
  final Color innerExit;
  final Color exit;

  const _BandPalette({
    required this.approach,
    required this.innerApproach,
    required this.peak,
    required this.innerExit,
    required this.exit,
  });
}

/// Discrete severity tier for the sheen overlay. Thresholds are
/// NOT arbitrary — they mirror the canonical `repoHealth` classifier
/// in `logos_free_energy.dart`, which declared the meaningful cut-
/// points at `0.30 / 0.45 / 0.55` on the upper-half-spectrum fraction.
/// That function and `repoAnomalyLevel` both compute the same scalar
/// (upper-half F mass / total F mass), so a tier here means exactly
/// what the backend means by stable / drifting / anomalous / critical.
///
/// A sheen is fundamentally a positive animation — shimmer, light,
/// beauty. To make it convey NEGATIVE state (rising anomaly) without
/// abandoning the medium, we don't enhance it as intensity climbs —
/// we let it lose coherence. Colours desaturate. Smooth alpha gains
/// jitter. Reflections stop being twin-bright and start reading as
/// grey shadows. The light is losing its life.
///
/// Tiers compound: each rung adds a distinct degradation signal on
/// top of the previous. Archetype (shape / palette / tempo) stays
/// orthogonal — a crystalline repo at critical is still crystalline-
/// shaped, just heavily drained.
///
///   0 (silent):    < 0.001  — no signal
///   1 (stable):    < 0.30   — base sweep; mild attention cue
///   2 (drifting):  < 0.45   — + alpha jitter; signal gets unsteady
///   3 (anomalous): < 0.55   — + shadow echo (narrow transitional band)
///   4 (critical):  ≥ 0.55   — + dissonant undertow; phase transition
///
/// The anomalous band (0.45–0.55) is deliberately narrow — it's the
/// transitional state between "concerning" and "phase transition."
/// 0.47 sits right in its middle, which is why that number feels
/// like a "prime" threshold — it's the midpoint of the regime.
int _sheenTier(double intensity) {
  if (intensity < 0.001) return 0;
  if (intensity < 0.30) return 1;
  if (intensity < 0.45) return 2;
  if (intensity < 0.55) return 3;
  return 4;
}

/// Per-tier desaturation factor in `[0, 1]`. Zero keeps the theme's
/// full chromatic vibrance; 1 collapses to grayscale. The curve is
/// non-linear — vibrance falls gently through the middle tiers, then
/// drains more aggressively at the top. Reads as: "the light loses
/// its colour as the repo loses coherence."
double _tierDegradation(int tier) {
  switch (tier) {
    case 0:
      return 0.0;
    case 1:
      return 0.08;
    case 2:
      return 0.28;
    case 3:
      return 0.55;
    case 4:
      return 0.78;
    default:
      return 0.0;
  }
}

/// Desaturate `c` by `amount` in `[0, 1]` via HSL. `amount = 0`
/// returns the colour unchanged; `amount = 1` collapses it to
/// grayscale. Preserves alpha and lightness.
Color _desaturate(Color c, double amount) {
  if (amount <= 0.0) return c;
  final clamped = amount.clamp(0.0, 1.0);
  final hsl = HSLColor.fromColor(c);
  final s = (hsl.saturation * (1.0 - clamped)).clamp(0.0, 1.0).toDouble();
  return hsl.withSaturation(s).toColor();
}

// ── Archetype templates ──────────────────────────────────────────
//
// Per-archetype sheen parameters. Each archetype's visual / temporal
// signature is a point in a small scalar space (width, tilt, period,
// noise, alpha bias). The blended profile takes a weighted sum over
// these templates — a repo at the edge between two archetypes
// renders as a hybrid whose light moves between them, not one that
// snaps to whichever distance happens to be 0.001 smaller.

class _ArchetypeTemplate {
  /// How many parallel sheen bands sweep the text. Orders the
  /// visual density: crystalline is a single clean glide; GOE runs
  /// three layered bands for a turbulent, parallax-separated feel.
  final int bandCount;

  /// Width equation is `(widthA + widthB * intensity)` then clamped
  /// to `[widthMin, widthMax]`. Each archetype's clamp range reflects
  /// its visual register: crystalline stays narrow, tree spans wide.
  final double widthA;
  final double widthB;
  final double widthMin;
  final double widthMax;

  /// Per-archetype tilt of the band gradient (degrees). Signed so
  /// archetype pairs with opposing tilts (modular vs. poisson) can
  /// cancel toward 0° when blended near-equally.
  final double tiltDeg;

  /// Offset added to the intensity-driven centre alpha. GOE nudges
  /// up (+), tree nudges down (−) — the repo's *character* tips the
  /// band's core brightness even at the same overall intensity.
  final double centerAlphaBias;

  /// Multiplier on the intensity-driven edge alpha. Tree's gentle
  /// 1.1 reads as a long fade; poisson's 0.9 crops the fringes
  /// harder for a more contained glide.
  final double edgeAlphaMult;

  /// Multiplier on the ambient cycle period. `<1.0` faster (chaos),
  /// `>1.0` slower (coherent, tidal).
  final double periodScale;

  /// Per-sweep noise amplitude. Crystalline is almost still; GOE
  /// glints and flickers.
  final double noiseAmp;

  const _ArchetypeTemplate({
    required this.bandCount,
    required this.widthA,
    required this.widthB,
    required this.widthMin,
    required this.widthMax,
    required this.tiltDeg,
    required this.centerAlphaBias,
    required this.edgeAlphaMult,
    required this.periodScale,
    required this.noiseAmp,
  });
}

/// Crystalline — ordered, geometric. One tight band, minimal tilt.
/// Breathes slowly and cleanly: the surface is uniform, so light
/// glides instead of flickering.
const _crystallineTemplate = _ArchetypeTemplate(
  bandCount: 1,
  widthA: 0.06,
  widthB: 0.08,
  widthMin: 0.04,
  widthMax: 0.18,
  tiltDeg: 0.0,
  centerAlphaBias: 0.0,
  edgeAlphaMult: 1.0,
  periodScale: 1.25,
  noiseAmp: 0.35,
);

/// Poisson — independent levels. Two bands, moderate tilt, default
/// pace with gentle wobble.
const _poissonTemplate = _ArchetypeTemplate(
  bandCount: 2,
  widthA: 0.08,
  widthB: 0.09,
  widthMin: 0.05,
  widthMax: 0.20,
  tiltDeg: 4.0,
  centerAlphaBias: 0.0,
  edgeAlphaMult: 0.9,
  periodScale: 1.0,
  noiseAmp: 0.9,
);

/// GOE — chaotic structured. Three bands, wider, larger tilt.
/// Quicker, more turbulent — the repo is restless, and the light
/// picks that up.
const _goeTemplate = _ArchetypeTemplate(
  bandCount: 3,
  widthA: 0.09,
  widthB: 0.12,
  widthMin: 0.06,
  widthMax: 0.24,
  tiltDeg: 7.0,
  centerAlphaBias: 0.05,
  edgeAlphaMult: 1.0,
  periodScale: 0.70,
  noiseAmp: 1.6,
);

/// Tree — dendritic / dominated. One wide band with long fade; very
/// slow, very smooth. A single dominant mode isn't in a hurry.
const _treeTemplate = _ArchetypeTemplate(
  bandCount: 1,
  widthA: 0.12,
  widthB: 0.13,
  widthMin: 0.08,
  widthMax: 0.28,
  tiltDeg: 2.0,
  centerAlphaBias: -0.05,
  edgeAlphaMult: 1.1,
  periodScale: 1.45,
  noiseAmp: 0.5,
);

/// Bulk — dense, multi-dimensional. Two diffuse bands; medium-fast
/// with moderate wobble as many modes contribute.
const _bulkTemplate = _ArchetypeTemplate(
  bandCount: 2,
  widthA: 0.10,
  widthB: 0.10,
  widthMin: 0.06,
  widthMax: 0.22,
  tiltDeg: 3.0,
  centerAlphaBias: 0.0,
  edgeAlphaMult: 1.05,
  periodScale: 0.85,
  noiseAmp: 1.1,
);

/// Modular — clustered. Two bands that almost cross, mirrored
/// palette via its negative tilt. Slightly quicker than default.
const _modularTemplate = _ArchetypeTemplate(
  bandCount: 2,
  widthA: 0.07,
  widthB: 0.10,
  widthMin: 0.05,
  widthMax: 0.20,
  tiltDeg: -5.0,
  centerAlphaBias: 0.0,
  edgeAlphaMult: 1.0,
  periodScale: 0.95,
  noiseAmp: 1.0,
);

/// Neutral — used before any universality signal arrives. Matches
/// the pre-blend default profile.
const _neutralTemplate = _ArchetypeTemplate(
  bandCount: 1,
  widthA: 0.07,
  widthB: 0.11,
  widthMin: 0.04,
  widthMax: 0.22,
  tiltDeg: 0.0,
  centerAlphaBias: 0.0,
  edgeAlphaMult: 1.0,
  periodScale: 1.0,
  noiseAmp: 1.0,
);

const Map<String, _ArchetypeTemplate> _archetypeTemplates = {
  'crystalline': _crystallineTemplate,
  'poisson': _poissonTemplate,
  'goe': _goeTemplate,
  'tree': _treeTemplate,
  'bulk': _bulkTemplate,
  'modular': _modularTemplate,
};

/// Archetype mixing weights. Closer archetypes (smaller distance)
/// carry larger weight, with `(1 − d)^2` sharpening so a clear
/// match still dominates the blend. Two archetypes tied for
/// nearest produce a near-50/50 mix; a single dominant archetype
/// with all others distant approaches 100% weight for itself.
///
/// Returns a map keyed by archetype name (same six keys as
/// `_archetypeTemplates`), summing to 1. If every distance is at
/// its cap of 1.0, falls back to a uniform mix — the profile then
/// reads as a neutral average of every archetype simultaneously,
/// which is visually mild and correctly conveys "no clear class."
Map<String, double> _archetypeWeights(UniversalityVector u) {
  double w(double d) {
    final x = (1.0 - d).clamp(0.0, 1.0).toDouble();
    return x * x;
  }
  final raw = <String, double>{
    'crystalline': w(u.toCrystalline),
    'poisson': w(u.toPoisson),
    'goe': w(u.toGoe),
    'tree': w(u.toTree),
    'bulk': w(u.toBulk),
    'modular': w(u.toModular),
  };
  final sum = raw.values.fold<double>(0.0, (a, b) => a + b);
  if (sum <= 1e-9) {
    final n = raw.length.toDouble();
    return {for (final k in raw.keys) k: 1.0 / n};
  }
  return raw.map((k, v) => MapEntry(k, v / sum));
}

/// Smooth pseudo-random modulator. Sum of three incommensurate sines
/// at different frequencies gives a signal that drifts in ~[-1, 1]
/// with no visible period. Cheap: 3 sines + 2 adds per call.
///
/// `t` is the normalised time in `[0, 1]`; `seed` deterministically
/// shifts the phase so different (sweep, band) pairs produce
/// different signals.
double _noise(double t, double seed) {
  final r = (math.sin(t * 2.1 * math.pi + seed * 0.71) +
          math.sin(t * 3.7 * math.pi + seed * 1.37) * 0.55 +
          math.sin(t * 5.3 * math.pi + seed * 2.13) * 0.30) /
      1.85;
  return r.clamp(-1.0, 1.0).toDouble();
}
