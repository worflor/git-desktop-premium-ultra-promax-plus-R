import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/window_activity.dart';
import '../backend/logos_spectrogeometry.dart' show UniversalityVector;
import 'motion.dart';
import 'theme_shaders.dart';
import 'tokens.dart';

/// Ambient thermal presence on the repo name. Per-glyph chromatic tint
/// that shifts from cool (idle) to warm (active) as spectral flux
/// accumulates. Always on — the text quietly breathes with the repo's
/// thermodynamic state.
///
///   - Color → thermal state (cool pole = stable, warm pole = active)
///   - Per-glyph variation → noise at character-width frequency
///   - Gradient drift → Berry phase (irreversible rotation over session)
///   - Breathing → k₀ = 0.27 universal spring constant
///   - Texture → spectral dimension (coherent vs turbulent)
///   - Color POLES → universality class (crystalline = narrow,
///     GOE = wide, tree = biased, modular = sharp)
class EigenmanifoldGlow extends StatefulWidget {
  final Widget child;

  /// Thermal presence in [0, 1]. 0 = cold/idle → cool pole.
  /// 1 = hot/active → warm pole.
  final double temperature;

  /// Spectral gap — controls flow coherence in the shader.
  final double spectralGap;

  /// Spectral dimension — controls noise granularity.
  final double spectralDimension;

  /// Universality classification. When present, the color poles are
  /// modulated by the repo's spectral character: crystalline repos
  /// glow in a narrow monochromatic band, GOE repos sweep across a
  /// rich chromatic gradient, tree repos lean into one dominant pole,
  /// modular repos show sharp separation between poles.
  final UniversalityVector? universality;

  const EigenmanifoldGlow({
    super.key,
    required this.child,
    this.temperature = 0.0,
    this.spectralGap = 0.3,
    this.spectralDimension = 2.0,
    this.universality,
  });

  @override
  State<EigenmanifoldGlow> createState() => _EigenmanifoldGlowState();
}

class _EigenmanifoldGlowState extends State<EigenmanifoldGlow>
    with SingleTickerProviderStateMixin, WindowAwakeGuardedMixin {
  AnimationController? _ticker;
  double _berryPhase = 0.0;
  double _lastTickTime = 0.0;

  // Cached pole colors — recomputed only when inputs change.
  (Color, Color)? _cachedPoles;
  Color? _cachedBaseCool;
  Color? _cachedBaseWarm;
  UniversalityVector? _cachedUniversality;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void onWindowAwakeChanged() => _syncTicker();

  @override
  void didUpdateWidget(covariant EigenmanifoldGlow old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    final rate = context.motionRateRead;
    final awake = WindowActivity.instance.awake;
    final active = rate > 0.05 && awake;

    if (active) {
      if (_ticker == null) {
        _ticker = AnimationController(
          vsync: this,
          duration: const Duration(seconds: 60),
        );
        _ticker!.addListener(_onTick);
        _ticker!.repeat();
      }
    } else {
      _ticker?.removeListener(_onTick);
      _ticker?.dispose();
      _ticker = null;
    }
  }

  void _onTick() {
    final now = _ticker!.lastElapsedDuration?.inMicroseconds ?? 0;
    final nowSec = now / 1e6;
    final dt = nowSec - _lastTickTime;
    _lastTickTime = nowSec;

    if (dt > 0 && dt < 1.0) {
      _berryPhase += (0.005 + widget.temperature * 0.02) * dt;
      const period = 2.0 * 3.141592653589793 / 0.03;
      if (_berryPhase > period) _berryPhase -= period;
    }
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    _ticker?.dispose();
    super.dispose();
  }

  (Color, Color) _resolvedPoles(Color baseCool, Color baseWarm) {
    if (_cachedPoles != null &&
        _cachedBaseCool == baseCool &&
        _cachedBaseWarm == baseWarm &&
        identical(_cachedUniversality, widget.universality)) {
      return _cachedPoles!;
    }
    _cachedBaseCool = baseCool;
    _cachedBaseWarm = baseWarm;
    _cachedUniversality = widget.universality;
    return _cachedPoles =
        _modulatePoles(baseCool, baseWarm, widget.universality);
  }

  @override
  Widget build(BuildContext context) {
    if (_ticker == null) return widget.child;
    if (ThemeShaders.eigenmanifold() == null) return widget.child;

    final t = context.tokens;
    final (coolColor, warmColor) =
        _resolvedPoles(t.hyperChromatic1, t.hyperChromatic2);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ticker!,
        builder: (context, child) {
          final elapsed =
              _ticker!.lastElapsedDuration?.inMicroseconds ?? 0;
          final timeSec = elapsed / 1e6;

          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) =>
                ThemeShaders.eigenmanifoldShader(
                  width: bounds.width,
                  height: bounds.height,
                  time: timeSec,
                  temperature: widget.temperature.clamp(0.0, 1.0),
                  gap: widget.spectralGap.clamp(0.01, 1.0),
                  spectralDim: widget.spectralDimension.clamp(0.5, 5.0),
                  berryPhase: _berryPhase,
                  intensity: 1.0,
                  coolColor: coolColor,
                  warmColor: warmColor,
                ) ??
                ui.Gradient.linear(
                  Offset.zero,
                  const Offset(1, 0),
                  const [Color(0x00000000), Color(0x00000000)],
                ),
            child: child!,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ── Universality-derived color pole modulation ─────────────────────
//
// Each archetype has a distinct relationship with chromatic space:
//
//   crystalline — convergent. Poles pull toward each other. The glow
//     is almost monochromatic — a single spectral line. The repo's
//     eigenvalue spacing is tight and ordered; the light reflects that
//     by refusing to spread.
//
//   goe — divergent. Poles push apart. Maximum chromatic range with
//     visible turbulence. The repo's spectrum is chaotic; the light
//     carries that restlessness as rich color variation.
//
//   tree — asymmetric. Cool pole dominates. The dendritic hierarchy
//     has a single voice; the glow leans into it. One color speaks,
//     the other whispers.
//
//   bulk — diffuse. Both poles desaturate slightly. Many modes
//     contribute but none dominate; the light is warm fog, not a
//     sharp beam.
//
//   modular — sharp. Both poles at full saturation, clearly separated.
//     The communities are distinct; the glow shows their boundaries.
//
//   poisson — neutral. Theme defaults. The repo is unremarkable
//     spectrally; the glow doesn't editorialize.
//
// Blending uses the same (1-d)² weighting the sheen uses for its
// archetype templates — a repo at the edge between two classes gets
// a hybrid that shifts smoothly, not a snap to the nearest.

(Color, Color) _modulatePoles(
  Color baseCool, Color baseWarm, UniversalityVector? u,
) {
  if (u == null) return (baseCool, baseWarm);

  // Archetype weights — same formula as the sheen's _archetypeWeights.
  double w(double d) => math.pow((1.0 - d).clamp(0.0, 1.0), 2).toDouble();
  final wCryst = w(u.toCrystalline);
  final wGoe = w(u.toGoe);
  final wTree = w(u.toTree);
  final wBulk = w(u.toBulk);
  final wMod = w(u.toModular);
  final wPois = w(u.toPoisson);
  final sum = wCryst + wGoe + wTree + wBulk + wMod + wPois;
  if (sum <= 1e-9) return (baseCool, baseWarm);

  // Each archetype contributes a color RANGE factor (how far apart
  // the poles are) and a BALANCE factor (how much cool vs warm
  // dominates). Blended by archetype weights.
  //
  //                    range   balance  saturation
  //                   [0, 1]   [0, 1]     [0, 1]
  //                   0=same   0=cool     0=gray
  //                   1=far    1=warm     1=vivid
  const profiles = {
    'crystalline': (range: 0.15, balance: 0.50, saturation: 0.85),
    'goe':         (range: 1.00, balance: 0.50, saturation: 1.00),
    'tree':        (range: 0.50, balance: 0.25, saturation: 0.90),
    'bulk':        (range: 0.70, balance: 0.50, saturation: 0.70),
    'modular':     (range: 0.85, balance: 0.50, saturation: 1.00),
    'poisson':     (range: 0.60, balance: 0.50, saturation: 0.90),
  };

  final weights = {
    'crystalline': wCryst / sum,
    'goe': wGoe / sum,
    'tree': wTree / sum,
    'bulk': wBulk / sum,
    'modular': wMod / sum,
    'poisson': wPois / sum,
  };

  var range = 0.0, balance = 0.0, saturation = 0.0;
  for (final entry in weights.entries) {
    final p = profiles[entry.key]!;
    range += entry.value * p.range;
    balance += entry.value * p.balance;
    saturation += entry.value * p.saturation;
  }

  // Apply the blended modulation to the theme's base poles.
  //
  // RANGE: lerp both poles toward their midpoint. range=1 keeps them
  // as-is. range=0 collapses them to the same color.
  final mid = Color.lerp(baseCool, baseWarm, 0.5)!;
  var cool = Color.lerp(mid, baseCool, range)!;
  var warm = Color.lerp(mid, baseWarm, range)!;

  // BALANCE: shift the midpoint toward cool (balance < 0.5) or
  // warm (balance > 0.5). The dominant pole gets brighter; the
  // recessive one gets pulled toward it.
  if ((balance - 0.5).abs() > 0.05) {
    final bias = (balance - 0.5) * 2; // [-1, 1]
    if (bias < 0) {
      // Cool-biased: warm pole fades toward cool
      warm = Color.lerp(warm, cool, -bias * 0.5)!;
    } else {
      // Warm-biased: cool pole fades toward warm
      cool = Color.lerp(cool, warm, bias * 0.5)!;
    }
  }

  // SATURATION: desaturate both poles by the blend factor.
  if (saturation < 0.99) {
    cool = _adjustSaturation(cool, saturation);
    warm = _adjustSaturation(warm, saturation);
  }

  return (cool, warm);
}

Color _adjustSaturation(Color c, double factor) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withSaturation((hsl.saturation * factor).clamp(0.0, 1.0))
      .toColor()
      .withValues(alpha: c.a);}

