import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'orrery_finding_style.dart';
import 'orrery_findings.dart';
import 'orrery_model.dart';

/// The Orrery's right rail — an astronomer's console over the scrubbed history.
/// A flat instrument column, not a stack of cards: hairlines, small caps, and
/// tabular figures carry the reading. Three blocks stay put as you scrub —
/// STRUCTURE (what kind of shape the repo is), FIELD (three scalars as
/// full-history sparklines with a sweeping playhead), and FINDINGS (a ledger of
/// structural events). The selection inspector docks at the bottom, so pinning a
/// node never shifts the blocks above it.
class OrreryRail extends StatefulWidget {
  final OrreryModel model;

  /// Continuous scrub position in `[0, stepCount-1]`; the page rebuilds the rail
  /// as it changes, so the playhead dots sweep with it.
  final double head;
  final List<OrreryFinding> findings;
  final void Function(int step, int? nodeId) onSelect;

  /// Shared with the timeline: an index into [findings]. The rail writes it on
  /// pointer enter/leave of a row and reads it so a row lights up when the
  /// timeline hovers that finding's marker.
  final ValueNotifier<int?> hoveredFinding;

  /// The pinned node id (file-space), if any. A position finding's row reads as
  /// active only when its file is actually pinned — standing at the head step
  /// alone means nothing for findings that merely anchor to the present.
  final int? pinnedNodeId;
  final ({String path, String story})? selection;
  final VoidCallback onClearSelection;

  const OrreryRail({
    super.key,
    required this.model,
    required this.head,
    required this.findings,
    required this.onSelect,
    required this.hoveredFinding,
    required this.pinnedNodeId,
    required this.selection,
    required this.onClearSelection,
  });

  @override
  State<OrreryRail> createState() => _OrreryRailState();
}

class _OrreryRailState extends State<OrreryRail> {
  final ScrollController _ledgerScroll = ScrollController();
  // One key per row so a timeline-hover can scroll its row into view. The
  // ledger is built non-lazily (a handful of findings), so every row has a
  // live context to ensureVisible on.
  List<GlobalKey> _rowKeys = const <GlobalKey>[];
  // True while the hover change came from our own row's pointer — the row is
  // visible by definition, and scrolling under the cursor would fight it.
  bool _selfHover = false;

  OrreryModel get model => widget.model;
  double get head => widget.head;
  List<OrreryFinding> get findings => widget.findings;

  @override
  void initState() {
    super.initState();
    _rowKeys = [for (final _ in widget.findings) GlobalKey()];
    widget.hoveredFinding.addListener(_onHoverChannel);
  }

  @override
  void didUpdateWidget(OrreryRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.findings, widget.findings)) {
      _rowKeys = [for (final _ in widget.findings) GlobalKey()];
    }
    if (!identical(old.hoveredFinding, widget.hoveredFinding)) {
      old.hoveredFinding.removeListener(_onHoverChannel);
      widget.hoveredFinding.addListener(_onHoverChannel);
    }
  }

  @override
  void dispose() {
    widget.hoveredFinding.removeListener(_onHoverChannel);
    _ledgerScroll.dispose();
    super.dispose();
  }

  /// A timeline-side hover scrolls the matching ledger row into view — the
  /// cross-highlight is worthless if the lit row sits below the fold. A no-op
  /// for already-visible rows and for hovers born in the rail itself.
  void _onHoverChannel() {
    if (_selfHover) return;
    final int? i = widget.hoveredFinding.value;
    if (i == null || i < 0 || i >= _rowKeys.length) return;
    final ctx = _rowKeys[i].currentContext;
    if (ctx == null) return;
    // motionRead, not motion — this runs from a notifier callback, where a
    // build-time subscription is illegal. Rate 0 collapses the duration and
    // ensureVisible degrades to a jump, so reduce-motion is honoured for free.
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: context.motionRead(AppMotion.fade),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final int index = head.round().clamp(0, model.stepCount - 1);
    final OrreryStep step = model.steps[index];

    // Each scalar's whole trajectory, so the sparklines read the terrain the
    // playhead is crossing rather than a single instantaneous bar.
    final List<double> gapCurve = [for (final s in model.steps) s.gap];
    final List<double> rigidityCurve = [
      for (final s in model.steps) s.rigidity
    ];
    final List<double> entropyCurve = [
      for (final s in model.steps) s.vonNeumann
    ];

    return Container(
      width: 270,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _RailLabel('STRUCTURE'),
          const SizedBox(height: 4),
          Text(
            step.archetype.isEmpty ? 'forming…' : step.archetype,
            style: TextStyle(
              color: t.accentBright,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          // One-line gauge: label, the bar itself, the value. Vertical space is
          // the rail's scarcest resource — the ledger below must keep breathing
          // room even on short windows.
          Row(
            children: [
              Text('canonical',
                  style: TextStyle(color: t.textMuted, fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: _ThinBar(
                  value: step.canonicality,
                  track: t.chromeBorder.withValues(alpha: 0.45),
                  fill: t.accentBright.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                step.canonicality.toStringAsFixed(2),
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          const _RailLabel('FIELD'),
          const SizedBox(height: 6),
          _FieldInstrument(
            label: 'connectivity',
            value: _fmtScalar(step.gap, 3),
            curve: gapCurve,
            head: head,
          ),
          const SizedBox(height: 7),
          _FieldInstrument(
            label: 'rigidity',
            value: _fmtScalar(step.rigidity, 3),
            curve: rigidityCurve,
            head: head,
          ),
          const SizedBox(height: 7),
          _FieldInstrument(
            label: 'entropy',
            value: _fmtScalar(step.vonNeumann, 2),
            curve: entropyCurve,
            head: head,
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              const _RailLabel('FINDINGS'),
              if (findings.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('${findings.length}',
                    style: TextStyle(
                      color: t.textFaint,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // The lower zone shares its height between the ledger and the docked
          // inspector inside one LayoutBuilder. The pinned node is the user's
          // focus, so the inspector may take the whole zone on a short window
          // (the ledger scrolls; it can vanish); the cap plus the ClipRect
          // guarantee it never paints past the rail into the timeline, with the
          // story fading at the cut.
          Expanded(
            child: LayoutBuilder(
              builder: (context, zone) {
                final double inspectorCap = math.min(170.0, zone.maxHeight);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ledger(t, index)),
                    if (widget.selection != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: inspectorCap),
                        child: ClipRect(
                          child: _Inspector(
                            path: widget.selection!.path,
                            story: widget.selection!.story,
                            onClear: widget.onClearSelection,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledger(AppTokens t, int index) {
    return findings.isEmpty
        ? Text('No structural events detected in this history.',
            style: TextStyle(color: t.textFaint, fontSize: 11.5, height: 1.3))
        : ValueListenableBuilder<int?>(
            valueListenable: widget.hoveredFinding,
            // A truly non-lazy scrollable: every row's element stays
            // alive off-screen, so a timeline hover can ensureVisible
            // its row (see _onHoverChannel — a lazy ListView gives
            // off-screen rows no context). Findings number a handful,
            // never a feed, so building them all is free.
            builder: (_, hoveredIdx, __) => SingleChildScrollView(
              controller: _ledgerScroll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < findings.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Container(
                          height: 1,
                          color: t.chromeBorder.withValues(alpha: 0.25),
                        ),
                      ),
                    // Active = the disk is showing this finding right
                    // now. Event findings light when the playhead stands
                    // on their commit; position findings additionally
                    // need their file pinned (most anchor at the head,
                    // and opening at the present must not light up the
                    // whole ledger); trend findings describe the whole
                    // history and never auto-light.
                    _FindingRow(
                      key: _rowKeys[i],
                      finding: findings[i],
                      active: findings[i].stepIndex == index &&
                          (findings[i].nodeId != null
                              ? findings[i].nodeId == widget.pinnedNodeId
                              : findings[i].isEventAnchored),
                      litByTimeline: hoveredIdx == i,
                      onTap: () => widget.onSelect(
                          findings[i].stepIndex, findings[i].nodeId),
                      onEnter: () {
                        _selfHover = true;
                        widget.hoveredFinding.value = i;
                        _selfHover = false;
                      },
                      onExit: () {
                        if (widget.hoveredFinding.value == i) {
                          _selfHover = true;
                          widget.hoveredFinding.value = null;
                          _selfHover = false;
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
  }
}

/// A scalar readout that admits gaps: steps whose spectrum was absent carry
/// NaN (rigidity does this on early snapshots), and a fabricated number would
/// be a lie — show an em dash instead.
String _fmtScalar(double v, int digits) =>
    v.isFinite ? v.toStringAsFixed(digits) : '—';

/// Section heading — small caps, wide tracking, whisper-faint. The rail's only
/// typographic chrome.
class _RailLabel extends StatelessWidget {
  final String text;
  const _RailLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text,
      style: TextStyle(
        color: t.textFaint,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    );
  }
}

/// The canonicality gauge — a 3px hairline bar, quieter than a meter.
class _ThinBar extends StatelessWidget {
  final double value; // 0..1
  final Color track;
  final Color fill;
  const _ThinBar(
      {required this.value, required this.track, required this.fill});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.xxsAll,
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: ColoredBox(color: fill),
            ),
          ],
        ),
      ),
    );
  }
}

/// One FIELD scalar: a header reading its label and current value, over a
/// full-history micro-sparkline with a playhead dot at the live scrub position.
class _FieldInstrument extends StatelessWidget {
  final String label;
  final String value;
  final List<double> curve;
  final double head;
  const _FieldInstrument({
    required this.label,
    required this.value,
    required this.curve,
    required this.head,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: t.textMuted, fontSize: 11.5)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 18,
          child: CustomPaint(
            painter: _SparkPainter(
              curve: curve,
              head: head,
              line: t.textNormal.withValues(alpha: 0.5),
              fill: t.textNormal.withValues(alpha: 0.05),
              playhead: t.accentBright,
              baseline: t.chromeBorder.withValues(alpha: 0.3),
            ),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

/// A scalar's whole trajectory, normalised to its own range, with a playhead
/// dot at the fractional scrub position so it sweeps smoothly during play.
/// Pure over resolved colours + numbers — never touches BuildContext.
class _SparkPainter extends CustomPainter {
  final List<double> curve;
  final double head;
  final Color line;
  final Color fill;
  final Color playhead;
  final Color baseline;
  const _SparkPainter({
    required this.curve,
    required this.head,
    required this.line,
    required this.fill,
    required this.playhead,
    required this.baseline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int n = curve.length;
    if (n < 2 || size.isEmpty) return;
    final double w = size.width;
    final double h = size.height;

    // The range is taken over finite samples only — a step whose spectrum was
    // absent carries NaN (rigidity does, early on) and must read as a gap in
    // the trace, not poison the whole instrument into blankness.
    double lo = double.infinity, hi = -double.infinity;
    int finite = 0;
    for (final v in curve) {
      if (!v.isFinite) continue;
      finite++;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final double range = hi - lo;
    final bool flat = range < 1e-9; // no spread — draw a flat midline

    const double padT = 3, padB = 3;
    final double usable = h - padT - padB;
    double xOf(double i) => i / (n - 1) * w;
    double yOf(double v) {
      final double f = flat ? 0.5 : (v - lo) / range;
      return padT + (1 - f) * usable;
    }

    canvas.drawLine(
      Offset(0, h - 0.5),
      Offset(w, h - 0.5),
      Paint()
        ..color = baseline
        ..strokeWidth = AppBorderWidth.hairline,
    );
    if (finite < 2) return; // nothing traceable — the baseline says "no data"

    // Trace and fill per contiguous finite run, so NaN steps become visible
    // breaks rather than interpolated fiction.
    final Path linePath = Path();
    final Path fillPath = Path();
    bool inRun = false;
    double runStartX = 0;
    double lastX = 0;
    void closeRun() {
      if (!inRun) return;
      fillPath
        ..lineTo(lastX, h)
        ..lineTo(runStartX, h)
        ..close();
      inRun = false;
    }

    for (int i = 0; i < n; i++) {
      final double v = curve[i];
      if (!v.isFinite) {
        closeRun();
        continue;
      }
      final double x = xOf(i.toDouble());
      final double y = yOf(v);
      if (!inRun) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
        runStartX = x;
        inRun = true;
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      lastX = x;
    }
    closeRun();
    canvas.drawPath(fillPath, Paint()..color = fill);
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );

    // Interpolate the curve between the bracketing steps so the dot glides
    // rather than snapping from vertex to vertex. When a bracket is NaN the
    // dot leans on the finite side; inside a gap it simply isn't drawn.
    final double hp = head.clamp(0.0, (n - 1).toDouble());
    final int i0 = hp.floor().clamp(0, n - 1);
    final int i1 = (i0 + 1).clamp(0, n - 1);
    final double frac = hp - i0;
    final double a = curve[i0], b = curve[i1];
    final double? pv = (a.isFinite && b.isFinite)
        ? a + (b - a) * frac
        : (a.isFinite ? a : (b.isFinite ? b : null));
    if (pv != null) {
      canvas.drawCircle(
          Offset(xOf(hp), yOf(pv)), 2.2, Paint()..color = playhead);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.head != head ||
      !identical(old.curve, curve) ||
      old.line != line ||
      old.fill != fill ||
      old.playhead != playhead ||
      old.baseline != baseline;
}

/// One finding in the ledger — flat, no card box. A kind-coloured tick down the
/// left edge, a kind glyph + label line, and the full headline underneath. Lit
/// by local hover or by the timeline hovering this finding's marker; the active
/// row (its step == the scrub position) carries a faint fill.
class _FindingRow extends StatelessWidget {
  final OrreryFinding finding;
  final bool active;
  final bool litByTimeline;
  final VoidCallback onTap;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  const _FindingRow({
    super.key,
    required this.finding,
    required this.active,
    required this.litByTimeline,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final Color accent = findingAccent(t, finding.kind);
    // The anchor is a commit ref on event findings ("13 · a1b2c3d") and a bare
    // word on position ones; show only the former, since the kind label already
    // names what a position finding is.
    final bool showAnchor = finding.isEventAnchored;

    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: HoverableTap(
        onTap: onTap,
        borderRadius: AppRadii.xsAll,
        builder: (context, localHover) {
          final bool lit = litByTimeline || localHover;
          return Container(
            decoration: BoxDecoration(
              color: active
                  ? t.itemActiveBg.withValues(alpha: 0.25)
                  : (lit ? t.itemHoverBg : null),
              borderRadius: AppRadii.xsAll,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(findingIcon(finding.kind),
                              size: 11, color: accent),
                          const SizedBox(width: 5),
                          Text(
                            findingLabel(finding.kind),
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const Spacer(),
                          if (showAnchor)
                            Text(
                              finding.anchor,
                              style: TextStyle(
                                color: t.textFaint,
                                fontSize: 9.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        finding.headline,
                        style: TextStyle(
                          color: active
                              ? t.textStrong
                              : (lit ? t.textNormal : t.textMuted),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: accent.withValues(
                        alpha: active ? 0.95 : (lit ? 0.7 : 0.45)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The pinned node's inspector, docked at the bottom so pin/unpin never shifts
/// the blocks above. Flat — a 2px accent tick down the left edge is the only
/// accent — with the filename leading over a faint directory line and the
/// plain-language account of where the node sits.
class _Inspector extends StatelessWidget {
  final String path;
  final String story;
  final VoidCallback onClear;
  const _Inspector({
    required this.path,
    required this.story,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Filename leads; the directory sits above it, middle-elided to the last two
    // segments so a long path doesn't wrap mid-word.
    final segs = path.split('/');
    final filename = segs.isEmpty ? path : segs.last;
    final dirSegs =
        segs.length > 1 ? segs.sublist(0, segs.length - 1) : const <String>[];
    final dir = dirSegs.isEmpty
        ? ''
        : (dirSegs.length <= 2
            ? dirSegs.join('/')
            : '…/${dirSegs.sublist(dirSegs.length - 2).join('/')}');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.4)),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('SELECTED',
                        style: TextStyle(
                          color: t.accentBright,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        )),
                    const Spacer(),
                    ChromeButton(
                      onTap: onClear,
                      borderRadius: AppRadii.xsAll,
                      padding: const EdgeInsets.all(3),
                      chromeBuilder: (
                              {required bool hovered, required bool pressed}) =>
                          ghostButtonChrome(t,
                              hovered: hovered,
                              pressed: pressed,
                              enabled: true,
                              baseBorderColor: Colors.transparent),
                      child: Icon(Icons.close_rounded,
                          size: AppIconSize.xs, color: t.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (dir.isNotEmpty)
                  Text(dir,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textFaint, fontSize: 10, height: 1.2)),
                Text(
                  filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 7),
                // Flexible + fade: when the docked inspector hits its height
                // cap on a short window, the story fades at the cut instead of
                // painting past the rail into the timeline.
                Flexible(
                  child: Text(
                    story,
                    overflow: TextOverflow.fade,
                    style: TextStyle(
                        color: t.textMuted, fontSize: 11, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: t.accentBright.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
