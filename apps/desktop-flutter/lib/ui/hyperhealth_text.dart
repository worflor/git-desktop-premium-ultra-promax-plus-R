// HyperhealthText — the repo title's sheen-based F-state visualisation.
//
// Design decisions:
//
// * **No ambient color tint.** Base text colour is exactly what the
//   caller passes — the engine's F state never silently repaints the
//   letters. Colour changes only happen for user-caused events
//   (hover, etc.), which the caller drives by adjusting `baseColor`.
//
// * **Sheen is the one indicator.** When the repo is not perfectly
//   stable, a chromatic swoosh periodically sweeps across the title.
//   Strength and prettiness of the swoosh scale with a continuous
//   `intensity ∈ [0, 1]` — not a discrete state, so subtle anomalies
//   produce a faint sweep and severe ones produce a vivid one.
//
// * **Refresh rides the same mechanism.** When `refreshing` is true
//   (the user clicked to fetch) the widget fires a fast bright sheen
//   on its own. Visually unified with the ambient sheen — same sweep,
//   same chromatic gradient, just faster and peak-intensity.
//
// * **No breathing.** No scale oscillation. No passive color pulse.
//   If the widget looks still, it IS still.
//
// Technique: classic shader-mask shimmer. A LinearGradient with a
// narrow chromatic band (transparent outside, cyan → white → magenta
// inside) is used as a `ShaderMask` with `BlendMode.srcIn` over a text
// widget. The gradient colours tint the text wherever the band
// overlaps; everywhere else the child reads as fully transparent and
// the base text (in a lower Stack layer) shows through.

import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// Period of a single ambient sheen cycle at motion-rate = 1.0. The
/// band is off-screen for most of the cycle — visible only in a short
/// window inside each period. Tuned long so the effect reads as
/// occasional, not constant.
const Duration _kAmbientPeriod = Duration(milliseconds: 9500);

/// Period of a refresh sheen. Fast, deliberate — reads as a "go"
/// gesture tied to the user's click.
const Duration _kRefreshPeriod = Duration(milliseconds: 680);

/// The visible fraction of a cycle during which the band crosses the
/// text (the rest of the cycle is approach/exit off-screen). Ambient
/// sheens use a short window so most of the time is "still"; refresh
/// sheens use the full window to read as a decisive swoosh.
const double _kAmbientVisibleFraction = 0.18;
const double _kRefreshVisibleFraction = 1.0;

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
  /// cadence until `refreshing` flips back to `false`. Composes with
  /// ambient sheen — both can run; whichever is "brighter" wins.
  final bool refreshing;

  /// Overflow for the underlying `Text` widgets.
  final TextOverflow overflow;

  const HyperhealthText({
    super.key,
    required this.text,
    required this.baseColor,
    required this.style,
    this.intensity = 0.0,
    this.refreshing = false,
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
        old.refreshing != widget.refreshing) {
      _syncTickers();
    }
  }

  void _syncTickers() {
    final intensity = _clampedIntensity();
    final motionRate = context.motionRate;
    final motionActive = motionRate > 0.05;
    final rate = motionRate.clamp(0.1, 2.0);

    // Ambient sheen runs continuously while the repo is anomalous.
    final shouldAmbient = intensity > 0.001 && motionActive;
    if (shouldAmbient) {
      _ambient ??= AnimationController(
        vsync: this,
        duration: Duration(
          milliseconds: (_kAmbientPeriod.inMilliseconds / rate).round(),
        ),
      )..repeat();
    } else {
      _ambient?.dispose();
      _ambient = null;
    }

    // Refresh sheen runs while the user has a fetch in flight.
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

  @override
  void dispose() {
    _ambient?.dispose();
    _refresh?.dispose();
    super.dispose();
  }

  /// Compute the sheen band's current x-center and visibility, given a
  /// controller phase `[0, 1]` and the cycle's visible fraction.
  ///
  /// Returns `null` when the band is off-screen (this cycle's sheen
  /// isn't currently visible). Otherwise returns `center ∈ [-0.1, 1.1]`
  /// — slight over-travel so the band fades in/out across the edges.
  double? _bandCenter(double phase, double visibleFraction) {
    if (phase > visibleFraction) return null;
    // Band travels from x = -0.1 (just off-left) to x = 1.1 (just
    // off-right) over the visible window.
    final p = phase / visibleFraction;
    return -0.1 + p * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = widget.style.copyWith(color: widget.baseColor);
    final intensity = _clampedIntensity();

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

    return AnimatedBuilder(
      animation: Listenable.merge([
        if (_ambient != null) _ambient!,
        if (_refresh != null) _refresh!,
      ]),
      builder: (context, _) {
        // Sample both possible sheens. Whichever is currently in its
        // "visible" window and has higher peak brightness wins.
        final ambientCenter = _ambient == null
            ? null
            : _bandCenter(_ambient!.value, _kAmbientVisibleFraction);
        final refreshCenter = _refresh == null
            ? null
            : _bandCenter(_refresh!.value, _kRefreshVisibleFraction);

        final bool refreshingBand = refreshCenter != null;
        final double? bandCenter = refreshingBand ? refreshCenter : ambientCenter;

        if (bandCenter == null) {
          // No band visible this frame — plain text.
          return Text(
            widget.text,
            style: effectiveStyle,
            overflow: widget.overflow,
            maxLines: 1,
          );
        }

        // Band geometry: wider at high intensity / during refresh so the
        // sweep reads as decisive.
        final double halfWidth = refreshingBand
            ? 0.18
            : (0.07 + 0.11 * intensity).clamp(0.04, 0.25).toDouble();

        // Peak alphas:
        //   * `centerAlpha` — how bright the white peak is
        //   * `edgeAlpha`   — how visible the cyan/magenta fringes are
        final double centerAlpha = refreshingBand
            ? 1.0
            : (0.35 + 0.65 * intensity).clamp(0.3, 1.0).toDouble();
        final double edgeAlpha = refreshingBand
            ? 0.70
            : (0.15 + 0.55 * intensity).clamp(0.08, 0.85).toDouble();

        // Gradient stops — 7 stops for a smooth band profile:
        //   [outer-transparent, fringe-cyan, inner-cyan, white-peak,
        //    inner-magenta, fringe-magenta, outer-transparent]
        final double c = bandCenter;
        final double outer = halfWidth;
        final double inner = halfWidth * 0.45;
        double clamp01(double x) => x.clamp(0.0, 1.0).toDouble();
        final stops = <double>[
          0.0,
          clamp01(c - outer),
          clamp01(c - inner),
          clamp01(c),
          clamp01(c + inner),
          clamp01(c + outer),
          1.0,
        ];
        // Degenerate stops — when the band is wholly off-screen the
        // clamp collapses them. Recover by forcing strict monotonicity.
        for (var i = 1; i < stops.length; i++) {
          if (stops[i] <= stops[i - 1]) {
            stops[i] = (stops[i - 1] + 1e-6).clamp(0.0, 1.0).toDouble();
          }
        }

        final chroma1 = tokens.hyperChromatic1.withValues(alpha: edgeAlpha);
        final chroma2 = tokens.hyperChromatic2.withValues(alpha: edgeAlpha);
        final colors = <Color>[
          const Color(0x00000000), // transparent — no sheen outside band
          chroma1.withValues(alpha: edgeAlpha * 0.35), // fringe approach
          chroma1,                                       // inner cyan
          Colors.white.withValues(alpha: centerAlpha),   // peak
          chroma2,                                       // inner magenta
          chroma2.withValues(alpha: edgeAlpha * 0.35),   // fringe fade
          const Color(0x00000000),
        ];

        return Stack(
          children: [
            // Base text — always visible, exactly the caller's colour.
            Text(
              widget.text,
              style: effectiveStyle,
              overflow: widget.overflow,
              maxLines: 1,
            ),
            // Sheen overlay — the band's colours show through the text
            // shape via srcIn; elsewhere the overlay is transparent so
            // the base reads underneath.
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: colors,
                  stops: stops,
                ).createShader(bounds),
                child: Text(
                  widget.text,
                  style: widget.style.copyWith(color: Colors.white),
                  overflow: widget.overflow,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
