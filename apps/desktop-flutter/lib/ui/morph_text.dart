import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'tokens.dart';

/// Theme-driven character-level text morph. Drop-in for [Text] on labels
/// whose content changes over time (status counters, branch names, commit
/// subjects). When the string changes, shared characters slide from their
/// old position to their new one (LCS-aligned); unique chars fade
/// in/out. Stable text is idle — zero ticks until the string actually
/// changes. Duration + curve come from `context.surfaceShader` so each
/// theme gets its own cadence. Reduce-motion short-circuits to instant.
///
/// Not suitable for body text, diff content, or anything you're *reading*
/// — reserve for single-line labels that read as events when they change.
class ThemeMorphText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextDirection? textDirection;

  const ThemeMorphText(
    this.text, {
    super.key,
    this.style,
    this.textDirection,
  });

  @override
  State<ThemeMorphText> createState() => _ThemeMorphTextState();
}

class _ThemeMorphTextState extends State<ThemeMorphText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, value: 1);

  late String _fromText = widget.text;
  late String _toText = widget.text;
  _LaidOut? _fromLayout;
  _LaidOut? _toLayout;
  List<_MorphOp> _ops = const [];
  TextStyle? _cachedStyleKey;
  TextDirection? _cachedDir;
  double? _cachedMaxWidth;

  @override
  void initState() {
    super.initState();
    // When a morph completes, collapse `_fromText` onto `_toText` so the
    // next layout pass reports the to-string's natural size instead of
    // the max(from, to) we hold mid-morph. Without this the widget
    // stays stuck at the wider footprint forever after any text shrink
    // (e.g. a transient "... · peek" suffix that goes away).
    _ac.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (!mounted || _fromText == _toText) return;
      setState(() {
        _fromText = _toText;
        _ops = const [];
        _invalidateLayouts();
      });
    });
  }

  @override
  void didUpdateWidget(covariant ThemeMorphText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) {
      if (old.style != widget.style) _invalidateLayouts();
      return;
    }
    if (context.reduceMotionRead) {
      // No morph: snap straight to the new text so the reported size
      // is the new string's natural size, not max(from, to). Otherwise
      // the widget would inherit any wider footprint from the prior
      // text (e.g. a removed "· peek" suffix) and never shrink.
      _fromText = widget.text;
      _toText = widget.text;
      _ops = const [];
      _invalidateLayouts();
      _ac.value = 1;
      return;
    }
    _fromText = _toText;
    _toText = widget.text;
    _ops = _computeOps(_fromText, _toText);
    _invalidateLayouts();
    _ac
      ..duration = context.surfaceShader.duration
      ..stop()
      ..value = 0
      // safeCurve — progress drives per-glyph opacity via saveLayer
      // alpha, which asserts [0, 1]. Overshoot on elastic themes breaks.
      ..animateTo(1, curve: context.surfaceShader.safeCurve);
  }

  void _invalidateLayouts() {
    _fromLayout?.dispose();
    _toLayout?.dispose();
    _fromLayout = null;
    _toLayout = null;
  }

  @override
  void dispose() {
    _invalidateLayouts();
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final dir = widget.textDirection ?? Directionality.of(context);

    // LayoutBuilder lets us honour the parent's width constraint. Without
    // this, TextPainter lays out unbounded (single line forever), which
    // breaks any site where the text is expected to wrap — commit
    // subjects, setting descriptions, multi-line labels. With maxWidth
    // passed to TextPainter, getOffsetForCaret returns correct 2-D
    // positions per glyph on a wrapped layout; the painter then renders
    // each char at its wrapped (x, y) position, morph intact.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Guard against degenerate constraints: during transitions or
        // tight parent layouts, maxWidth can briefly be 0 or sub-pixel.
        // TextPainter.layout(maxWidth: 0) wraps every char onto its own
        // line, producing a ~99k-pixel-tall layout that blows up the
        // paint pipeline. Treat tiny/zero maxWidth as unbounded so the
        // text at least renders coherently; the ClipRect below handles
        // actual visual overflow.
        final raw = constraints.maxWidth;
        final maxWidth = (raw.isFinite && raw >= 1) ? raw : double.infinity;

        if (_cachedStyleKey != style ||
            _cachedDir != dir ||
            _cachedMaxWidth != maxWidth ||
            _toLayout == null) {
          _invalidateLayouts();
          _fromLayout = _LaidOut.build(_fromText, style, dir, maxWidth);
          _toLayout = _LaidOut.build(_toText, style, dir, maxWidth);
          _cachedStyleKey = style;
          _cachedDir = dir;
          _cachedMaxWidth = maxWidth;
        }

        final to = _toLayout!;
        final from = _fromLayout!;
        // Report size as the MAX of from and to so the widget's footprint
        // doesn't thrash mid-morph — otherwise the parent Row/Column would
        // relayout every frame as glyphs fade in/out, popping overflow
        // banners for one-frame flashes on tight flex containers.
        final stableSize = Size(
          math.max(from.size.width, to.size.width),
          math.max(from.size.height, to.size.height),
        );
        final tokens = context.tokens;
        final shader = context.surfaceShader;
        return ClipRect(
          child: SizedBox(
            width: stableSize.width,
            height: stableSize.height,
            child: AnimatedBuilder(
              animation: _ac,
              builder: (context, _) => CustomPaint(
                size: stableSize,
                isComplex: false,
                willChange: _ac.isAnimating,
                painter: _MorphPainter(
                  from: from,
                  to: to,
                  ops: _ops,
                  progress: _ac.value,
                  effect: shader.textEffect,
                  accent: tokens.accentBright,
                  ambient: tokens.themeAmbient ?? tokens.chromeAccent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── LCS-based per-char ops ─────────────────────────────────────────────

class _MorphOp {
  final int fromIdx; // -1 when char is new
  final int toIdx; // -1 when char is leaving

  const _MorphOp(this.fromIdx, this.toIdx);
}

List<_MorphOp> _computeOps(String from, String to) {
  final n = from.length, m = to.length;
  if (n == 0) return [for (var j = 0; j < m; j++) _MorphOp(-1, j)];
  if (m == 0) return [for (var i = 0; i < n; i++) _MorphOp(i, -1)];
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      if (from.codeUnitAt(i - 1) == to.codeUnitAt(j - 1)) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }
  final ops = <_MorphOp>[];
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (from.codeUnitAt(i - 1) == to.codeUnitAt(j - 1)) {
      ops.add(_MorphOp(i - 1, j - 1));
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      ops.add(_MorphOp(i - 1, -1));
      i--;
    } else {
      ops.add(_MorphOp(-1, j - 1));
      j--;
    }
  }
  while (i > 0) {
    i--;
    ops.add(_MorphOp(i, -1));
  }
  while (j > 0) {
    j--;
    ops.add(_MorphOp(-1, j));
  }
  return ops.reversed.toList();
}

// ── Cached per-glyph layout ────────────────────────────────────────────

class _LaidOut {
  final List<Offset> positions;
  final List<TextPainter> glyphs;
  final Size size;

  _LaidOut._(this.positions, this.glyphs, this.size);

  factory _LaidOut.build(
      String text, TextStyle style, TextDirection dir, double maxWidth) {
    if (text.isEmpty) {
      return _LaidOut._(const [], const [], const Size(0, 14));
    }
    final master = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: dir,
    )..layout(maxWidth: maxWidth);
    final positions = <Offset>[];
    final glyphs = <TextPainter>[];
    for (var i = 0; i < text.length; i++) {
      positions.add(
          master.getOffsetForCaret(TextPosition(offset: i), Rect.zero));
      glyphs.add(TextPainter(
        text: TextSpan(text: text[i], style: style),
        textDirection: dir,
      )..layout());
    }
    final size = master.size;
    master.dispose();
    return _LaidOut._(positions, glyphs, size);
  }

  void dispose() {
    for (final g in glyphs) {
      g.dispose();
    }
  }
}

// ── Painter ────────────────────────────────────────────────────────────

class _MorphPainter extends CustomPainter {
  final _LaidOut from;
  final _LaidOut to;
  final List<_MorphOp> ops;
  final double progress;
  final ThemeTextEffect effect;
  final Color accent;
  final Color ambient;

  // Computed once per paint() and reused by every per-glyph helper —
  // avoids the quadratic blowup of recomputing the text bbox inside
  // each inner-loop `_wavePulse` call.
  Rect? _cachedBbox;

  _MorphPainter({
    required this.from,
    required this.to,
    required this.ops,
    required this.progress,
    required this.effect,
    required this.accent,
    required this.ambient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress;
    // Initial mount (no transition has fired yet) — render the current
    // text directly instead of the empty ops list. Without this the
    // painter would loop zero times and paint nothing on first build.
    if (ops.isEmpty) {
      for (var i = 0; i < to.glyphs.length; i++) {
        to.glyphs[i].paint(canvas, to.positions[i]);
      }
      return;
    }

    // Precompute each op's char-distance to the nearest changing op
    // (insert/remove). Changes = distance 0. Each unit further away
    // gives that glyph a weaker, slightly delayed echo of the effect
    // — so the whole word "feels" each change ripple through it.
    final distances = _distancesToChange();
    // Compute bbox ONCE now so every _wavePulse() call is O(1) instead
    // of re-walking every glyph each time. Big win on long strings.
    _cachedBbox = _computeBboxUncached();

    // ── Single pass: each glyph paints with its per-op tint ─────────
    // No particles, no external overlays. The text itself is the thing
    // that changes color — each glyph picks up the theme-specific tint
    // based on its role in the op (keep / insert / remove) and the
    // progress `t`.
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final dist = distances[i];
      if (op.fromIdx >= 0 && op.toIdx >= 0) {
        // keep
        if (op.fromIdx >= from.glyphs.length ||
            op.toIdx >= to.glyphs.length) continue;
        final p = Offset.lerp(
            from.positions[op.fromIdx], to.positions[op.toIdx], t)!;
        final tint = _tintFor(op, t, p.dx, dist);
        final scale = _scaleFor(op, t, p.dx, dist);
        final ab = _aberrationFor(op, t, dist);
        _paintGlyph(canvas, to.glyphs[op.toIdx], p, 1.0, tint, scale, ab);
      } else if (op.toIdx >= 0) {
        // insert
        if (op.toIdx >= to.glyphs.length) continue;
        if (effect == ThemeTextEffect.pop) {
          // Pop: hard swap at t=0.5 with a one-beat scale burst
          // (1.18 → 1.0 over the second half). Glyph manipulation,
          // no fade, no tint — reads as stamped in.
          if (t < 0.5) continue;
          final burst = 1.18 - 0.18 * ((t - 0.5) * 2).clamp(0.0, 1.0);
          _paintGlyph(canvas, to.glyphs[op.toIdx], to.positions[op.toIdx],
              1.0, null, burst, 0);
          continue;
        }
        if (effect == ThemeTextEffect.chalk) {
          // Chalk: progressively DRAW the glyph L→R with a bright
          // chalk-tip highlight at the reveal edge. The char isn't
          // fading in, it's being written.
          _paintChalkDraw(
              canvas, to.glyphs[op.toIdx], to.positions[op.toIdx], t,
              drawing: true);
          continue;
        }
        final p = to.positions[op.toIdx] + Offset(0, (1 - t) * 2);
        final tint = _tintFor(op, t, p.dx, dist);
        final scale = _scaleFor(op, t, p.dx, dist);
        final ab = _aberrationFor(op, t, dist);
        // When the effect provides an insert tint, the tint IS the
        // transition — keep the glyph at full opacity so the color
        // change is the visible thing. Without a tint we fall back to
        // the plain opacity fade-in.
        final opacity = tint != null ? 1.0 : t;
        _paintGlyph(canvas, to.glyphs[op.toIdx], p, opacity, tint, scale, ab);
      } else {
        // remove
        if (op.fromIdx >= from.glyphs.length) continue;
        if (effect == ThemeTextEffect.pop) {
          if (t >= 0.5) continue;
          final burst = 1.0 + 0.2 * (t * 2).clamp(0.0, 1.0);
          _paintGlyph(canvas, from.glyphs[op.fromIdx],
              from.positions[op.fromIdx], 1 - (t * 2).clamp(0.0, 1.0), null,
              burst, 0);
          continue;
        }
        if (effect == ThemeTextEffect.chalk) {
          // Chalk remove: erase R→L with the same chalk-tip, but the
          // tip trails a softer smudge behind it.
          _paintChalkDraw(
              canvas, from.glyphs[op.fromIdx], from.positions[op.fromIdx], t,
              drawing: false);
          continue;
        }
        final p = from.positions[op.fromIdx] + Offset(0, t * 2);
        final tint = _tintFor(op, t, p.dx, dist);
        final scale = _scaleFor(op, t, p.dx, dist);
        final ab = _aberrationFor(op, t, dist);
        // Same story for removes: while the tint is active the glyph
        // stays fully visible; the last quarter of the transition is
        // where it actually dims and vanishes. Gives the burn/warmth
        // effects room to read before the glyph leaves.
        final opacity = tint != null
            ? (1 - ((t - 0.75) * 4).clamp(0.0, 1.0))
            : (1 - t);
        _paintGlyph(canvas, from.glyphs[op.fromIdx], p, opacity, tint, scale,
            ab);
      }
    }
  }

  /// Blackboard chalk draw/erase. The glyph itself is progressively
  /// revealed across its own width. At the leading edge, a narrow
  /// slice of the glyph is re-painted at pure white — so the tip
  /// reads as the actual ink-shape of the letter catching the fresh
  /// chalk pressure, not a blurred rectangle floating over the slate.
  void _paintChalkDraw(
      Canvas canvas, TextPainter glyph, Offset pos, double t,
      {required bool drawing}) {
    final revealed = drawing ? t : (1 - t);
    if (revealed <= 0) return;
    final rect = pos & glyph.size;
    final revealedWidth = rect.width * revealed;

    // ── Drawn body ─────────────────────────────────────────────────
    // Clip to the revealed portion and paint the glyph in a warm off-
    // white (feels like pressed chalk, not LCD-white). Hard clip = no
    // blur, no ghost edge.
    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(rect.left, rect.top, revealedWidth, rect.height));
    _paintGlyph(canvas, glyph, pos, 1.0,
        const Color(0xE6F5F5F0), 1.0, 0);
    canvas.restore();

    // ── Leading tip ────────────────────────────────────────────────
    // A 3-px-wide vertical slice at the reveal edge, painted as the
    // glyph itself at PURE white. The tip lights up only the glyph's
    // own pixels (via srcATop inside _paintGlyph) — no blur, no screen
    // blend, no bloom over the slate. Reads as chalk contact, crisp.
    if (t > 0.02 && t < 0.98 && revealedWidth > 0.5) {
      final tipX = rect.left + revealedWidth;
      const tipWidth = 3.0;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
        tipX - tipWidth,
        rect.top,
        tipWidth,
        rect.height,
      ));
      _paintGlyph(canvas, glyph, pos, 1.0, Colors.white, 1.0, 0);
      canvas.restore();
    }
  }

  /// Paint a glyph with optional fade, tint, scale, and chromatic
  /// aberration. Everything stays intrinsic to the glyph — no external
  /// particles, just the character being manipulated.
  ///
  /// [scale] scales the glyph about its own center.
  /// [aberration] is a pixel offset amount for CRT-style red/blue ghost
  /// copies (0 disables). The glyph is painted three times: red ghost
  /// offset -[aberration]px left, blue ghost offset +[aberration]px
  /// right, and the main glyph on top.
  void _paintGlyph(Canvas canvas, TextPainter glyph, Offset pos,
      double opacity, Color? tint,
      [double scale = 1.0, double aberration = 0]) {
    final a = opacity.clamp(0.0, 1.0);
    if (a <= 0.01) return;
    final hasTint = tint != null && tint.a > 0.01;
    final hasScale = (scale - 1.0).abs() > 0.001;
    final hasAberration = aberration > 0.1;

    // Chromatic aberration — paint red + blue ghosts around the main
    // glyph to mimic a misconverged CRT. Ghosts are painted BEFORE the
    // main glyph so it sits on top, crisp.
    if (hasAberration) {
      final rect = pos & glyph.size;
      final ghostAlpha = (a * 0.55).clamp(0.0, 1.0);
      _paintGhost(canvas, glyph, pos + Offset(-aberration, 0), rect,
          const Color(0xFFFF2244), ghostAlpha);
      _paintGhost(canvas, glyph, pos + Offset(aberration, 0), rect,
          const Color(0xFF2288FF), ghostAlpha);
    }

    // Main glyph. Optional scale is applied around the glyph's center
    // so the character grows/shrinks in place.
    Offset paintPos = pos;
    if (hasScale) {
      final center = pos + Offset(glyph.size.width / 2, glyph.size.height / 2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      canvas.translate(-center.dx, -center.dy);
    }

    if (!hasTint && a >= 0.99 && !hasAberration) {
      glyph.paint(canvas, paintPos);
    } else {
      // Single saveLayer with a colorFilter does the tint in one pass:
      // the layer captures the glyph's alpha shape, and when it restores
      // the filter paints the tint srcATop onto those pixels at composite
      // time. Halves per-glyph draw work vs. saveLayer + drawRect.
      final rect = paintPos & glyph.size;
      final layerPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, a);
      if (hasTint) {
        layerPaint.colorFilter = ColorFilter.mode(tint, BlendMode.srcATop);
      }
      canvas.saveLayer(rect, layerPaint);
      glyph.paint(canvas, paintPos);
      canvas.restore();
    }

    if (hasScale) canvas.restore();
  }

  /// Paint a color-shifted ghost copy of a glyph for chromatic
  /// aberration. The ColorFilter tints the glyph's pixels as the layer
  /// is composited — no separate drawRect pass needed.
  void _paintGhost(Canvas canvas, TextPainter glyph, Offset pos, Rect rect,
      Color color, double alpha) {
    final ghostRect = pos & glyph.size;
    canvas.saveLayer(
      ghostRect,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, alpha)
        ..colorFilter = ColorFilter.mode(color, BlendMode.srcATop),
    );
    glyph.paint(canvas, pos);
    canvas.restore();
  }

  /// Scale multiplier for a glyph. [dist] is the distance to the
  /// nearest changing op — keeps within the neighborhood get a subtle
  /// delayed scale pulse, so the change feels like a bump traveling
  /// through the word.
  double _scaleFor(_MorphOp op, double t, double glyphX, int dist) {
    if (t <= 0 || t >= 1) return 1.0;
    final isKeep = op.fromIdx >= 0 && op.toIdx >= 0;
    final isInsert = op.fromIdx < 0 && op.toIdx >= 0;
    final localT = _neighborLocalT(t, dist);
    final falloff = _neighborFalloff(dist);
    switch (effect) {
      case ThemeTextEffect.stamp:
        if (isInsert) {
          final settle = (t * 2).clamp(0.0, 1.0);
          return 1.08 - 0.08 * settle;
        }
        // Neighbors get a tiny delayed bump as the stamp lands.
        if (isKeep && falloff > 0) {
          return 1.0 + _triangle(localT) * 0.03 * falloff;
        }
        return 1.0;
      case ThemeTextEffect.sparkle:
        if (isKeep) {
          return 1.0 + _wavePulse(t, glyphX) * 0.04;
        }
        return 1.0;
      case ThemeTextEffect.burn:
      case ThemeTextEffect.twinkle:
      case ThemeTextEffect.warmth:
        // Subtle ripple: neighbors scale up briefly as the change
        // echoes through them.
        if (isKeep && falloff > 0) {
          return 1.0 + _triangle(localT) * 0.02 * falloff;
        }
        return 1.0;
      default:
        return 1.0;
    }
  }

  /// Chromatic aberration offset (pixels). Burn splits each glyph into
  /// R/B ghosts during the transition. Neighbors of a burning glyph
  /// get a weaker split that propagates outward.
  double _aberrationFor(_MorphOp op, double t, int dist) {
    if (t <= 0 || t >= 1) return 0;
    switch (effect) {
      case ThemeTextEffect.burn:
        final isKeep = op.fromIdx >= 0 && op.toIdx >= 0;
        if (isKeep) {
          final falloff = _neighborFalloff(dist);
          if (falloff <= 0) return 0;
          return _triangle(_neighborLocalT(t, dist)) * 1.0 * falloff;
        }
        return _triangle(t) * 1.6;
      default:
        return 0;
    }
  }

  /// List of char-distances from each op to its nearest changing op
  /// (insert/remove). 0 = this op IS the change. Max distance is
  /// capped at [_neighborhoodRange] since glyphs further than that
  /// don't react.
  List<int> _distancesToChange() {
    final n = ops.length;
    final out = List<int>.filled(n, _neighborhoodRange + 1);
    for (var i = 0; i < n; i++) {
      final op = ops[i];
      if (op.fromIdx < 0 || op.toIdx < 0) out[i] = 0;
    }
    // Propagate left→right then right→left to compute nearest-change
    // distance in linear time.
    for (var i = 1; i < n; i++) {
      if (out[i - 1] + 1 < out[i]) out[i] = out[i - 1] + 1;
    }
    for (var i = n - 2; i >= 0; i--) {
      if (out[i + 1] + 1 < out[i]) out[i] = out[i + 1] + 1;
    }
    return out;
  }

  /// Keep glyphs this many chars from a change still echo the effect
  /// (with falloff + stagger). Beyond this, they stay untouched so the
  /// whole text doesn't shimmer for every tiny edit.
  static const int _neighborhoodRange = 4;

  /// Falloff factor for a given distance-from-change: 1.0 at distance 0
  /// (the changing glyph itself), tapering to 0 at [_neighborhoodRange].
  double _neighborFalloff(int dist) {
    if (dist <= 0) return 1.0;
    if (dist > _neighborhoodRange) return 0.0;
    // Smooth curve so the ripple feels wavelike, not linear.
    final x = dist / _neighborhoodRange;
    return (1 - x) * (1 - x);
  }

  /// Stagger delay applied to neighbor echoes: each char further from
  /// the change starts its echo slightly later in the transition, so
  /// the ripple visually propagates outward from the change point.
  double _neighborLocalT(double t, int dist) {
    if (dist <= 0) return t;
    final delay = (dist * 0.06).clamp(0.0, 0.3);
    return ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
  }

  /// Return the color tint to blend onto this glyph at the current
  /// progress. Each effect decides which ops get tinted and when the
  /// tint peaks. Returning `null` (or a zero-alpha color) means the
  /// glyph paints untinted. [dist] is the char-distance to the nearest
  /// changing op; keeps near a change pick up a weaker, delayed echo.
  Color? _tintFor(_MorphOp op, double t, double glyphX, int dist) {
    if (t <= 0 || t >= 1) return null;
    final isKeep = op.fromIdx >= 0 && op.toIdx >= 0;
    final isInsert = op.fromIdx < 0 && op.toIdx >= 0;
    final isRemove = op.fromIdx >= 0 && op.toIdx < 0;
    // Neighbor-echo helpers: for keeps within the echo range, we apply
    // a weaker, delayed version of the effect so the change ripples
    // outward from the changing glyph.
    final localT = _neighborLocalT(t, dist);
    final falloff = _neighborFalloff(dist);

    switch (effect) {
      case ThemeTextEffect.burn:
        // Leaving chars ember out (amber), arriving chars arrive cool
        // (accent). Neighbors pick up a faint amber pulse as the burn
        // passes them.
        if (isRemove) {
          final intensity = _triangle(t, peak: 0.35);
          return const Color(0xFFFF7700).withValues(alpha: intensity * 0.85);
        }
        if (isInsert) {
          final intensity = (1 - t * 1.4).clamp(0.0, 1.0);
          return accent.withValues(alpha: intensity * 0.7);
        }
        if (isKeep && falloff > 0) {
          final intensity = _triangle(localT, peak: 0.35) * falloff * 0.4;
          return const Color(0xFFFF7700).withValues(alpha: intensity);
        }
        return null;
      case ThemeTextEffect.glint:
        // Gold wave rides L→R across the text, tinting each glyph as
        // the wave front passes over it. Wave-based so already neighbor-
        // aware; no extra distance logic needed.
        final wave = _wavePulse(t, glyphX);
        return const Color(0xFFFFE08A).withValues(alpha: wave * 0.9);
      case ThemeTextEffect.twinkle || ThemeTextEffect.sparkle:
        // Arriving chars flash to accent-bright at arrival, settle to
        // normal by mid-transition.
        if (isInsert) {
          final intensity = (1 - t * 2).clamp(0.0, 1.0);
          return accent.withValues(alpha: intensity);
        }
        // Sparkle: its wave ripples kept chars L→R already. Twinkle
        // adds a proximity echo so nearby keeps flash when a char
        // arrives next to them.
        if (isKeep) {
          if (effect == ThemeTextEffect.sparkle) {
            final wave = _wavePulse(t, glyphX);
            return accent.withValues(alpha: wave * 0.5);
          }
          if (falloff > 0) {
            final intensity =
                (1 - localT * 2).clamp(0.0, 1.0) * falloff * 0.6;
            return accent.withValues(alpha: intensity);
          }
        }
        return null;
      case ThemeTextEffect.stamp:
        // Arriving chars snap in with a brief accent-tint pulse.
        // Neighbors pick up a tiny echo so the stamp feels like it
        // shakes the word.
        if (isInsert) {
          final intensity = (1 - t * 2).clamp(0.0, 1.0);
          return accent.withValues(alpha: intensity * 0.9);
        }
        if (isKeep && falloff > 0) {
          final intensity = (1 - localT * 2).clamp(0.0, 1.0) * falloff * 0.35;
          return accent.withValues(alpha: intensity);
        }
        return null;
      case ThemeTextEffect.chalk:
        // Chalk handles its own draw/erase rendering for insert/remove
        // in `_paintChalkDraw`; keeps don't get a tint (already drawn).
        return null;
      case ThemeTextEffect.warmth:
        // Leaving chars catch warm amber as they fade; neighbors warm
        // slightly as the change passes by.
        if (isRemove) {
          final intensity = t.clamp(0.0, 1.0);
          return const Color(0xFFFFB366).withValues(alpha: intensity * 0.85);
        }
        if (isKeep && falloff > 0) {
          final intensity = _triangle(localT) * falloff * 0.3;
          return const Color(0xFFFFB366).withValues(alpha: intensity);
        }
        return null;
      case ThemeTextEffect.pop:
      case ThemeTextEffect.none:
        return null;
    }
  }

  /// Triangle wave: 0 at [t]=0 and [t]=1, peaks at [peak] (default 0.5).
  /// Used by effects whose tint appears and disappears mid-transition.
  double _triangle(double t, {double peak = 0.5}) {
    if (t <= peak) return (t / peak).clamp(0.0, 1.0);
    return ((1 - t) / (1 - peak)).clamp(0.0, 1.0);
  }

  /// Soft pulse that travels L→R across the morph bbox as `t` advances.
  /// Returns [0, 1] intensity for a glyph at [glyphX]. Wave width is
  /// ~20% of the text bbox, so each glyph sees a brief flash as the
  /// front passes over it. Reads bbox from the paint-time cache so
  /// this stays O(1) regardless of string length.
  double _wavePulse(double t, double glyphX) {
    final bbox = _cachedBbox;
    if (bbox == null) return 0;
    final waveX = bbox.left - 20 + (bbox.width + 40) * t;
    final halfWidth = bbox.width * 0.12 + 12;
    final dx = (glyphX - waveX).abs();
    return (1 - dx / halfWidth).clamp(0.0, 1.0);
  }

  /// Compute the bounding box of the TO-string glyph layout. Only
  /// called once per paint() — cached in [_cachedBbox] for the
  /// per-glyph inner loop.
  Rect? _computeBboxUncached() {
    if (to.glyphs.isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (var i = 0; i < to.glyphs.length; i++) {
      final p = to.positions[i];
      final s = to.glyphs[i].size;
      if (p.dx < left) left = p.dx;
      if (p.dy < top) top = p.dy;
      if (p.dx + s.width > right) right = p.dx + s.width;
      if (p.dy + s.height > bottom) bottom = p.dy + s.height;
    }
    if (!left.isFinite) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(_MorphPainter old) =>
      old.progress != progress ||
      old.from != from ||
      old.to != to ||
      old.ops != ops ||
      old.effect != effect ||
      old.accent != accent ||
      old.ambient != ambient;
}
