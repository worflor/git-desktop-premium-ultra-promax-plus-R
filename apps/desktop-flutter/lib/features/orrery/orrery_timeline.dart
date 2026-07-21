// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:math' as math;
import 'dart:ui' as ui show FontFeature;

import 'package:flutter/material.dart';

import '../../i18n/gen/strings.g.dart';
import '../../ui/design_primitives.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/tokens.dart';
import 'orrery_finding_style.dart';
import 'orrery_findings.dart';
import 'orrery_model.dart';

// Shared widths so Row 2's date insets line up under the lane instead of
// drifting from hand-tuned magic numbers. The lane is everything between the
// transport and the readout.
const double _kTransportW = 34;
const double _kGap = 14;
const double _kReadoutW = 150;

// The lane owns two vertical zones. The marker band ([0, _kMarkerBandH)) holds
// the event ticks and answers pointer events as select/hover; the scrub field
// below it holds the terrain, glyphs, heat, and playhead and answers as scrub.
const double _kLaneH = 52;
const double _kMarkerBandH = 14;

/// One tick in the marker band: which finding it stands for (an index into
/// the shared findings list, so the hover channel keeps one id space across
/// rail and timeline) and its horizontal fan offset.
typedef TimelineMarker = ({int finding, double fan});

/// The timeline's event index — which findings earn a marker in the band.
/// Only commit-anchored findings appear: position and trend findings anchor
/// to the head as a *jump target*, not a moment, and painting them as moments
/// would assert the exact false claim the rail's active-state semantics guard
/// against (and crowd the head band with non-events). Markers landing on the
/// same step fan out at [pitch] so every tick stays visible and hittable.
List<TimelineMarker> timelineEventMarkers(
  List<OrreryFinding> findings, {
  double pitch = 5.0,
}) {
  final byStep = <int, List<int>>{};
  for (int i = 0; i < findings.length; i++) {
    if (!findings[i].isEventAnchored) continue;
    (byStep[findings[i].stepIndex] ??= <int>[]).add(i);
  }
  final out = <TimelineMarker>[];
  byStep.forEach((step, group) {
    final k = group.length;
    for (int j = 0; j < k; j++) {
      out.add((finding: group[j], fan: (j - (k - 1) / 2) * pitch));
    }
  });
  out.sort((a, b) => a.finding.compareTo(b.finding));
  return out;
}

/// The Orrery timeline — the spine of the feature. It is the event index of the
/// whole history: the connectivity terrain, the event markers, the commit
/// identity, and a heat band showing when the structure was physically
/// reorganising, all under one playhead. Everything is inline-painted; there
/// are no overlays or tooltips — captions are drawn straight onto the canvas.
class OrreryTimeline extends StatefulWidget {
  final OrreryModel model;
  final ValueNotifier<double>
      head; // continuous scrub position [0, stepCount-1]
  final bool playing;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onScrub; // clamped by the caller
  final List<OrreryFinding>
      findings; // whole-history event index (stable order)

  /// Shared with the rail: index into [findings], null = none. Both sides read
  /// it (to highlight a marker when the rail hovers a row) and write it (when
  /// the pointer hovers a marker here). We only ever null it if we set it.
  final ValueNotifier<int?> hoveredFinding;

  /// Tap a marker: the page jumps to that moment and pins the finding's file.
  final ValueChanged<int> onSelectFinding;

  const OrreryTimeline({
    super.key,
    required this.model,
    required this.head,
    required this.playing,
    required this.onTogglePlay,
    required this.onScrub,
    required this.findings,
    required this.hoveredFinding,
    required this.onSelectFinding,
  });

  @override
  State<OrreryTimeline> createState() => _OrreryTimelineState();
}

class _OrreryTimelineState extends State<OrreryTimeline> {
  // Cursor position while hovering the scrub field (null outside it). Drives the
  // ghost playhead + its date caption.
  final ValueNotifier<Offset?> _ghost = ValueNotifier<Offset?>(null);
  // The lane's cursor, split out so cursor changes don't rebuild the painter.
  final ValueNotifier<MouseCursor> _cursor =
      ValueNotifier<MouseCursor>(MouseCursor.defer);

  // We only clear the shared hover if we were the one who set it — the rail
  // shares this notifier and its hover must never be clobbered by our exit.
  bool _ownsHover = false;

  // Per-step mean node displacement, normalised by its own max. Computed once
  // per model — this is the channel the engine always had and the UI never
  // showed: "when was the repo physically reorganising".
  List<double> _heat = const <double>[];
  // The band's event index: commit-anchored findings only, pre-fanned. See
  // [timelineEventMarkers] for why non-events never earn a tick.
  List<TimelineMarker> _markers = const <TimelineMarker>[];

  @override
  void initState() {
    super.initState();
    _computeHeat();
    _markers = timelineEventMarkers(widget.findings);
  }

  @override
  void didUpdateWidget(OrreryTimeline old) {
    super.didUpdateWidget(old);
    if (!identical(old.model, widget.model)) _computeHeat();
    if (!identical(old.findings, widget.findings)) {
      _markers = timelineEventMarkers(widget.findings);
    }
  }

  @override
  void dispose() {
    _ghost.dispose();
    _cursor.dispose();
    super.dispose();
  }

  // Mean per-step displacement of nodes present on both sides of the step,
  // requiring a quorum so a lone birth/death can't manufacture "motion".
  // Normalised against the *median* step, not zero — every step carries some
  // drift, so a raw max-normalisation paints a constant stripe. A storm is
  // motion above the typical step; the typical step is the baseline.
  void _computeHeat() {
    final steps = widget.model.steps;
    final nodes = widget.model.nodes;
    final n = steps.length;
    final raw = List<double>.filled(n, 0);
    for (int s = 1; s < n; s++) {
      double sum = 0;
      int cnt = 0;
      for (final node in nodes) {
        if (s >= node.positions.length) continue;
        final a = node.positions[s - 1];
        final b = node.positions[s];
        if (a == null || b == null) continue;
        sum += (b - a).distance;
        cnt++;
      }
      raw[s] = cnt >= 4 ? sum / cnt : 0;
    }
    double mx = 0;
    for (final v in raw) {
      if (v > mx) mx = v;
    }
    final sorted = raw.sublist(1)..sort();
    final double med = sorted.isEmpty ? 0 : sorted[sorted.length ~/ 2];
    final double span = mx - med;
    _heat = span <= 1e-12
        ? List<double>.filled(n, 0)
        : <double>[for (final v in raw) ((v - med) / span).clamp(0.0, 1.0)];
  }

  double _maxHead() => widget.model.headPosition;

  double _xOf(int i, double w) {
    final n = widget.model.stepCount;
    return n <= 1 ? 0 : i / (n - 1) * w;
  }

  // Clamped inside the lane so a fan at genesis/head keeps every tick visible
  // and hittable. Must mirror the painter's marker x exactly.
  double _markerX(TimelineMarker m, double w) =>
      (_xOf(widget.findings[m.finding].stepIndex, w) + m.fan)
          .clamp(3.0, math.max(3.0, w - 3.0));

  // Nearest event marker within the pick radius, or null. Returns the index
  // into the shared findings list (the hover channel's id space).
  int? _markerAt(Offset local, double w) {
    int? best;
    double bestD = 5.0;
    for (final m in _markers) {
      final d = (_markerX(m, w) - local.dx).abs();
      if (d < bestD) {
        bestD = d;
        best = m.finding;
      }
    }
    return best;
  }

  void _clearOwnedHover() {
    if (_ownsHover) {
      widget.hoveredFinding.value = null;
      _ownsHover = false;
    }
  }

  void _onHover(Offset local, double w) {
    if (local.dy < _kMarkerBandH) {
      _ghost.value = null;
      final i = _markerAt(local, w);
      if (i != null) {
        widget.hoveredFinding.value = i;
        _ownsHover = true;
        _cursor.value = SystemMouseCursors.click;
      } else {
        _clearOwnedHover();
        _cursor.value = MouseCursor.defer;
      }
      return;
    }
    _clearOwnedHover();
    _ghost.value = local;
    _cursor.value = SystemMouseCursors.click;
  }

  void _onExit() {
    _ghost.value = null;
    _clearOwnedHover();
    _cursor.value = MouseCursor.defer;
  }

  void _onTapUp(Offset local, double w) {
    if (local.dy < _kMarkerBandH) {
      final i = _markerAt(local, w);
      if (i != null) widget.onSelectFinding(i);
      return; // empty band taps do nothing
    }
    _scrub(local.dx, w);
  }

  void _scrub(double dx, double w) {
    final maxHead = _maxHead();
    if (maxHead <= 0 || w <= 0) return;
    widget.onScrub((dx / w) * maxHead);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = _TimelineColors.fromTokens(t);
    final markerColors = <Color>[
      for (final m in _markers)
        findingAccent(t, widget.findings[m.finding].kind),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _TimelinePlayButton(
                playing: widget.playing,
                onTap: widget.onTogglePlay,
              ),
              const SizedBox(width: _kGap),
              Expanded(
                child: SizedBox(
                  height: _kLaneH,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      return ValueListenableBuilder<MouseCursor>(
                        valueListenable: _cursor,
                        builder: (_, cursor, child) => MouseRegion(
                          cursor: cursor,
                          onHover: (e) => _onHover(e.localPosition, w),
                          onExit: (_) => _onExit(),
                          child: child,
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _onTapUp(d.localPosition, w),
                          onHorizontalDragStart: (d) =>
                              _scrub(d.localPosition.dx, w),
                          onHorizontalDragUpdate: (d) =>
                              _scrub(d.localPosition.dx, w),
                          child: ListenableBuilder(
                            listenable: Listenable.merge(
                                [widget.head, widget.hoveredFinding, _ghost]),
                            builder: (_, __) => CustomPaint(
                              painter: _TimelinePainter(
                                model: widget.model,
                                head: widget.head.value,
                                ghost: _ghost.value,
                                hoveredIndex: widget.hoveredFinding.value,
                                findings: widget.findings,
                                markers: _markers,
                                markerColors: markerColors,
                                heat: _heat,
                                colors: colors,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: _kGap),
              SizedBox(width: _kReadoutW, child: _readout(t)),
            ],
          ),
          const SizedBox(height: 3),
          // Inset so the dates align exactly under the lane's two ends.
          Padding(
            padding: const EdgeInsets.only(
              left: _kTransportW + _kGap,
              right: _kGap + _kReadoutW,
            ),
            child: Row(
              children: [
                Text(_fmtDate(widget.model.steps.first.date),
                    style: TextStyle(color: t.textFaint, fontSize: 10)),
                const Spacer(),
                Text(_fmtDate(widget.model.steps.last.date),
                    style: TextStyle(color: t.textFaint, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Commit identity, next to the lane — the sha/date that used to live in the
  // page header. Rebuilds on head alone.
  Widget _readout(AppTokens t) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.head,
      builder: (_, head, __) {
        final n = widget.model.stepCount;
        final idx = head.round().clamp(0, n - 1);
        final step = widget.model.steps[idx];
        const tab = <ui.FontFeature>[ui.FontFeature.tabularFigures()];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '${idx + 1}',
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: tab,
                  ),
                ),
                TextSpan(
                  text: ' / $n',
                  style: TextStyle(
                    color: t.textFaint,
                    fontSize: 12,
                    fontFeatures: tab,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 1),
            Text(step.shortSha,
                style: TextStyle(
                    color: t.textMuted, fontSize: 11, fontFeatures: tab)),
            const SizedBox(height: 1),
            Text(_fmtDate(step.date),
                style: TextStyle(
                    color: t.textFaint, fontSize: 10, fontFeatures: tab)),
          ],
        );
      },
    );
  }
}

/// The transport control — same circular play/pause as the old scrubber, kept
/// byte-for-byte so the timeline's character carries over.
class _TimelinePlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _TimelinePlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return HoverableTap(
      onTap: onTap,
      borderRadius: AppRadii.pillAll,
      builder: (context, hovered) => Container(
        width: _kTransportW,
        height: _kTransportW,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: t.surface1.withValues(alpha: hovered ? 0.85 : 0.6),
          shape: CircleBorder(
            side: BorderSide(
                color: t.chromeBorder.withValues(alpha: hovered ? 0.95 : 0.7)),
          ),
        ),
        child: Icon(
          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 19,
          color: hovered ? t.textStrong : t.textNormal,
        ),
      ),
    );
  }
}

/// Painter-side colours, resolved from tokens in build() so the painter never
/// reaches for a BuildContext.
class _TimelineColors {
  final Color spark;
  final Color sparkFill;
  final Color regime;
  final Color archetype;
  final Color playhead;
  final Color heat;
  final Color ghostLine;
  final Color ghostText;
  final Color axisText;
  const _TimelineColors({
    required this.spark,
    required this.sparkFill,
    required this.regime,
    required this.archetype,
    required this.playhead,
    required this.heat,
    required this.ghostLine,
    required this.ghostText,
    required this.axisText,
  });

  factory _TimelineColors.fromTokens(AppTokens t) => _TimelineColors(
        spark: t.textNormal,
        sparkFill: t.accentBright,
        regime: t.stateModified,
        archetype: t.accentBright,
        playhead: t.textStrong,
        heat: t.stateModified,
        ghostLine: t.textStrong,
        ghostText: t.textMuted,
        axisText: t.textFaint,
      );

  bool sameAs(_TimelineColors o) =>
      spark == o.spark &&
      sparkFill == o.sparkFill &&
      regime == o.regime &&
      archetype == o.archetype &&
      playhead == o.playhead &&
      heat == o.heat &&
      ghostLine == o.ghostLine &&
      ghostText == o.ghostText &&
      axisText == o.axisText;
}

/// The timeline canvas: a connectivity sparkline fitted to the scrub field, a
/// motion heat band along the floor, regime notches + archetype diamonds, the
/// event markers in their band, a ghost playhead under the cursor, and the
/// live playhead. All captions are painted here — no widgets, no overlays.
class _TimelinePainter extends CustomPainter {
  final OrreryModel model;
  final double head;
  final Offset? ghost;

  /// Index into [findings] of the shared hovered finding, or null. Position
  /// and trend findings never earn a marker, so a rail hover on one simply
  /// finds no tick to light here — their home on this page is the disk.
  final int? hoveredIndex;
  final List<OrreryFinding> findings;
  final List<TimelineMarker> markers; // events only, pre-fanned
  final List<Color> markerColors; // aligned with [markers]
  final List<double> heat;
  final _TimelineColors colors;

  _TimelinePainter({
    required this.model,
    required this.head,
    required this.ghost,
    required this.hoveredIndex,
    required this.findings,
    required this.markers,
    required this.markerColors,
    required this.heat,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || model.stepCount < 2) return;
    final int n = model.stepCount;
    final double w = size.width;
    final double h = size.height;
    final double maxHead = (n - 1).toDouble();

    // The scrub field: terrain lives between the marker band and the heat band.
    const double top = _kMarkerBandH + 2;
    final double bot = h - 5;

    double xOf(int i) => n == 1 ? 0 : i / (n - 1) * w;

    double lo = double.infinity, hi = -double.infinity;
    for (final s in model.steps) {
      lo = math.min(lo, s.gap);
      hi = math.max(hi, s.gap);
    }
    final double span = (hi - lo).abs() < 1e-9 ? 1.0 : (hi - lo);
    double yOf(double gap) => bot - ((gap - lo) / span) * (bot - top);

    // Connectivity sparkline + soft fill, fitted so the marker band stays clear.
    final Path line = Path();
    final Path fill = Path()..moveTo(0, bot);
    for (int i = 0; i < n; i++) {
      final p = Offset(xOf(i), yOf(model.steps[i].gap));
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx, p.dy);
      }
      fill.lineTo(p.dx, p.dy);
    }
    fill
      ..lineTo(w, bot)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = colors.sparkFill.withValues(alpha: 0.10),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = colors.spark.withValues(alpha: 0.85),
    );

    // Motion heat band along the floor — when the structure was physically
    // reorganising. Each segment spans the step it measures; near-still is skip.
    final double heatY = h - 3;
    for (int s = 1; s < n && s < heat.length; s++) {
      final v = heat[s];
      if (v < 0.02) continue;
      canvas.drawRect(
        Rect.fromLTRB(xOf(s - 1), heatY, xOf(s), h),
        Paint()..color = colors.heat.withValues(alpha: 0.55 * v),
      );
    }

    // Regime changes (notch + top dot) and archetype shifts (diamond on curve),
    // constrained to the scrub field.
    for (int i = 0; i < n; i++) {
      final s = model.steps[i];
      final x = xOf(i);
      if (s.regimeChange) {
        canvas.drawLine(
          Offset(x, top),
          Offset(x, bot),
          Paint()
            ..color = colors.regime.withValues(alpha: 0.6)
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(Offset(x, top), 2.2,
            Paint()..color = colors.regime.withValues(alpha: 0.9));
      }
      if (s.archetypeShift) {
        _diamond(canvas, Offset(x, yOf(s.gap)), 3.2,
            Paint()..color = colors.archetype.withValues(alpha: 0.95));
      }
    }

    // Ghost playhead: a faint rule at the cursor with the step's date, kept in
    // the upper scrub field so it never meets the heat band.
    final Offset? g = ghost;
    if (g != null) {
      final double gx = g.dx.clamp(0.0, w);
      canvas.drawLine(
        Offset(gx, top),
        Offset(gx, bot),
        Paint()
          ..color = colors.ghostLine.withValues(alpha: 0.25)
          ..strokeWidth = 1.0,
      );
      final int gi = (gx / w * maxHead).round().clamp(0, n - 1);
      final gs = model.steps[gi];
      _paintCaption(
        canvas,
        '${gi + 1} · ${_fmtDate(gs.date)}',
        anchorX: gx,
        y: top + 1,
        laneWidth: w,
        color: colors.ghostText,
        fontSize: 9.5,
        weight: FontWeight.w500,
        tabular: true,
      );
    }

    // Event markers in the band ([timelineEventMarkers] — commit-anchored
    // findings only). The hovered one (set by either side) grows and gains a
    // kind-coloured label painted next to it.
    for (int k = 0; k < markers.length; k++) {
      final int fi = markers[k].finding;
      final bool hot = fi == hoveredIndex;
      final Color c = k < markerColors.length
          ? markerColors[k]
          : colors.spark; // defensive; lists stay aligned
      // Same clamp as the hit-test's _markerX — paint and pick must agree.
      final double mx = (xOf(findings[fi].stepIndex) + markers[k].fan)
          .clamp(3.0, math.max(3.0, w - 3.0));
      final double tw = hot ? 3.5 : 2.5;
      final double th = hot ? 11 : 8;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(mx, _kMarkerBandH / 2), width: tw, height: th),
          const Radius.circular(1),
        ),
        Paint()..color = c.withValues(alpha: hot ? 1.0 : 0.75),
      );
      if (hot) {
        _paintCaption(
          canvas,
          findingLabel(findings[fi].kind),
          anchorX: mx + 6,
          y: 1,
          laneWidth: w,
          color: c,
          fontSize: 8.5,
          weight: FontWeight.w700,
          letterSpacing: 0.6,
        );
      }
    }

    // The live playhead — full-height rule through the scrub field plus a dot
    // riding the sparkline at the head step.
    final double px = (head / maxHead).clamp(0.0, 1.0) * w;
    canvas.drawLine(
      Offset(px, _kMarkerBandH),
      Offset(px, h),
      Paint()
        ..color = colors.playhead.withValues(alpha: 0.9)
        ..strokeWidth = 1.4,
    );
    canvas.drawCircle(
      Offset(px, yOf(model.steps[head.round().clamp(0, n - 1)].gap)),
      3.6,
      Paint()..color = colors.playhead,
    );

    // The one persistent axis label, replacing the old external column.
    _paintCaption(
      canvas,
      t.orrery.structure.connectivity,
      anchorX: 0,
      y: _kMarkerBandH + 1,
      laneWidth: w,
      color: colors.axisText,
      fontSize: 9,
      weight: FontWeight.w400,
      leftAlign: true,
    );
  }

  void _diamond(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  // A single painted caption, x-clamped to stay inside the lane. [anchorX] is
  // the desired left edge unless it would overflow, in which case it flips left.
  void _paintCaption(
    Canvas canvas,
    String text, {
    required double anchorX,
    required double y,
    required double laneWidth,
    required Color color,
    required double fontSize,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    bool tabular = false,
    bool leftAlign = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          fontFeatures:
              tabular ? const [ui.FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double x = anchorX;
    if (!leftAlign && x + tp.width > laneWidth) {
      x = anchorX - tp.width - 8; // flip to the cursor's left
    }
    x = x.clamp(0.0, math.max(0.0, laneWidth - tp.width));
    tp.paint(canvas, Offset(x, y));
    // TextPainter holds native (dart:ui) resources; a fresh one is built per
    // caption per paint, so it must be released or leak_tracker flags every
    // repaint (surfaced as undisposed TextPainters in the orrery scrub tests).
    tp.dispose();
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.head != head ||
      old.ghost != ghost ||
      old.hoveredIndex != hoveredIndex ||
      !identical(old.model, model) ||
      !identical(old.findings, findings) ||
      // markerColors is derived from markers + tokens, both already compared
      // (markers by identity, tokens via colors.sameAs) — no separate check.
      !identical(old.markers, markers) ||
      !identical(old.heat, heat) ||
      !old.colors.sameAs(colors);
}

/// "Mon D, YYYY" — the timeline's own copy of the app-wide date format so the
/// genesis/present captions and the readout read identically to the page.
String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  final m = t.common.time.monthAbbrevs;
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}
