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
        _nearestArchetype(old.universality) !=
            _nearestArchetype(widget.universality)) {
      _syncTickers();
    }
  }

  /// Archetype name for controller-rebuild comparison. Null-safe.
  String? _nearestArchetype(UniversalityVector? u) =>
      u?.nearest.name;

  void _syncTickers() {
    final intensity = _clampedIntensity();
    final motionRate = context.motionRate;
    final motionActive = motionRate > 0.05;
    final rate = motionRate.clamp(0.1, 2.0);

    // Resolve the archetype's desired period once per sync. Pure
    // function of universality → small switch in _SheenProfile.
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

  /// Archetype-keyed period scale. Kept inline so the tickers can
  /// read it without constructing a full [_SheenProfile] (which
  /// needs token lookups we don't have during state-level logic).
  double _periodScaleFor(UniversalityVector? u) {
    if (u == null) return 1.0;
    switch (u.nearest.name) {
      case 'crystalline':
        return 1.25;
      case 'goe':
        return 0.70;
      case 'tree':
        return 1.45;
      case 'bulk':
        return 0.85;
      case 'modular':
        return 0.95;
      case 'poisson':
      default:
        return 1.0;
    }
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

  const _AmbientSheenStack({
    required this.text,
    required this.baseStyle,
    required this.overlayStyle,
    required this.overflow,
    required this.phase,
    required this.sweepSeed,
    required this.profile,
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
    // phase offset, colour shift, and width jitter.
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
      );
      layers.add(Positioned.fill(child: layer));
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
/// wobble.
class _SheenBandLayer extends StatelessWidget {
  final String text;
  final TextStyle overlayStyle;
  final TextOverflow overflow;
  final double center;
  final _SheenProfile profile;
  final int bandIndex;
  final int sweepSeed;
  final double bandPhase; // [0, visibleFraction]

  const _SheenBandLayer({
    required this.text,
    required this.overlayStyle,
    required this.overflow,
    required this.center,
    required this.profile,
    required this.bandIndex,
    required this.sweepSeed,
    required this.bandPhase,
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
    final centerAlpha = (profile.centerAlpha * envelope)
        .clamp(0.0, 1.0)
        .toDouble();
    final edgeAlpha = (profile.edgeAlpha * envelope)
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
    final colors = <Color>[
      const Color(0x00000000),
      palette.approach.withValues(alpha: edgeAlpha * 0.35),
      palette.innerApproach.withValues(alpha: edgeAlpha),
      palette.peak.withValues(alpha: centerAlpha),
      palette.innerExit.withValues(alpha: edgeAlpha),
      palette.exit.withValues(alpha: edgeAlpha * 0.35),
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

  const _RefreshSheenStack({
    required this.text,
    required this.baseStyle,
    required this.overlayStyle,
    required this.overflow,
    required this.phase,
    required this.chroma1,
    required this.chroma2,
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
    if (midBurstAlpha > 0.01) {
      layers.add(Positioned.fill(
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: midBurstAlpha),
              Colors.white.withValues(alpha: midBurstAlpha),
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
        // Left band leads with cyan.
        chromaApproach: chroma1,
        chromaExit: chroma2,
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
        // Right band leads with magenta (mirror palette).
        chromaApproach: chroma2,
        chromaExit: chroma1,
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
      Colors.white.withValues(alpha: peakAlpha),
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
class _SheenProfile {
  final int bandCount;
  final double baseWidth;
  final double tiltDeg;
  final double centerAlpha;
  final double edgeAlpha;
  final Color chroma1;
  final Color chroma2;

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
    this.periodScale = 1.0,
    this.noiseAmp = 1.0,
  });

  factory _SheenProfile.fromContext({
    required UniversalityVector? universality,
    required double intensity,
    required Color chroma1,
    required Color chroma2,
  }) {
    // Intensity drives overall alpha envelope across every profile.
    final centerAlpha = (0.35 + 0.65 * intensity).clamp(0.30, 1.0).toDouble();
    final edgeAlpha = (0.15 + 0.55 * intensity).clamp(0.08, 0.85).toDouble();

    // Default / unknown profile — neutral single band.
    if (universality == null) {
      final width = (0.07 + 0.11 * intensity).clamp(0.04, 0.22).toDouble();
      return _SheenProfile(
        bandCount: 1,
        baseWidth: width,
        tiltDeg: 0.0,
        centerAlpha: centerAlpha,
        edgeAlpha: edgeAlpha,
        chroma1: chroma1,
        chroma2: chroma2,
      );
    }

    switch (universality.nearest.name) {
      case 'crystalline':
        // Ordered, geometric — one tight band, minimal tilt.
        // Breathes SLOWLY and cleanly — the surface is uniform, so
        // light doesn't flicker; it glides.
        return _SheenProfile(
          bandCount: 1,
          baseWidth:
              (0.06 + 0.08 * intensity).clamp(0.04, 0.18).toDouble(),
          tiltDeg: 0.0,
          centerAlpha: centerAlpha,
          edgeAlpha: edgeAlpha,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 1.25,
          noiseAmp: 0.35,
        );
      case 'poisson':
        // Independent levels — two bands, offset, moderate tilt.
        // Default pace with gentle wobble.
        return _SheenProfile(
          bandCount: 2,
          baseWidth:
              (0.08 + 0.09 * intensity).clamp(0.05, 0.20).toDouble(),
          tiltDeg: 4.0,
          centerAlpha: centerAlpha,
          edgeAlpha: edgeAlpha * 0.9,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 1.0,
          noiseAmp: 0.9,
        );
      case 'goe':
        // Chaotic structured — three bands, wider, larger tilt.
        // QUICKER pace, MORE turbulence. The repo is restless; the
        // light picks it up.
        return _SheenProfile(
          bandCount: 3,
          baseWidth:
              (0.09 + 0.12 * intensity).clamp(0.06, 0.24).toDouble(),
          tiltDeg: 7.0,
          centerAlpha: (centerAlpha + 0.05).clamp(0.0, 1.0).toDouble(),
          edgeAlpha: edgeAlpha,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 0.70,
          noiseAmp: 1.6,
        );
      case 'tree':
        // Dendritic / dominated — one wide band with long fade.
        // Tidal — very slow, very smooth. A single dominant mode
        // isn't in a hurry.
        return _SheenProfile(
          bandCount: 1,
          baseWidth:
              (0.12 + 0.13 * intensity).clamp(0.08, 0.28).toDouble(),
          tiltDeg: 2.0,
          centerAlpha: (centerAlpha - 0.05).clamp(0.0, 1.0).toDouble(),
          edgeAlpha: edgeAlpha * 1.1,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 1.45,
          noiseAmp: 0.5,
        );
      case 'bulk':
        // Dense, multi-dimensional — two diffuse bands.
        // Medium-fast, moderate wobble — many modes contributing
        // read as a busier surface.
        return _SheenProfile(
          bandCount: 2,
          baseWidth:
              (0.10 + 0.10 * intensity).clamp(0.06, 0.22).toDouble(),
          tiltDeg: 3.0,
          centerAlpha: centerAlpha,
          edgeAlpha: edgeAlpha * 1.05,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 0.85,
          noiseAmp: 1.1,
        );
      case 'modular':
        // Clustered — two bands that almost cross, mirrored palette.
        // Slightly quicker than default; moderate wobble from the
        // cluster structure.
        return _SheenProfile(
          bandCount: 2,
          baseWidth:
              (0.07 + 0.10 * intensity).clamp(0.05, 0.20).toDouble(),
          tiltDeg: -5.0,
          centerAlpha: centerAlpha,
          edgeAlpha: edgeAlpha,
          chroma1: chroma1,
          chroma2: chroma2,
          periodScale: 0.95,
          noiseAmp: 1.0,
        );
      default:
        final width = (0.07 + 0.11 * intensity).clamp(0.04, 0.22).toDouble();
        return _SheenProfile(
          bandCount: 1,
          baseWidth: width,
          tiltDeg: 0.0,
          centerAlpha: centerAlpha,
          edgeAlpha: edgeAlpha,
          chroma1: chroma1,
          chroma2: chroma2,
        );
    }
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
      peak: Colors.white,
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
