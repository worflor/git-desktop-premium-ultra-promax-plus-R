import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' as ui show Gradient;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/context_menu.dart';
import '../../ui/control_chrome.dart';
import '../../ui/horizontal_wheel.dart';
import '../../ui/design_primitives.dart';
import '../../ui/form_controls.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/resonance_text.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../backend/file_coupling.dart';
import '../../backend/logos_git.dart';
import '../../app/file_coupling_state.dart';
import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../changes/merge_conflict_flow.dart'
    show resolveSequencerConflicts, SequencerKind;
import '../../app/worktree_state.dart';
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';
import '../../backend/commit_fingerprint.dart';
import '../../backend/file_lifecycle.dart';
import '../diff/diff_shell.dart';
import 'commit_lede.dart';
import 'commit_seismograph.dart';
import 'commit_sigil.dart';
import 'commit_tag_pill.dart';
import 'commit_tagger.dart';
import 'worldline_field.dart';


const double _kNodeRadius = 3;

// ── WORLDLINE POSTURE constants (θ opens the strip into the sky) ────────────
//
// _kWorldlineDepthK: the perspective foreshortening. depthScale =
//   1 / (1 + k·depth·θ). Committed so the FURTHEST commit (depth=1) at full
//   open (θ=1) shrinks to ~0.55: solve 1/(1+k) = 0.55 → k = 0.818… → 0.82.
const double _kWorldlineDepthK = 0.82;
//
// _kWorldlineOpenFactor: the drawer-pull. Painted height = H0·(1 + f·θ), so
//   at θ=1 the strip stands at 3.2×H0 (f = 2.2). This same factor maps drag
//   pixels to θ (dθ = dy / (f·H0)), so the horizon bar tracks the finger 1:1.
const double _kWorldlineOpenFactor = 2.2;
//
// Fraction of the painted height reserved for the sky's vertical centre and
// amplitude. yCenter = H·0.46 leaves the caption band clear at the bottom;
// amp = H·0.36 lets u=±1 fill most of the opened panel without clipping.
const double _kWorldlineSkyCenterFrac = 0.46;
const double _kWorldlineSkyAmpFrac = 0.36;
//
// Bottom band that owns the drag-to-open gesture (the "caption bar" handle).
const double _kWorldlineHandleBand = 16;
//
// _kWorldlineDepthAlpha: alpha attenuation floor for the furthest dot,
// matched to the committed 0.55 SIZE target (1/(1+k) at depth=1) so both
// depth cues shrink in lockstep: alpha *= lerp(1, 0.55, depth·orn).
const double _kWorldlineDepthAlpha = 0.55;
//
// _kWorldlineAgeCap: how far age may pull a dot away from its OWN strip
// colour. Capped at 0.6 so even the oldest commit keeps ~40% of its
// churn/state identity — age modulates, never repaints.
const double _kWorldlineAgeCap = 0.6;
//
// Fling law for the caption-bar release: |vy| beyond this picks the detent
// in the fling direction regardless of position. 365 px/s is Flutter's own
// Drawer fling threshold (_kMinFlingVelocity in drawer.dart) — the same
// "drawer-pull" idiom this gesture borrows.
const double _kWorldlineFlingPxPerSec = 365.0;
//
// Release spring, θ-space, critically damped (no overshoot past a detent —
// θ clamps at both ends, so an overshoot would read as a bounce off the
// rim). Settle-to-2% for a critically damped spring is t ≈ 5.8/ω; the
// authored snap is ~190ms → ω ≈ 30 rad/s → stiffness = ω² = 900, damping
// = 2·√(k·m) = 60 at mass 1.
const SpringDescription _kWorldlineSpring = SpringDescription(
  mass: 1,
  stiffness: 900,
  damping: 60,
);

/// Ornament choreography: geometry (positions, panel height) rides θ
/// linearly, but ornament (polyline alpha, age tint, √churn radius blend,
/// depth attenuation) rides this smoothstep of (θ−0.25)/0.6 — the plane
/// opens first, the sky fades in after; closing reverses so ornament
/// leaves before the drawer shuts. Zero for all θ ≤ 0.25 (and so at θ=0).
double _worldlineOrnament(double theta) {
  final t = ((theta - 0.25) / 0.6).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Per-dot settle roll-in — the exact law of `_trackWakeProgress` in
/// commit_seismograph.dart: dot i's local progress maps the global settle
/// through a window starting at (i/n)·0.4 with width 0.6, so windows
/// overlap and the sweep travels along the time axis.
double _worldlineDotSettle(double global, int index, int count) {
  if (global >= 1.0) return 1.0;
  if (count <= 1) return global.clamp(0.0, 1.0);
  final start = (index / count) * 0.4;
  return ((global - start) / 0.6).clamp(0.0, 1.0);
}

/// Centripetal Catmull-Rom approximated as cubic Béziers — ported verbatim
/// from `_RidgelinePainter._catmullRom` in commit_seismograph.dart (same
/// repo, same math). Endpoint tangents reflect so the trace doesn't snap.
Path _catmullRom(List<Offset> p) {
  final path = Path()..moveTo(p.first.dx, p.first.dy);
  if (p.length == 2) {
    path.lineTo(p.last.dx, p.last.dy);
    return path;
  }
  for (var i = 0; i < p.length - 1; i++) {
    final p0 = i == 0 ? p[0] : p[i - 1];
    final p1 = p[i];
    final p2 = p[i + 1];
    final p3 = i + 2 < p.length ? p[i + 2] : p[i + 1];
    final c1 =
        Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
    final c2 =
        Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// Flat 2.5D projection of one commit from its strip position toward the
/// opened sky. x stays time; y opens into `coord.u`; `coord.depth` drives a
/// perspective scale that foreshortens the vertical excursion and (in the
/// painter) fades/shrinks far dots. [settle] eases the sky in when the field
/// lands mid-pull. At [theta] == 0 this is exactly the strip position, so the
/// rest posture is pixel-identical.
({Offset center, double depthScale}) _projectWorldline({
  required double xStrip,
  required double yStrip,
  required WorldlineCoord coord,
  required double theta,
  required double settle,
  required double height,
}) {
  if (theta <= 0) return (center: Offset(xStrip, yStrip), depthScale: 1.0);
  final yCenter = height * _kWorldlineSkyCenterFrac;
  final amp = height * _kWorldlineSkyAmpFrac;
  final uAmt = coord.u * settle;
  final depthEff = coord.depth * settle;
  final depthScale = 1.0 / (1.0 + _kWorldlineDepthK * depthEff * theta);
  final ySky = yCenter + uAmt * amp * theta * depthScale;
  final yProj = yStrip + (ySky - yStrip) * theta;
  return (center: Offset(xStrip, yProj), depthScale: depthScale);
}
const double _kVertInset = 8;
const double _kHorizPad = 4;
const double _kLeftPad = 6;

const int _kReservedLaneCount = 2;
const double _kMinLaneH = 42;
const double _kScaleFocus = 0.45;
const double _kScaleSelected = 1.25;
const double _kScaleHover = 1.1;
const double _kScaleMerge = 1.05;
const double _kGapLog = 1.1;
const double _kTemporalBlend = 0.32;
const double _kLensMin = 32;
const double _kLensMax = 64;
const int _kHistoryDefault = kDefaultHistoryCommits;

/// Ceiling the history window widens to when revealing a commit that sits
/// outside the loaded range (e.g. a palette search hit deep in history).
/// Bounds the one-shot expansion so an unreachable hash can't kick off an
/// unbounded load.
const int _kHistoryRevealCeiling = 5000;
const int _kHistoryMax = 500;


/// One hovered-desk preview list plus the PRECONDITIONS it was fetched
/// under. A cached value whose inputs aren't recorded can't know when it's
/// lying; carrying `rev` (the desk tip) and `limit` (the effective history
/// window) lets the hover path validate instead of trusting, so desk
/// activity and window changes invalidate for free.
class _PreviewCacheEntry {
  final List<CommitHistoryEntry> commits;
  final String rev;
  final int limit;
  const _PreviewCacheEntry(this.commits, {required this.rev, required this.limit});
}

class _GNode {
  final CommitHistoryEntry entry;
  final int row, lane;
  final List<String> visibleParents;
  /// True when this node represents a hovered-desk preview commit
  /// rather than a real ancestor of HEAD. Drives the painter's accent
  /// styling (halo + scaled core), the per-node stagger window, and
  /// the lens-metric exemption (preview nodes don't shift real-node
  /// positions). Real nodes default to false; nothing else needs to
  /// branch on this flag.
  final bool isPreview;
  const _GNode(
      {required this.entry,
      required this.row,
      required this.lane,
      required this.visibleParents,
      this.isPreview = false});
}

class _GEdge {
  final String from, to;
  final int fromRow, toRow, fromLane, toLane;
  const _GEdge(
      {required this.from,
      required this.to,
      required this.fromRow,
      required this.toRow,
      required this.fromLane,
      required this.toLane});
}

class _GLayout {
  final List<_GNode> nodes;
  final List<_GEdge> edges;
  final int laneCount;
  /// Lanes occupied by REAL commits (1 = single rail, 2 = trunk +
  /// diverged). Preview strands always take the lane AFTER these, so
  /// an in-flight overlay can never interleave with a real strand on
  /// the same rail.
  final int realLaneCount;
  /// Cached hash→nodes-index lookup. Built once at layout time so the
  /// painter can resolve `edge.from`/`edge.to` and z-priority sort
  /// indices in O(1) instead of walking the nodes list each paint.
  final Map<String, int> hashToIndex;
  const _GLayout({
    required this.nodes,
    required this.edges,
    required this.laneCount,
    required this.realLaneCount,
    required this.hashToIndex,
  });
}

class _LensMetric {
  final double x, y, scale;
  const _LensMetric(this.x, this.y, this.scale);
}


_GLayout _buildLayout(
  List<CommitHistoryEntry> entries, {
  Set<String>? trunkHashes,
  List<CommitHistoryEntry> previewCommits = const [],
}) {
  final visibleHashes = entries.map((e) => e.commitHash).toSet()
    ..addAll(previewCommits.map((e) => e.commitHash));
  final hashToNode = <String, _GNode>{};
  final nodes = <_GNode>[];

  // Lane plan first: real commits use lane 0 (trunk) and, when the
  // current branch has diverged from trunk, lane 1. The preview
  // strand ALWAYS takes the next free lane — never a lane real
  // commits sit on, so an in-flight overlay can't interleave with a
  // real strand.
  final hasDivergedReal = trunkHashes != null &&
      entries.any((e) => !trunkHashes.contains(e.commitHash));
  final realLaneCount = hasDivergedReal ? 2 : 1;
  final previewLane = realLaneCount;
  int laneCount = realLaneCount;

  for (int i = 0; i < previewCommits.length; i++) {
    final entry = previewCommits[i];
    final visibleParents = entry.parentHashes
        .where((h) => visibleHashes.contains(h))
        .toList();
    final node = _GNode(
      entry: entry,
      row: i,
      lane: previewLane,
      visibleParents: visibleParents,
      isPreview: true,
    );
    nodes.add(node);
    hashToNode[entry.commitHash] = node;
    laneCount = max(laneCount, previewLane + 1);
  }

  final realRowOffset = previewCommits.length;
  for (int i = 0; i < entries.length; i++) {
    final row = realRowOffset + i;
    final entry = entries[i];
    final parents =
        entry.parentHashes.where((h) => visibleHashes.contains(h)).toList();

    final lane = (trunkHashes != null &&
            !trunkHashes.contains(entry.commitHash))
        ? 1
        : 0;

    final node =
        _GNode(entry: entry, row: row, lane: lane, visibleParents: parents);
    nodes.add(node);
    hashToNode[entry.commitHash] = node;
  }

  final edges = <_GEdge>[];
  for (final node in nodes) {
    for (final ph in node.visibleParents) {
      final parent = hashToNode[ph];
      if (parent != null) {
        edges.add(_GEdge(
          from: node.entry.commitHash,
          to: ph,
          fromRow: node.row,
          toRow: parent.row,
          fromLane: node.lane,
          toLane: parent.lane,
        ));
      }
    }
  }

  final hashToIndex = <String, int>{
    for (var i = 0; i < nodes.length; i++) nodes[i].entry.commitHash: i,
  };
  return _GLayout(
      nodes: nodes,
      edges: edges,
      laneCount: laneCount,
      realLaneCount: realLaneCount,
      hashToIndex: hashToIndex);
}


List<double> _computePercents(List<CommitHistoryEntry> entries) {
  final n = entries.length;
  if (n == 0) return [];
  if (n == 1) return [50];

  final even = List.generate(n, (i) => (i / (n - 1)) * 100);
  final stamps = entries.map((e) {
    final p = DateTime.tryParse(e.authoredAt)?.millisecondsSinceEpoch;
    return p?.toDouble() ?? DateTime.now().millisecondsSinceEpoch.toDouble();
  }).toList();

  final rawGaps =
      List.generate(n - 1, (i) => max(1.0, (stamps[i] - stamps[i + 1]).abs()));
  final sorted = [...rawGaps]..sort();
  final median = sorted[sorted.length ~/ 2];
  final weighted = rawGaps
      .map((g) => max(0.4, min(12.0, 1 + log(1 + g / median) * _kGapLog)))
      .toList();
  final total = weighted.fold(0.0, (a, b) => a + b);

  final timePercents = [0.0];
  double cursor = 0;
  for (final w in weighted) {
    cursor += (w / max(total, 1)) * 100;
    timePercents.add(cursor);
  }

  final blended = List.generate(n, (i) {
    final t = timePercents[i];
    return even[i] * (1 - _kTemporalBlend) + t * _kTemporalBlend;
  });

  final bMin = blended.reduce(min), bMax = blended.reduce(max);
  final range = bMax - bMin;
  return blended
      .map((v) => range > 0 ? ((v - bMin) / range) * 100 : v)
      .toList();
}

/// Projects percent positions into pixel x. The newest and oldest REAL
/// commits pin to the drawable edges; preview nodes (indices below
/// [firstReal]) are never pinned — they land wherever their percents
/// put them, so a hover-preview can't yank a dot to the far-left edge.
List<double> _projectXs(
    int n, double width, List<double> percents, double lInset, double rInset,
    {int firstReal = 0}) {
  if (n == 0) return [];
  if (n == 1) return [width * 0.5];

  final minX = max(0.0, lInset);
  final maxX = max(minX, width - rInset);
  final drawable = max(0.0, maxX - minX);
  final pMin = percents.reduce(min), pMax = percents.reduce(max);
  final pRange = max(pMax - pMin, 1.0);

  return List.generate(n, (i) {
    if (i == firstReal) return minX;
    if (i == n - 1) return maxX;
    final norm = (percents[i] - pMin) / pRange;
    return minX + norm * drawable;
  });
}


List<_LensMetric> _lensMetrics({
  required List<_GNode> nodes,
  required List<double> baseXs,
  required double focusX,
  required String? selectedHash,
  required String? hoveredHash,
  required double width,
  required double vertInset,
  required double laneStep,
}) {
  if (nodes.isEmpty) return [];

  final spacingPx = width / max(nodes.length - 1, 1);
  final lensRadius = min(_kLensMax, max(_kLensMin, spacingPx * 2.8));

  double influence(double dist) {
    final n = min(dist / lensRadius, 1.0);
    return exp(-4 * n * n) * (1 - n * n);
  }

  return List.generate(nodes.length, (i) {
    final node = nodes[i];
    final bx = baseXs[i];
    final delta = bx - focusX;
    final gain = influence(delta.abs());

    double scale = 1 + gain * _kScaleFocus;
    if (node.entry.commitHash == selectedHash) scale *= _kScaleSelected;
    if (node.entry.commitHash == hoveredHash) scale *= _kScaleHover;
    if (node.entry.isMerge) scale *= _kScaleMerge;

    final y = vertInset + node.lane * laneStep + laneStep / 2;
    return _LensMetric(bx, y, scale);
  });
}


class _TimelinePainter extends CustomPainter {
  final _GLayout layout;
  final List<double> baseXs;
  final String? selectedHash;
  // Hover state comes in as Listenables so the painter can be wired to
  // `super(repaint: ...)` and repaint on pointer move without any
  // widget-tree rebuilds above it.
  final ValueListenable<String?> hoveredHashListenable;
  final ValueListenable<double?> hoverXListenable;
  final AppTokens tokens;
  final double width;
  final double height;
  final double vertInset;
  final double laneStep;
  final Map<String, double> churnNorm;
  final Map<String, double> netRatio;
  /// Pre-resolved per-hash churn target colors. The painter just lerps
  /// gray→target instead of doing the churn-axis lerp inside the paint
  /// loop on every frame.
  final Map<String, Color> targetColors;
  /// 0→1 fade animation. At 0 every node paints the gray fallback;
  /// at 1 it paints its computed churn color. Lerping between makes
  /// the gray→colored transition feel like a fill instead of a flip.
  final Animation<double> churnIntro;

  /// Hovered-desk preview commits. Painted as an ADDITIVE overlay on
  /// lane 1, ABOVE the main rail's lane 0 — they never enter the
  /// main layout pass so adding/removing them doesn't perturb the
  /// existing nodes' x-positions. Empty list = no overlay.
  final List<CommitHistoryEntry> previewCommits;

  /// 0→1 controller for the preview overlay's populate-in. Each
  /// preview node fades + scales in based on a per-index window
  /// derived from this single value, so a chip hover triggers a
  /// staggered cascade across the overlay without per-node
  /// AnimationControllers.
  final Animation<double> previewIntro;
  final Map<String, double> fileSpread;
  final Animation<double> resonance;
  final ValueListenable<String?> resonanceAuthorListenable;

  /// Commits reachable from HEAD but NOT from `@{upstream}` — the
  /// unpushed frontier. The rail segment they span tints stateAdded
  /// and a small tick marks the push boundary, so "what haven't I
  /// pushed" is readable without any interaction. Empty when the
  /// branch has no upstream (nothing to claim) or everything's pushed.
  final Set<String> localOnlyHashes;

  /// Hash-keyed commit details for the inline hover caption (+/−).
  final Map<String, CommitDetailData> detailByHash;

  /// Branch label of the previewed desk, prefixed onto the caption
  /// when hovering a preview dot.
  final String? previewLabel;

  /// The active theme's body font (from the inherited text style at
  /// build time). Canvas text doesn't inherit DefaultTextStyle, so
  /// without this the caption would render in the platform font and
  /// silently break per-theme typography.
  final String? captionFontFamily;
  final List<String>? captionFontFallback;

  /// WORLDLINE POSTURE. θ ∈ [0,1] opens the strip into the sky; the
  /// settle animation eases dots from the horizon into the sky. BOTH are
  /// live-read Listenables wired into `repaint:` (the same idiom hover
  /// uses) so a drag/spring/settle tick costs one repaint — never a
  /// widget rebuild or a fresh painter. [field] carries the per-commit
  /// structural coordinates (null until computed; changes arrive with a
  /// new painter via setState). At θ == 0 every worldline element
  /// contributes zero, so the strip paints identically to its rest
  /// posture. `handleHover` reveals the grip cue on the caption bar
  /// without perturbing the rest pixels.
  final ValueListenable<double> thetaListenable;
  final Animation<double> fieldSettle;
  final WorldlineField? field;
  final ValueListenable<bool> handleHoverListenable;

  _TimelinePainter({
    required this.layout,
    required this.baseXs,
    required this.selectedHash,
    required this.hoveredHashListenable,
    required this.hoverXListenable,
    required this.tokens,
    required this.width,
    required this.height,
    required this.vertInset,
    required this.laneStep,
    required this.churnNorm,
    required this.netRatio,
    required this.fileSpread,
    required this.targetColors,
    required this.churnIntro,
    required this.previewCommits,
    required this.previewIntro,
    required this.resonance,
    required this.resonanceAuthorListenable,
    required this.localOnlyHashes,
    required this.detailByHash,
    required this.previewLabel,
    required this.captionFontFamily,
    required this.captionFontFallback,
    required this.thetaListenable,
    required this.fieldSettle,
    required this.field,
    required this.handleHoverListenable,
  }) : super(
          repaint: Listenable.merge([
            hoveredHashListenable,
            hoverXListenable,
            churnIntro,
            previewIntro,
            resonance,
            handleHoverListenable,
            thetaListenable,
            fieldSettle,
          ]),
        );

  String? get hoveredHash => hoveredHashListenable.value;
  double? get hoverX => hoverXListenable.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty || baseXs.isEmpty) return;

    final focusX =
        hoverX ?? (selectedHash != null ? _selectedX() : width * 0.5);

    final metrics = _lensMetrics(
      nodes: layout.nodes,
      baseXs: baseXs,
      focusX: focusX,
      selectedHash: selectedHash,
      hoveredHash: hoveredHash,
      width: width,
      vertInset: vertInset,
      laneStep: laneStep,
    );

    // metricsMap removed — `metrics` is index-aligned with `layout.nodes`,
    // and the layout caches `hashToIndex` once at build time. Edge/node
    // lookups now resolve in O(1) with no per-paint Map allocation
    // (was ~500 string-keyed entries on a long history).
    final hashToIndex = layout.hashToIndex;

    // Total real (non-preview) node count for temporal gradient.
    final realNodeCount = layout.nodes.where((n) => !n.isPreview).length;

    // WORLDLINE projection. Precompute each node's opened center, depth
    // scale, and depth fraction once per paint. At theta == 0
    // `_projectWorldline` returns the exact strip position with
    // depthScale 1, so every worldline-gated branch below is a no-op and
    // the rest posture is pixel-identical. Geometry rides θ; ornament
    // (tints, radius blends, attenuation) rides the choreographed
    // smoothstep so the plane opens before the sky fades in.
    final worldT = thetaListenable.value.clamp(0.0, 1.0);
    final settleT = fieldSettle.value;
    final worldActive = worldT > 0.0005;
    final worldOrn = _worldlineOrnament(worldT);
    final centers = List<Offset>.filled(layout.nodes.length, Offset.zero);
    final depthScales = List<double>.filled(layout.nodes.length, 1.0);
    final depthFracs = List<double>.filled(layout.nodes.length, 0.0);
    final previewOffset0 = previewCommits.length;
    for (var i = 0; i < layout.nodes.length; i++) {
      final m = metrics[i];
      // Preview commits resolve to `absent` BY DESIGN: the field is keyed
      // to the displayed tip's window, and previews are another desk's
      // ahead-commits — outside that history by definition. They ride the
      // horizon while real commits open into the sky, which reads as
      // "hypothetical, not yet part of this trajectory". Computing their
      // coords would need a per-hovered-desk field build; not worth it.
      final coord = (worldActive && field != null)
          ? field!.coordFor(layout.nodes[i].entry.commitHash)
          : WorldlineCoord.absent;
      // Per-dot settle: the roll-in sweeps along the time axis (real
      // index order = time order) with overlapping windows.
      final dotSettle = _worldlineDotSettle(
          settleT, max(i - previewOffset0, 0), realNodeCount);
      final p = _projectWorldline(
        xStrip: m.x,
        yStrip: m.y,
        coord: coord,
        theta: worldT,
        settle: dotSettle,
        height: size.height,
      );
      centers[i] = p.center;
      depthScales[i] = p.depthScale;
      depthFracs[i] = coord.depth * dotSettle;
    }

    final previewFade = previewIntro.value;
    final railPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lanesUsed = <int>{};
    for (final n in layout.nodes) {
      lanesUsed.add(n.lane);
    }
    for (final lane in lanesUsed) {
      // Per-lane extents come from min/max over the lane's actual x
      // positions — NOT first/last node index. Preview nodes prepend
      // to the node list but sit mid-timeline, so index order and x
      // order disagree whenever a preview overlay is up.
      double laneMinX = double.infinity, laneMaxX = double.negativeInfinity;
      // Unpushed span within this lane (real nodes only).
      double localMinX = double.infinity, localMaxX = double.negativeInfinity;
      var laneHasReal = false;
      for (var i = 0; i < layout.nodes.length; i++) {
        final n = layout.nodes[i];
        if (n.lane != lane || i >= baseXs.length) continue;
        final x = baseXs[i];
        laneMinX = min(laneMinX, x);
        laneMaxX = max(laneMaxX, x);
        if (!n.isPreview) {
          laneHasReal = true;
          if (localOnlyHashes.contains(n.entry.commitHash)) {
            localMinX = min(localMinX, x);
            localMaxX = max(localMaxX, x);
          }
        }
      }
      if (laneMinX == double.infinity) continue;

      final isMain = lane == 0;
      final lx = max(laneMinX - _kNodeRadius, 0.0);
      final rx = min(laneMaxX + _kNodeRadius, width);
      final ry = vertInset + lane * laneStep + laneStep / 2;
      // A lane populated only by preview nodes breathes with the
      // preview intro — it fades in with its dots and back out with
      // them, instead of lingering as an orphaned line.
      final railAlpha = isMain
          ? 0.14
          : laneHasReal
              ? 0.08 + 0.06 * previewFade
              : 0.14 * previewFade;
      if (railAlpha <= 0.005) continue;
      railPaint
        ..color = isMain
            ? tokens.chromeAccent.withValues(alpha: railAlpha)
            : tokens.textMuted.withValues(alpha: railAlpha)
        ..strokeWidth = isMain ? 1.0 : 0.8;
      canvas.drawLine(Offset(lx, ry), Offset(rx, ry), railPaint);

      // Unpushed overlay: retint the rail across the local-only span
      // and drop a small vertical tick at the push frontier — the
      // seam between "only on this machine" and "on the remote".
      if (localMaxX > double.negativeInfinity) {
        railPaint
          ..color = tokens.stateAdded.withValues(alpha: isMain ? 0.45 : 0.30)
          ..strokeWidth = isMain ? 1.6 : 1.2;
        canvas.drawLine(
          Offset(max(localMinX - _kNodeRadius, 0.0), ry),
          Offset(min(localMaxX + _kNodeRadius, width), ry),
          railPaint,
        );
        // Frontier tick sits halfway between the oldest unpushed node
        // and the nearest pushed node to its right (x grows older).
        double pushedBeyond = double.infinity;
        for (var i = 0; i < layout.nodes.length; i++) {
          final n = layout.nodes[i];
          if (n.lane != lane || n.isPreview || i >= baseXs.length) continue;
          final x = baseXs[i];
          if (x > localMaxX && !localOnlyHashes.contains(n.entry.commitHash)) {
            pushedBeyond = min(pushedBeyond, x);
          }
        }
        if (pushedBeyond < double.infinity) {
          final tickX = (localMaxX + pushedBeyond) / 2;
          railPaint
            ..color = tokens.stateAdded.withValues(alpha: 0.55)
            ..strokeWidth = 1.4;
          canvas.drawLine(
              Offset(tickX, ry - 4), Offset(tickX, ry + 4), railPaint);
        }
      }
    }

    // A strand keeps exactly ONE connector into the real graph: the
    // oldest preview commit with a visible real parent (the base).
    // Preview merge commits also carry links to mid-rail main
    // commits, but drawing those sweeps long curves across the strand
    // at angles the synthetic preview window can't make honest —
    // they're the "weird connections" a hover overlay must never add.
    int previewBaseRow = -1;
    if (previewCommits.isNotEmpty) {
      for (final edge in layout.edges) {
        final fIdx = hashToIndex[edge.from];
        final tIdx = hashToIndex[edge.to];
        if (fIdx == null || tIdx == null) continue;
        if (layout.nodes[fIdx].isPreview && !layout.nodes[tIdx].isPreview) {
          previewBaseRow = max(previewBaseRow, layout.nodes[fIdx].row);
        }
      }
    }

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final edgePath = Path();
    final previewIntroT2 = previewIntro.value;
    final previewStaggerN =
        previewCommits.length <= 20 ? previewCommits.length : 20;
    final previewSlide2 =
        previewStaggerN > 0 ? 1.0 / previewStaggerN : 1.0;
    final previewOffset = previewCommits.length;

    for (final edge in layout.edges) {
      final fromIdx = hashToIndex[edge.from];
      final toIdx = hashToIndex[edge.to];
      if (fromIdx == null || toIdx == null) continue;
      final from = metrics[fromIdx];
      final to = metrics[toIdx];
      // Positions come from the projected centers (strip positions at rest);
      // scale still rides the lens metric.
      final fc = centers[fromIdx];
      final tc = centers[toIdx];
      final fromNode = layout.nodes[fromIdx];

      final isCrossLane = edge.fromLane != edge.toLane;
      final isMainline = !isCrossLane && edge.fromLane == 0;

      // Preview edges: in-strand links draw normally; the ONE base
      // connector renders as the same bezier every other cross-lane
      // edge uses — both endpoints are real positions, so the curve
      // lands on the actual fork commit instead of dropping a
      // context-free vertical at the child's x (the old behaviour,
      // which composed into a stray rectangle with the lane rails).
      // All other preview→real links are suppressed (see
      // previewBaseRow above).
      if (fromNode.isPreview) {
        if (previewFade <= 0.01) continue;
        final toNode = layout.nodes[toIdx];
        if (!toNode.isPreview && fromNode.row != previewBaseRow) continue;
      }

      final dx = tc.dx - fc.dx;
      final dy = tc.dy - fc.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.01) continue;
      final inv = 1.0 / dist;
      final fromR = _kNodeRadius * from.scale;
      final toR = _kNodeRadius * to.scale;
      final startX = fc.dx + dx * inv * fromR;
      final startY = fc.dy + dy * inv * fromR;
      final endX = tc.dx - dx * inv * toR;
      final endY = tc.dy - dy * inv * toR;

      edgePath.reset();
      edgePath.moveTo(startX, startY);
      if (isCrossLane) {
        final midX = (startX + endX) * 0.5;
        edgePath.cubicTo(midX, startY, midX, endY, endX, endY);
      } else {
        edgePath.lineTo(endX, endY);
      }

      // Temporal fade: edge inherits recency from its newer endpoint.
      final fromRealIdx = fromIdx - previewOffset;
      final edgeTemporal = realNodeCount <= 1 || fromRealIdx < 0
          ? 1.0
          : 1.0 - (fromRealIdx / (realNodeCount - 1)) * 0.5;

      double baseAlpha;
      double baseWidth;
      Color baseColor;
      if (fromNode.isPreview) {
        // Preview strand: same green as its dots so the whole overlay
        // reads as one incoming shape — connector included.
        baseColor = tokens.stateAdded;
        baseAlpha = isCrossLane ? 0.30 : 0.35;
        baseWidth = 1.1;
      } else if (isCrossLane) {
        baseColor = tokens.textMuted;
        baseAlpha = 0.22;
        baseWidth = 1.2;
      } else if (isMainline) {
        baseColor = tokens.chromeAccent;
        baseAlpha = 0.45;
        baseWidth = 1.6;
      } else {
        baseColor = tokens.textNormal;
        baseAlpha = 0.28;
        baseWidth = 1.2;
      }

      double alpha = baseAlpha * edgeTemporal;

      if (fromNode.isPreview && previewIntroT2 < 1.0) {
        final previewIdx = fromNode.row;
        final clampedIdx = previewIdx < previewStaggerN
            ? previewIdx
            : previewStaggerN - 1;
        final invertedIdx = previewStaggerN - 1 - clampedIdx;
        final nodeStart = invertedIdx * previewSlide2;
        var localT =
            ((previewIntroT2 - nodeStart) / previewSlide2).clamp(0.0, 1.0);
        localT = 1 - pow(1 - localT, 3).toDouble();
        if (localT <= 0) continue;
        alpha *= localT;
      }

      edgePaint
        ..color = baseColor.withValues(alpha: alpha)
        ..strokeWidth = baseWidth;
      canvas.drawPath(edgePath, edgePaint);
    }

    // WORLDLINE trace: a Catmull-Rom-smoothed thread through consecutive
    // commits — the worldline itself (same cubic-Bézier idiom as
    // _RidgelinePainter in commit_seismograph.dart). Ornament-gated
    // (absent at rest, fades in after the plane opens); age fade rides a
    // linear gradient along the time axis (newest = left = warmer/denser,
    // oldest = right = cooler/fainter) so one path keeps the per-segment
    // cooling the zigzag version had. Low alpha: a trace, not a wire.
    if (worldActive && worldOrn > 0.001 && realNodeCount >= 3) {
      final previewOff = previewCommits.length;
      final tracePts = centers.sublist(previewOff);
      final newest = tracePts.first;
      final oldest = tracePts.last;
      final wlPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.1
        ..shader = ui.Gradient.linear(newest, oldest, [
          tokens.chromeAccent.withValues(alpha: 0.34 * worldOrn),
          tokens.textMuted.withValues(alpha: 0.08 * worldOrn),
        ]);
      canvas.drawPath(_catmullRom(tracePts), wlPaint);
    }

    // Selected/hovered get z-priority (drawn last → on top). Skip the
    // O(n log n) sort + List allocation when nothing has priority,
    // which is the steady-state most paints — the painter receives
    // hover/select changes through the `repaint:` listenable so a
    // hover-tick still triggers a fresh paint with the sort enabled.
    final hasZPriority = selectedHash != null || hoveredHash != null;
    final List<_GNode> drawOrder;
    if (hasZPriority) {
      drawOrder = List.of(layout.nodes);
      drawOrder.sort((a, b) {
        int z(String h) => h == selectedHash
            ? 2
            : h == hoveredHash
                ? 1
                : 0;
        return z(a.entry.commitHash).compareTo(z(b.entry.commitHash));
      });
    } else {
      drawOrder = layout.nodes;
    }

    final nodeFillPaint = Paint()..style = PaintingStyle.fill;
    final selectedRingPaint = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final refRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final fallbackNodeColor = tokens.chromeBorder.withValues(alpha: 0.7);
    final selectedNodeColor = tokens.accentBright;
    final introValue = churnIntro.value;
    final introAtRest = introValue >= 1.0;
    final introAtStart = introValue <= 0.0;

    // Preview-stagger setup. Single shared controller drives the
    // populate-in across every preview node — each one carves out a
    // window from `previewIntro` based on its preview-index. When no
    // preview nodes exist (the steady state) the loop below pays
    // nothing for this — the per-node check is `if (node.isPreview)`
    // and the stagger math only runs inside that branch.
    final previewIntroT = previewIntro.value;
    final previewStaggerCount =
        previewCommits.length <= 20 ? previewCommits.length : 20;
    final previewSlide = previewStaggerCount > 0
        ? 1.0 / previewStaggerCount
        : 1.0;

    final resonanceT = resonance.value;
    final activeResonanceAuthor = resonanceAuthorListenable.value;

    for (final node in drawOrder) {
      final hash = node.entry.commitHash;
      final idx = hashToIndex[hash];
      if (idx == null) continue;
      final m = metrics[idx];
      final isSelected = hash == selectedHash;

      if (node.isPreview) {
        final previewIdx = node.row;
        final clampedIdx = previewIdx < previewStaggerCount
            ? previewIdx
            : previewStaggerCount - 1;
        final invertedIdx = previewStaggerCount - 1 - clampedIdx;
        final nodeStart = invertedIdx * previewSlide;
        var localT =
            ((previewIntroT - nodeStart) / previewSlide).clamp(0.0, 1.0);
        localT = 1 - pow(1 - localT, 3).toDouble();
        if (localT <= 0) continue;

        final center = centers[idx];
        final r = _kNodeRadius * m.scale;
        nodeFillPaint.color =
            tokens.stateAdded.withValues(alpha: 0.85 * localT);
        canvas.drawCircle(center, r, nodeFillPaint);
        // Preview dots answer touch the same way real ones do —
        // selection and hover rings, faded with the strand.
        if (isSelected) {
          canvas.drawCircle(center, r + 1.5, selectedRingPaint);
        } else if (hash == hoveredHash) {
          refRingPaint
            ..color = tokens.chromeAccent.withValues(alpha: 0.4 * localT)
            ..strokeWidth = 1.0;
          canvas.drawCircle(center, r + 2.6, refRingPaint);
        }
        continue;
      }

      final churn = churnNorm[hash] ?? 0.0;
      final spread = fileSpread[hash] ?? 0.0;
      final r = _kNodeRadius * m.scale * (1.0 + churn * 0.5 + spread * 0.4);

      final realIndex = idx - previewCommits.length;
      final temporal = realNodeCount <= 1 || realIndex < 0
          ? 1.0
          : 1.0 - (realIndex / (realNodeCount - 1)) * 0.4;

      final isResonant = activeResonanceAuthor != null &&
          node.entry.authorEmail == activeResonanceAuthor &&
          hash != hoveredHash;
      final resonanceBoost = isResonant ? 1.0 + 0.35 * resonanceT : 1.0;

      final Color nodeColor;
      if (isSelected) {
        nodeColor = selectedNodeColor;
      } else {
        final target = targetColors[hash];
        Color base;
        if (target == null) {
          base = fallbackNodeColor;
        } else if (introAtRest) {
          base = target;
        } else if (introAtStart) {
          base = fallbackNodeColor;
        } else {
          base = Color.lerp(fallbackNodeColor, target, introValue)!;
        }
        final alpha = (base.a * temporal * resonanceBoost).clamp(0.0, 1.0);
        nodeColor = base.withValues(alpha: alpha);
      }

      // Merge convergence: merges are structurally dense — slightly
      // larger fill so they read as junction points.
      final isMerge = node.entry.isMerge;
      var effectiveR = isMerge ? r * 1.12 : r;

      // WORLDLINE blend (ornament-gated, no-op at rest — worldOrn is 0
      // for all θ ≤ 0.25). Radius eases toward a √churn sizing
      // foreshortened by the commit's depth. Age MODULATES the dot's own
      // strip colour — a lerp toward the theme's cold token capped at
      // _kWorldlineAgeCap so even the oldest keeps ~40% of its churn/
      // state identity; never a wholesale repaint. Depth attenuates
      // alpha in lockstep with the 0.55 size target. Selected dots keep
      // their accent so selection stays legible.
      var fillColor = nodeColor;
      final center = centers[idx];
      if (worldActive && worldOrn > 0.001) {
        final coord = field?.coordFor(hash) ?? WorldlineCoord.absent;
        final ds = depthScales[idx];
        final worldR =
            _kNodeRadius * m.scale * (0.7 + 1.3 * coord.churn) * ds;
        effectiveR += (worldR - effectiveR) * worldOrn;
        if (!isSelected) {
          final ageFrac = realNodeCount <= 1 || realIndex < 0
              ? 0.0
              : realIndex / (realNodeCount - 1); // 0 = newest, 1 = oldest
          final cooled = Color.lerp(
              fillColor, tokens.textMuted, ageFrac * _kWorldlineAgeCap)!;
          final depthAtten = 1.0 -
              (1.0 - _kWorldlineDepthAlpha) * depthFracs[idx] * worldOrn;
          final aged = cooled.withValues(
              alpha: (fillColor.a * (1.0 - 0.35 * ageFrac) * depthAtten)
                  .clamp(0.0, 1.0));
          fillColor = Color.lerp(fillColor, aged, worldOrn)!;
        }
      }

      nodeFillPaint.color = fillColor;
      canvas.drawCircle(center, effectiveR, nodeFillPaint);

      if (isSelected) {
        canvas.drawCircle(center, effectiveR + 1.5, selectedRingPaint);
      }

      // Hover ring: a whisper of chrome under the cursor so the strip
      // answers touch before click. Skipped on the selected node —
      // its own ring already owns that slot.
      if (hash == hoveredHash && !isSelected) {
        refRingPaint
          ..color = tokens.chromeAccent.withValues(alpha: 0.4)
          ..strokeWidth = 1.0;
        canvas.drawCircle(center, effectiveR + 2.6, refRingPaint);
      }

      // Ref-tip ring: nodes with branch/tag refs get a subtle ring.
      // HEAD uses accentBright, tags use stateModified, other refs
      // use chromeAccent. The ring says "this node has a name."
      final refs = node.entry.refNames;
      final isHead = refs.any((n) => n.startsWith('HEAD'));
      if (refs.isNotEmpty && !isSelected) {
        final hasTag = refs.any((n) => n.startsWith('tag:'));
        refRingPaint
          ..color = isHead
              ? tokens.accentBright.withValues(alpha: 0.55 * temporal)
              : hasTag
                  ? tokens.stateModified.withValues(alpha: 0.40 * temporal)
                  : tokens.chromeAccent.withValues(alpha: 0.35 * temporal)
          ..strokeWidth = isHead ? 1.4 : 1.0;
        canvas.drawCircle(center, effectiveR + 2.0, refRingPaint);
      }

      // HEAD caret: a small downward wedge above the checked-out
      // commit — the one "you are here" that survives any amount of
      // churn color, ref rings, or preview noise. Clamped, never
      // culled: a hovered/selected HEAD magnifies enough to push the
      // ideal slot past the canvas top, and "you are here" vanishing
      // exactly when the user interacts with it would be backwards.
      // The wedge compresses against the top edge instead.
      if (isHead) {
        final tipY = center.dy - effectiveR - 2.5;
        final baseY = max(0.5, tipY - 4.6);
        if (tipY - baseY >= 1.5) {
          final caret = Path()
            ..moveTo(center.dx - 3.4, baseY)
            ..lineTo(center.dx + 3.4, baseY)
            ..lineTo(center.dx, tipY)
            ..close();
          nodeFillPaint.color = tokens.accentBright.withValues(alpha: 0.9);
          canvas.drawPath(caret, nodeFillPaint);
        }
      }
    }

    _paintHoverCaption(canvas, size);
    _paintGripCue(canvas, size);
  }

  /// The drag affordance on the caption bar: three faint dots at the
  /// bottom-centre. Painted ONLY while the handle is hovered or the strip
  /// is already open (θ>0), so the rest posture stays pixel-identical.
  void _paintGripCue(Canvas canvas, Size size) {
    final hovered = handleHoverListenable.value;
    final amt =
        max(hovered ? 1.0 : 0.0, thetaListenable.value.clamp(0.0, 1.0));
    if (amt <= 0.0005) return;
    final cx = size.width / 2;
    final cy = size.height - _kWorldlineHandleBand / 2;
    final dotPaint = Paint()
      ..color = tokens.chromeBorder.withValues(alpha: 0.16 * amt);
    for (final dx in const [-5.0, 0.0, 5.0]) {
      canvas.drawCircle(Offset(cx + dx, cy), 0.9, dotPaint);
    }
  }

  /// Inline hover caption, painted INTO the strip's own quiet bottom
  /// band — never an overlay, never a tooltip, can't cover anything.
  /// Layout is priority-ordered so nothing important falls off the
  /// right edge: the ↑ badge + hash always render; churn + meta
  /// right-align as a glance-stable tail and DROP (author first,
  /// then wholesale) before they'd collide; the subject takes
  /// whatever middle remains and ellipsizes. Appears only while a
  /// node is hovered or drag-scrubbed; the strip is silent otherwise.
  void _paintHoverCaption(Canvas canvas, Size size) {
    final hash = hoveredHash;
    if (hash == null) return;
    final idx = layout.hashToIndex[hash];
    if (idx == null) return;
    final node = layout.nodes[idx];
    final entry = node.entry;
    final t = tokens;

    const capSize = 9.5;
    const gap = 8.0;
    final monoStyle = TextStyle(
      color: t.accentBright,
      fontSize: capSize,
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallback,
      fontWeight: FontWeight.w700,
    );
    // Body spans follow the ACTIVE THEME's typography — canvas text
    // doesn't inherit DefaultTextStyle, so the family is threaded in
    // from the widget layer.
    final bodyStyle = TextStyle(
      color: t.textNormal,
      fontSize: capSize,
      fontWeight: FontWeight.w600,
      fontFamily: captionFontFamily,
      fontFamilyFallback: captionFontFallback,
    );
    final metaStyle = TextStyle(
      color: t.textMuted.withValues(alpha: 0.9),
      fontSize: capSize,
      fontFamily: captionFontFamily,
      fontFamilyFallback: captionFontFallback,
    );

    TextPainter tpOf(List<TextSpan> spans, {double? maxWidth}) {
      final tp = TextPainter(
        text: TextSpan(children: spans),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth ?? double.infinity);
      return tp;
    }

    // Head: ↑ badge (label capped so a novella of a branch name
    // can't eat the line) + short hash. Always painted.
    final headSpans = <TextSpan>[];
    if (node.isPreview) {
      var label = previewLabel ?? '';
      if (label.length > 24) label = '${label.substring(0, 23)}…';
      headSpans.add(TextSpan(
          text: label.isEmpty ? '↑  ' : '↑ $label  ',
          style: monoStyle.copyWith(color: t.stateAdded)));
    } else if (localOnlyHashes.contains(hash)) {
      headSpans.add(TextSpan(
          text: '↑  ', style: monoStyle.copyWith(color: t.stateAdded)));
    }
    headSpans.add(TextSpan(text: entry.shortHash, style: monoStyle));

    // Tail: meta + churn, right-aligned so the numbers sit in the
    // same spot for every commit you sweep across.
    List<TextSpan> tailSpans(bool withAuthor) {
      final spans = <TextSpan>[];
      final metaBits = <String>[
        if (withAuthor && entry.authorName.isNotEmpty) entry.authorName,
        _relAgeShort(entry.authoredAt),
        if (entry.isMerge) 'merge',
      ];
      spans.add(TextSpan(text: metaBits.join(' · '), style: metaStyle));
      final d = detailByHash[hash];
      if (d != null && (d.additions > 0 || d.deletions > 0)) {
        spans.add(TextSpan(
          text: '   +${d.additions}',
          style: monoStyle.copyWith(
              color: t.stateAdded.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600),
        ));
        spans.add(TextSpan(
          text: ' −${d.deletions}',
          style: monoStyle.copyWith(
              color: t.stateDeleted.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600),
        ));
      }
      return spans;
    }

    // Symmetric text insets: the head's origin sits at _kLeftPad + 2,
    // so the tail's right edge must mirror it at width − (_kLeftPad + 2).
    // The old maxW (width − 2·_kLeftPad) silently gave the right side a
    // 4px tighter inset and the churn numbers kissed the clip edge.
    final maxW = width - (_kLeftPad + 2) * 2;
    if (maxW < 40) return;
    // Head ellipsizes against the full band as a last resort so even
    // a pathologically narrow strip never paints past its edge.
    final head = tpOf(headSpans, maxWidth: maxW);

    // Degrade the tail before it can crowd the subject: full → no
    // author → gone.
    TextPainter? tail = tpOf(tailSpans(true));
    if (head.width + tail.width + gap * 2 + 60 > maxW) {
      tail = tpOf(tailSpans(false));
      if (head.width + tail.width + gap * 2 + 60 > maxW) tail = null;
    }

    final subjectAvail =
        maxW - head.width - gap - (tail == null ? 0 : tail.width + gap);
    final subject = subjectAvail > 12
        ? tpOf([TextSpan(text: entry.subject, style: bodyStyle)],
            maxWidth: subjectAvail)
        : null;

    final lineH = max(head.height, max(subject?.height ?? 0, tail?.height ?? 0));
    final y = size.height - lineH - 5;
    const x0 = _kLeftPad + 2;
    head.paint(canvas, Offset(x0, y + (lineH - head.height) / 2));
    subject?.paint(
        canvas,
        Offset(x0 + head.width + gap,
            y + (lineH - subject.height) / 2));
    tail?.paint(
        canvas,
        Offset(x0 + maxW - tail.width,
            y + (lineH - tail.height) / 2));
    // Every tpOf painter is local to this caption paint — release their
    // native (dart:ui) layouts now (this runs per repaint of the strip).
    head.dispose();
    subject?.dispose();
    tail?.dispose();
  }

  double _selectedX() {
    if (selectedHash == null) return width * 0.5;
    for (int i = 0; i < layout.nodes.length; i++) {
      if (layout.nodes[i].entry.commitHash == selectedHash) {
        return baseXs.length > i ? baseXs[i] : width * 0.5;
      }
    }
    return width * 0.5;
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      // Hover state changes route through the `repaint:` Listenable
      // so they don't need to be checked here — this method only fires
      // when the enclosing widget rebuilds with new structural props.
      old.selectedHash != selectedHash ||
      old.layout != layout ||
      old.baseXs != baseXs ||
      old.churnNorm != churnNorm ||
      old.netRatio != netRatio ||
      old.fileSpread != fileSpread ||
      old.localOnlyHashes != localOnlyHashes ||
      old.detailByHash != detailByHash ||
      // Identity, not length: the strip swaps the list reference on
      // every preview change, so a same-length different-desk swap
      // (18 commits → different 18 commits) still repaints.
      old.previewCommits != previewCommits ||
      // Caption inputs paint too — a label or inherited-font change
      // without a structural change must not leave a stale caption.
      old.previewLabel != previewLabel ||
      old.captionFontFamily != captionFontFamily ||
      old.captionFontFallback != captionFontFallback ||
      // Worldline: θ / settle / handleHover are live-read through
      // `repaint:` and never compared here. The FIELD is a plain value —
      // a new one arrives with a new painter (setState), so it must
      // repaint through this path.
      old.field != field;
}


class _TimelineStrip extends StatefulWidget {
  final List<CommitHistoryEntry> commits;
  final String? selectedHash;
  final ValueChanged<String> onSelected;
  final AppTokens tokens;
  final Map<String, CommitDetailData> detailCache;
  /// Monotonic counter the parent bumps on every `_detailCache`
  /// mutation. The map itself is mutated in place (same reference),
  /// so `old.detailCache.length` reads the post-mutation length —
  /// it can't detect cache changes. This counter is the only reliable
  /// "cache changed" signal at `didUpdateWidget` time.
  final int detailCacheVersion;

  /// Hashes reachable from the repo's default branch. When non-empty,
  /// the timeline splits into two lanes: commits in this set go on
  /// lane 0 (the trunk rail), commits not in it go on lane 1 (the
  /// diverged branch). Empty set = fall back to classic single-lane
  /// layout (same as before this feature existed).
  final Set<String> trunkHashes;

  /// Hovered-desk preview commits, prepended to [commits] when
  /// non-empty. These render with a short staggered crossfade so
  /// the timeline reads as "populating in" the desk's contribution
  /// while the chip is hovered. Off-trunk by construction (they're
  /// not reachable from HEAD), so they land on lane 1 via the
  /// existing trunk-aware assignment.
  final List<CommitHistoryEntry> previewCommits;

  /// Branch label of the desk feeding [previewCommits] — shown in the
  /// inline hover caption so preview dots identify themselves.
  final String? previewLabel;

  /// Commits not yet reachable from `@{upstream}`. Drives the
  /// unpushed rail tint + frontier tick and the caption's ↑ prefix.
  /// Empty when there's no upstream to compare against.
  final Set<String> localOnlyHashes;

  /// True when the IN FLIGHT strip is showing chips — i.e. a preview
  /// hover is POSSIBLE. The strip then reserves the preview lane's
  /// vertical space up front, so hovering a chip never changes the
  /// strip's height (the one layout shift a hover must never cause).
  final bool reservePreviewLane;

  /// Page-owned hover channel shared with the commit list. The strip
  /// writes into it from pointer events; the list's rows write into
  /// it from row hover. Because the painter already repaints off this
  /// listenable, a row hover lights its dot on the rail (ring + lens
  /// scale) with zero widget rebuilds — and a dot hover tints its row.
  /// Owned and disposed by the page, NOT this strip.
  final ValueNotifier<String?> hoverNotifier;

  /// Repo + window that key the Worldline structural field. Pulling the
  /// caption bar down opens the strip into the sky computed for exactly
  /// this repo's last [historyLimit] commits.
  final String repoPath;
  final int historyLimit;

  const _TimelineStrip({
    super.key,
    required this.commits,
    required this.selectedHash,
    required this.onSelected,
    required this.tokens,
    required this.detailCache,
    required this.detailCacheVersion,
    required this.hoverNotifier,
    required this.repoPath,
    required this.historyLimit,
    this.trunkHashes = const {},
    this.previewCommits = const [],
    this.previewLabel,
    this.localOnlyHashes = const {},
    this.reservePreviewLane = false,
  });

  @override
  State<_TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends State<_TimelineStrip>
    with TickerProviderStateMixin {
  // Pointer state held in ValueNotifiers — painter repaints via the
  // `repaint:` parameter on CustomPainter, bypassing widget rebuild
  // entirely. Was calling setState on every onPointerMove (60+/sec
  // during drag), rebuilding Container → Padding → Listener →
  // MouseRegion → CustomPaint every frame; now only the painter runs.
  final ValueNotifier<double?> _hoverXNotifier = ValueNotifier(null);
  bool _dragging = false;
  _GLayout? _layout;
  List<double> _percents = [];
  // Content signature, not length. Length-only cache keys missed:
  //   (a) growth without rebuilding churn maps → second half rendered
  //       gray because later hashes weren't in the (stale) churnNorm map
  //   (b) same-length-different-content updates (branch switch, filter
  //       toggle, HEAD moved) → layout + colors stayed stale
  // Signature combines length + first/last commit hash, which catches
  // every reasonable mutation while staying O(1) to compute.
  String _layoutSignature = '';
  Map<String, double> _churnNorm = {};
  Map<String, double> _netRatio = {};
  Map<String, double> _fileSpread = {};
  Map<String, Color> _churnTargetColors = const {};

  /// The preview list the layout + painter actually render. Tracks
  /// `widget.previewCommits` with one deliberate lag: when the widget
  /// list empties (hover left), the old list is RETAINED here while
  /// `_previewIntroCtrl` runs in reverse, so the overlay cascades out
  /// through the same stagger windows it cascaded in through — then
  /// clears for real. Direct assignment would pop every dot off in a
  /// single frame.
  List<CommitHistoryEntry> _shownPreview = const [];
  /// Generation guard: a fresh hover mid-exit invalidates the pending
  /// exit cleanup.
  int _previewGen = 0;

  /// Hash-keyed view of `widget.detailCache`, rebuilt alongside the
  /// churn maps. The painter's inline hover caption reads +/− from it.
  Map<String, CommitDetailData> _detailByHash = const {};

  static const Duration _churnAuthored = Duration(milliseconds: 320);
  static const Duration _previewAuthored = Duration(milliseconds: 1800);
  static const Duration _resonanceAuthored = Duration(milliseconds: 70);

  late final AnimationController _churnIntroCtrl = AnimationController(
    vsync: this,
    duration: _churnAuthored,
  );

  late final AnimationController _previewIntroCtrl = AnimationController(
    vsync: this,
    duration: _previewAuthored,
  );

  late final AnimationController _resonanceCtrl = AnimationController(
    vsync: this,
    duration: _resonanceAuthored,
  );
  final ValueNotifier<String?> _resonanceAuthorNotifier = ValueNotifier(null);

  // ── WORLDLINE POSTURE ──────────────────────────────────────────────────
  /// The single opening scalar. 0 = strip at rest, 1 = full spacetime view.
  /// Drives the panel height and the projection; the painter and the
  /// hit-test both read it, so the surface never disagrees with itself.
  final ValueNotifier<double> _theta = ValueNotifier(0.0);
  /// True while the caption-bar drag handle is hovered OR keyboard-focused
  /// — reveals the grip. Two independent input channels feed one cue, so
  /// they're tracked separately and OR-ed: a mouse exit must not hide the
  /// grip from a keyboard user parked on the handle, and vice versa.
  final ValueNotifier<bool> _handleHover = ValueNotifier(false);
  bool _handleHovered = false;
  bool _handleFocused = false;
  void _syncHandleCue() =>
      _handleHover.value = _handleHovered || _handleFocused;

  /// Derived posture bit for the handle's Semantics label ("open" vs
  /// "close"). A ValueNotifier so the label can rebuild through a scoped
  /// ValueListenableBuilder — it flips only when θ crosses 0.5 (twice per
  /// gesture at most), so the semantics wrapper never rides the per-tick
  /// animation the way the old whole-subtree AnimatedBuilder did.
  final ValueNotifier<bool> _postureOpen = ValueNotifier(false);
  void _syncPostureOpen() => _postureOpen.value = _theta.value > 0.5;

  /// The panel's painted height at the CURRENT θ. Pointer callbacks and
  /// the sizing builder both compute through this so no event handler
  /// ever captures a stale openHeight snapshot from build time.
  double _openHeightFor(double totalHeight) =>
      totalHeight * (1.0 + _kWorldlineOpenFactor * _theta.value);

  /// Release-spring / keyboard-toggle driver. UNBOUNDED: its value IS θ
  /// (clamped into [0,1] by [_tickSpring]) so a [SpringSimulation] can
  /// inherit the hand's release velocity directly in θ-space.
  late final AnimationController _thetaSpringCtrl =
      AnimationController.unbounded(vsync: this);

  /// One-shot settle: dots roll from the flat horizon into the sky, per-
  /// dot staggered along the time axis (see [_worldlineDotSettle]). Runs
  /// when the field lands mid-open AND on a detent-open with a warm
  /// field. ≤120ms total window; reduce-motion skips (value pinned to 1).
  late final AnimationController _fieldSettleCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );

  WorldlineField? _field;
  String _fieldKey = '';
  int _fieldGen = 0;
  // Failure memo. `_fieldKey` means "this request is handled" and a failed
  // load must NOT get to keep that claim (that made one transient git/isolate
  // hiccup flatten the window forever). But `_maybeLoadField` runs on every
  // build, so bare retry would hammer git while a failure persists. The memo
  // holds the line between the two: a failed key is skipped by builds and
  // released by the next OPEN GESTURE — retry is user-intent-driven, one
  // isolate per pull at worst, never one per frame.
  String _fieldFailedKey = '';

  /// Escape closes the open posture; focus is claimed on drag/toggle open.
  final FocusNode _stripFocus = FocusNode(skipTraversal: true);

  static String _signatureOf(List<CommitHistoryEntry> commits) {
    if (commits.isEmpty) return '';
    return '${commits.length}|${commits.first.commitHash}|${commits.last.commitHash}';
  }

  @override
  void initState() {
    super.initState();
    _shownPreview = widget.previewCommits;
    // Mounted mid-hover (e.g. repo strip rebuilt under the cursor):
    // show the overlay settled rather than replaying the entrance.
    if (_shownPreview.isNotEmpty) _previewIntroCtrl.value = 1.0;
    _thetaSpringCtrl.addListener(_tickSpring);
    _theta.addListener(_syncPostureOpen);
    // First field request — didUpdateWidget owns every subsequent one.
    _maybeLoadField();
  }

  void _tickSpring() {
    _theta.value = _thetaSpringCtrl.value.clamp(0.0, 1.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final churnScaled = context.motionRead(_churnAuthored);
    _churnIntroCtrl.duration =
        churnScaled == Duration.zero ? Duration.zero : churnScaled;
    final previewScaled = context.motionRead(_previewAuthored);
    _previewIntroCtrl.duration =
        previewScaled == Duration.zero ? Duration.zero : previewScaled;
    final resonanceScaled = context.motionRead(_resonanceAuthored);
    _resonanceCtrl.duration =
        resonanceScaled == Duration.zero ? Duration.zero : resonanceScaled;
  }

  int _resonanceGen = 0;

  void _updateResonance(String? hash) {
    if (_layout == null || hash == null) {
      if (_resonanceAuthorNotifier.value != null) {
        final gen = ++_resonanceGen;
        _resonanceCtrl.reverse().whenComplete(() {
          if (mounted && gen == _resonanceGen) {
            _resonanceAuthorNotifier.value = null;
          }
        });
      }
      return;
    }
    final idx = _layout!.hashToIndex[hash];
    if (idx == null || idx >= _layout!.nodes.length) return;
    final author = _layout!.nodes[idx].entry.authorEmail;
    if (author == _resonanceAuthorNotifier.value &&
        _resonanceCtrl.value > 0) {
      return;
    }
    ++_resonanceGen;
    _resonanceAuthorNotifier.value = author;
    _resonanceCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _hoverXNotifier.dispose();
    _resonanceAuthorNotifier.dispose();
    _churnIntroCtrl.dispose();
    _previewIntroCtrl.dispose();
    _resonanceCtrl.dispose();
    _thetaSpringCtrl.dispose();
    _fieldSettleCtrl.dispose();
    _theta.dispose();
    _handleHover.dispose();
    _postureOpen.dispose();
    _stripFocus.dispose();
    super.dispose();
  }

  // ── WORLDLINE gesture + field ───────────────────────────────────────────

  /// Load (or peek) the structural field for the current repo+window+tip.
  /// Warm on every relevant build; when it lands mid-open, ease it in.
  void _maybeLoadField() {
    if (widget.commits.isEmpty) return;
    final tip = widget.commits.first.commitHash;
    final key = worldlineFieldKey(widget.repoPath, widget.historyLimit, tip);
    if (key == _fieldKey || key == _fieldFailedKey) return;
    _fieldKey = key;
    final gen = ++_fieldGen;
    final warm = peekWorldlineField(widget.repoPath, widget.historyLimit, tip);
    if (warm != null) {
      _field = warm;
      _fieldSettleCtrl.value = 1.0; // already known → no migration
      return;
    }
    // Not ready: dots stay on the horizon until it lands.
    _field = null;
    _fieldSettleCtrl.value = 0.0;
    loadWorldlineField(widget.repoPath, widget.historyLimit, tip)
        .then((field) {
      if (!mounted || gen != _fieldGen) return;
      setState(() => _field = field);
      // If the user is already in the opened posture, ease the sky in;
      // otherwise it's just cached for the next pull.
      if (_theta.value > 0.0 && !context.reduceMotionRead) {
        _fieldSettleCtrl.forward(from: 0.0);
      } else {
        _fieldSettleCtrl.value = 1.0;
      }
    }).catchError((_) {
      if (!mounted || gen != _fieldGen) return;
      // Release the "handled" claim and memo the failure: the horizon
      // posture stays (empty field), but the request is retryable again
      // the next time the user pulls the strip open.
      setState(() {
        _field = WorldlineField.empty;
        _fieldFailedKey = key;
        _fieldKey = '';
      });
      _fieldSettleCtrl.value = 1.0;
    });
  }

  /// Map a vertical drag delta to θ. [restHeight] is H0 (the strip's rest
  /// height), so dragging down by dy grows the panel by exactly dy — the
  /// horizon bar tracks the finger (drawer-pull).
  void _dragTheta(double dy, double restHeight) {
    _thetaSpringCtrl.stop();
    final span = _kWorldlineOpenFactor * max(restHeight, 1.0);
    _theta.value = (_theta.value + dy / span).clamp(0.0, 1.0);
  }

  /// Drive θ to a detent with a critically-damped spring, inheriting
  /// [velocity] (θ-units/s) from the hand. Motion-rate scales the clock:
  /// ω′ = ω·rate ⇒ stiffness·rate², damping·rate (settle time ∝ 1/rate).
  /// Reduce-motion snaps. Opening from rest with a warm field replays the
  /// settle roll-in so the dots sweep into the sky on detent-open too.
  void _animateThetaTo(double target, {double velocity = 0}) {
    final opening = target > 0.5 && _theta.value < 0.05;
    if (context.reduceMotionRead) {
      _thetaSpringCtrl.stop();
      _theta.value = target;
      _fieldSettleCtrl.value = 1.0;
      return;
    }
    if (opening && _field != null && _fieldSettleCtrl.value >= 1.0) {
      _fieldSettleCtrl.forward(from: 0.0);
    }
    final rate = context.motionRateRead;
    final spring = rate == 1.0
        ? _kWorldlineSpring
        : SpringDescription(
            mass: _kWorldlineSpring.mass,
            stiffness: _kWorldlineSpring.stiffness * rate * rate,
            damping: _kWorldlineSpring.damping * rate,
          );
    _thetaSpringCtrl.animateWith(
        SpringSimulation(spring, _theta.value, target, velocity));
  }

  /// Release: a fling (|vy| ≥ the drawer threshold) picks the detent in
  /// the fling direction regardless of position and hands its momentum to
  /// the spring; a slow release keeps nearest-detent. [restHeight] is H0,
  /// so vy/(f·H0) converts pixel velocity into θ-space exactly as the
  /// drag itself maps pixels to θ.
  void _springToDetent(DragEndDetails d, double restHeight) {
    final vy = d.velocity.pixelsPerSecond.dy;
    final vTheta = vy / (_kWorldlineOpenFactor * max(restHeight, 1.0));
    final double target;
    if (vy.abs() >= _kWorldlineFlingPxPerSec) {
      target = vy > 0 ? 1.0 : 0.0; // pull down opens, push up closes
    } else {
      target = _theta.value < 0.5 ? 0.0 : 1.0;
    }
    _animateThetaTo(target, velocity: vTheta);
  }

  /// Keyboard / screen-reader activate: toggle open↔closed.
  void _toggleTheta() {
    final opening = _theta.value <= 0.5;
    if (opening) {
      // Claim focus only when nothing in the strip subtree holds it —
      // a pointer tap needs the claim so Esc works afterwards, but a
      // keyboard activation from the handle already has focus INSIDE the
      // subtree (Esc bubbles up from there), and stealing it would rip
      // the user off their tab position.
      if (!_stripFocus.hasFocus) _stripFocus.requestFocus();
      // Opening is the retry gesture, same as a pull (see drag start).
      if (_fieldFailedKey.isNotEmpty) {
        _fieldFailedKey = '';
        _maybeLoadField();
      }
    }
    _animateThetaTo(opening ? 1.0 : 0.0);
  }

  void _rebuildLayout() {
    final previewCount = _shownPreview.length;
    final trimmedReals = widget.commits;
    _layout = _buildLayout(
      trimmedReals,
      trunkHashes: widget.trunkHashes.isEmpty ? null : widget.trunkHashes,
      previewCommits: _shownPreview,
    );
    // Compute x-percents from main branch commits only. Preview
    // commits spread through a window ending at the fork point —
    // they're ahead commits that don't exist on this branch, so
    // there's no main-branch time range to interpolate into.
    final realPercents = _computePercents(trimmedReals);
    if (previewCount == 0) {
      _percents = realPercents;
    } else {
      // Fork anchor = the real parent of the DEEPEST strand commit
      // that has one visible — the same node the painter draws the
      // base connector from (see previewBaseRow). Scanning only the
      // oldest commit would misplace the strand whenever the true
      // merge-base sits beyond the loaded window but a mid-strand
      // merge still touches visible history.
      double forkPercent = realPercents.isEmpty ? 100.0 : realPercents.first;
      outer:
      for (var pi = _shownPreview.length - 1; pi >= 0; pi--) {
        for (final ph in _shownPreview[pi].parentHashes) {
          final idx = trimmedReals.indexWhere((e) => e.commitHash == ph);
          if (idx >= 0) {
            forkPercent = realPercents[idx];
            break outer;
          }
        }
      }
      // Run preview commits through the same timestamp-aware spacing
      // the main branch uses, then remap so the strand GROWS OUTWARD
      // FROM ITS BASE: the oldest preview commit always sits adjacent
      // to the fork it hangs off, and the strand extends toward newer
      // territory (leftward) from there. One invariant, two cases:
      //   room left of the fork  → strand occupies [fork−spread, fork]
      //   fork hugs the left edge → no newer territory exists, so the
      //     strand mirrors outward to [fork, fork+spread] instead —
      //     base STILL adjacent to the fork, no long backward
      //     connector sweeping across the rail. Local time direction
      //     inverts, which is the smaller lie: the strand reads as an
      //     outgrowth either way, and the base connector stays short.
      final rawPreview = _computePercents(_shownPreview);
      // Ideal room for the strand vs the bare minimum it can live in.
      // Time direction WINS whenever the left side is usable at all:
      // less room than ideal → the strand compresses leftward (the
      // lens makes dense dots hoverable). Only a fork pinned hard
      // against the newest edge — where leftward room is genuinely
      // unusable — mirrors the strand rightward from its base.
      final desiredSpread = min(38.0, max(10.0, previewCount * 2.2));
      final minUsable =
          min(desiredSpread, max(4.0, previewCount * 0.35));
      // A one-commit strand has no internal spacing to distribute —
      // _computePercents centers it at 50, which would float the dot
      // mid-window. Treat it as the base (p=100): adjacent to fork.
      double effP(double p) => previewCount == 1 ? 100.0 : p;
      final List<double> previewPercents;
      if (forkPercent >= minUsable) {
        final spread = min(desiredSpread, forkPercent);
        final lo = forkPercent - spread;
        previewPercents = rawPreview
            .map((p) => lo + (forkPercent - lo) * (effP(p) / 100.0))
            .toList();
      } else {
        final spanEnd =
            min(100.0, max(forkPercent, 0.0) + desiredSpread);
        previewPercents = rawPreview
            .map((p) =>
                forkPercent + (spanEnd - forkPercent) * (1 - effP(p) / 100.0))
            .toList();
      }
      _percents = [...previewPercents, ...realPercents];
    }
    _layoutSignature = _signatureOf(widget.commits);
    _rebuildChurnMaps();
  }

  void _rebuildChurnMaps() {
    final byHash = _byHash(widget.detailCache);
    final (norm, ratio, spread) =
        _computeChurnRatioSpread(widget.commits, byHash);
    // A preview hover/unhover rebuilds the layout but leaves churn
    // data untouched — replaying the gray→color intro then would
    // flash the ENTIRE rail on every chip hover. Only kick the fade
    // when the churn data itself moved.
    final churnChanged =
        !mapEquals(norm, _churnNorm) || !mapEquals(ratio, _netRatio);
    _detailByHash = byHash;
    _churnNorm = norm;
    _netRatio = ratio;
    _fileSpread = spread;
    // Pre-resolve target colors so the per-frame paint loop only does
    // one Color.lerp per node (gray→target) instead of two.
    final t = widget.tokens;
    final a = t.hypercubeNegative.withValues(alpha: 0.85);
    final b = t.hypercubePositive.withValues(alpha: 0.85);
    final out = <String, Color>{};
    norm.forEach((hash, _) {
      final tLerp = ratio[hash] ?? 0.5;
      out[hash] = Color.lerp(a, b, tLerp)!;
    });
    _churnTargetColors = out;
    if (!churnChanged) return;
    if (context.reduceMotionRead) {
      _churnIntroCtrl.value = 1.0;
    } else {
      _churnIntroCtrl.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_TimelineStrip old) {
    super.didUpdateWidget(old);
    final newSig = _signatureOf(widget.commits);
    // Lane assignment derives from trunk MEMBERSHIP (`contains` per commit
    // in _buildLayout), so invalidation must compare membership too. A
    // length shortcut misses same-cardinality swaps — branch switch or
    // trunk recompute exchanging hashes one-for-one kept stale lanes,
    // edges, and preview anchoring. setEquals is O(n) over a ≤window-sized
    // set, only on widget updates — exactness is affordable here. (Both
    // this branch and the plumbing line landed this fix independently.)
    final trunkChanged = !setEquals(old.trunkHashes, widget.trunkHashes);
    if (_signatureOf(old.commits) != newSig || trunkChanged) {
      // Real commits or trunk set changed → full layout invalidation.
      _layout = null;
    } else if (old.detailCacheVersion != widget.detailCacheVersion) {
      // Commits unchanged but cache mutated. The map is shared by
      // reference and mutated in place, so length/identity won't
      // change — only the parent-bumped version counter detects this.
      _rebuildChurnMaps();
    }
    _syncPreview();
    // Field lifecycle rides widget-update boundaries, not build. Every
    // input to the field key (repoPath, historyLimit, tip commit) arrives
    // through a widget update, so this is the complete set of trigger
    // points — build stays side-effect-free and the key guard inside
    // makes repeat calls a string compare.
    _maybeLoadField();
  }

  /// Preview overlay state machine. Signature match against
  /// `_shownPreview` (length + tip + tail — catches amends), three
  /// transitions:
  ///   fresh/replaced set → adopt it, relayout, stagger IN from 0
  ///   set emptied        → RETAIN the old set, run the intro in
  ///                        reverse so the cascade unwinds, then
  ///                        clear + relayout when it lands
  ///   no change          → nothing (steady state, incl. mid-exit
  ///                        frames where the widget list stays empty)
  void _syncPreview() {
    final incoming = widget.previewCommits;
    if (_signatureOf(incoming) == _signatureOf(_shownPreview)) return;
    final gen = ++_previewGen;
    if (incoming.isNotEmpty) {
      _shownPreview = incoming;
      _layout = null;
      if (context.reduceMotionRead) {
        _previewIntroCtrl.value = 1.0;
      } else {
        _previewIntroCtrl.forward(from: 0);
      }
      return;
    }
    // Exit: keep the outgoing commits in the layout while the shared
    // controller reverses through the per-node stagger windows.
    if (context.reduceMotionRead) {
      _previewIntroCtrl.value = 0;
      _shownPreview = const [];
      _layout = null;
      return;
    }
    _previewIntroCtrl.reverse().whenComplete(() {
      if (!mounted || gen != _previewGen) return;
      setState(() {
        _shownPreview = const [];
        _layout = null;
      });
    });
  }

  /// Nearest node by 2D distance. With the preview lane populated,
  /// two nodes can share an x — the pointer's y decides which lane
  /// the user means. Lane separation is small relative to horizontal
  /// density, so dy gets a modest weight rather than full Euclidean
  /// dominance.
  int? _nearestIndex(
      Offset pos, List<double> baseXs, double laneStep, double height) {
    if (baseXs.isEmpty || _layout == null) return null;
    // Preview dots are only pointer-targets while actually visible —
    // a strand mid-exit (or not yet populated in) shouldn't swallow
    // hovers and clicks aimed at the real rail behind it.
    final previewTargetable = _previewIntroCtrl.value > 0.35;
    // Hit-test against the SAME projected positions the painter draws, so
    // clicking a commit lands on it at every θ. At θ==0 the projection is
    // the identity, so this is byte-for-byte the original rail behaviour
    // (including the 1.4 dy lane-disambiguation weight).
    final theta = _theta.value;
    final worldActive = theta > 0.0005;
    final settle = _fieldSettleCtrl.value;
    final previewOff = _shownPreview.length;
    final realCount = _layout!.nodes.length - previewOff;
    // The 1.4 dy weight compensates the flat strip's anisotropy (lane
    // separation is small relative to horizontal density). The projection
    // dissolves lane structure LINEARLY in θ (yProj = yStrip + Δ·θ), so
    // the compensation must fade on the very same scalar — a boolean
    // regime switch here diverged from the painted geometry whenever the
    // field was still loading or the settle hadn't run (hit-testing with
    // opened weights against effectively-flat pixels). A weight that is a
    // function of the same θ that moves the dots cannot disagree with them.
    final dyWeight = 1.4 + (1.0 - 1.4) * theta;
    int nearest = -1;
    double best = double.infinity;
    for (int i = 0; i < baseXs.length && i < _layout!.nodes.length; i++) {
      final node = _layout!.nodes[i];
      if (node.isPreview && !previewTargetable) continue;
      final stripY = _kVertInset + node.lane * laneStep + laneStep / 2;
      final coord = (worldActive && _field != null)
          ? _field!.coordFor(node.entry.commitHash)
          : WorldlineCoord.absent;
      final proj = _projectWorldline(
        xStrip: baseXs[i],
        yStrip: stripY,
        coord: coord,
        theta: theta,
        // Same per-dot stagger the painter applies, so a click mid-roll
        // still lands on the dot where it's drawn.
        settle: _worldlineDotSettle(settle, max(i - previewOff, 0), realCount),
        height: height,
      );
      final dx = proj.center.dx - pos.dx;
      final dy = (proj.center.dy - pos.dy) * dyWeight;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    return nearest < 0 ? null : nearest;
  }

  void _selectNearest(
      Offset pos, List<double> baseXs, double laneStep, double height) {
    final i = _nearestIndex(pos, baseXs, laneStep, height);
    if (i == null) return;
    final hash = _layout!.nodes[i].entry.commitHash;
    widget.hoverNotifier.value = hash;
    widget.onSelected(hash);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.commits.isEmpty) return const SizedBox.shrink();

    if (_layout == null || _layoutSignature != _signatureOf(widget.commits)) {
      _rebuildLayout();
    }

    // Snapshot the theme's body font for the painter's caption —
    // canvas text can't inherit DefaultTextStyle on its own.
    final inheritedStyle = DefaultTextStyle.of(context).style;

    return Focus(
      focusNode: _stripFocus,
      onKeyEvent: _onStripKey,
      child: LayoutBuilder(builder: (ctx, constraints) {
      final width = max(constraints.maxWidth, 64.0);
      // Height is a function of RESERVED lanes, not currently-drawn
      // lanes: real lanes + one preview lane whenever chips exist.
      // A chip hover can therefore never change the strip's height —
      // the preview lane's space is already sitting there as quiet
      // surface before the cursor arrives.
      final reserved = max(
        _layout!.realLaneCount + (widget.reservePreviewLane ? 1 : 0),
        _kReservedLaneCount,
      );
      final laneCount = max(_layout!.laneCount, reserved);
      final height = max(_kMinLaneH, laneCount * 14.0 + 18.0);
      final laneStep =
          (height - _kVertInset * 2) / max(laneCount.toDouble(), 1);
      final totalHeight = height + _kVertInset * 2;

      // Unified x-projection: preview + real nodes share one percent list
      // computed in `_rebuildLayout`. Real commits are preserved; preview
      // nodes are inserted ahead of them, so hover can increase node
      // density instead of hiding older real history.
      final baseXs = _projectXs(
        _layout!.nodes.length,
        width,
        _percents,
        _kLeftPad + _kNodeRadius,
        // Mirror the left inset. A bare _kNodeRadius put the newest
        // commit's center one radius from the clip edge, so anything
        // wider than the base dot — selection ring, hover ring, the
        // worldline's churn-grown radius — painted half-clipped.
        _kLeftPad + _kNodeRadius,
        firstReal: _shownPreview.length,
      );
      // REPAINT, DON'T REBUILD. The panel physically grows with θ (the
      // drawer-pull): height eases from H0 (totalHeight) to 3.2×H0, so
      // exactly one thing must ride the θ tick: the SizedBox that sizes
      // the paint surface. Everything else — decorated surface, scrub
      // Listener, painter, handle band, semantics — is `content`, built
      // ONCE per widget build and re-parented through the sizing
      // builder's `child`. θ and settle reach the painter as live-read
      // Listenables wired into `repaint:` (the same idiom hover uses), so
      // a drag/spring/settle tick costs one box relayout + one repaint —
      // no subtree rebuild, no fresh painter. At θ==0 the height is
      // exactly totalHeight and nothing worldline-gated paints: the rest
      // posture stays byte-identical.
      final content = Container(
        decoration: BoxDecoration(
          color: widget.tokens.surface0,
          border: Border(
            bottom: BorderSide(
                color: widget.tokens.chromeBorder.withValues(alpha: 0.1)),
          ),
        ),
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kHorizPad),
            child: Listener(
              // Every callback derives the CURRENT open height via
              // _openHeightFor — no handler holds a θ snapshot from
              // build time, so hit-testing stays honest mid-animation.
              onPointerHover: (e) {
                _hoverXNotifier.value = e.localPosition.dx;
                final hash = _nearestHash(e.localPosition, baseXs,
                    laneStep, _openHeightFor(totalHeight));
                widget.hoverNotifier.value = hash;
                _updateResonance(hash);
              },
              onPointerDown: (e) {
                _hoverXNotifier.value = e.localPosition.dx;
                _dragging = true;
                _selectNearest(e.localPosition, baseXs, laneStep,
                    _openHeightFor(totalHeight));
              },
              onPointerMove: (e) {
                if (_dragging) {
                  _hoverXNotifier.value = e.localPosition.dx;
                  _selectNearest(e.localPosition, baseXs, laneStep,
                      _openHeightFor(totalHeight));
                }
              },
              onPointerUp: (_) => _dragging = false,
              // Wheel over the strip steps the selection one commit
              // at a time — scroll down walks older, up walks newer.
              onPointerSignal: (e) {
                if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) {
                  return;
                }
                _stepSelection(e.scrollDelta.dy > 0 ? 1 : -1);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onExit: (_) {
                  _hoverXNotifier.value = null;
                  widget.hoverNotifier.value = null;
                  _updateResonance(null);
                },
                // RepaintBoundary isolates the timeline's repaint
                // region so the header/siblings don't get
                // invalidated on every hover tick.
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      layout: _layout!,
                      baseXs: baseXs,
                      selectedHash: widget.selectedHash,
                      hoveredHashListenable: widget.hoverNotifier,
                      hoverXListenable: _hoverXNotifier,
                      tokens: widget.tokens,
                      width: width,
                      height: height,
                      vertInset: _kVertInset,
                      laneStep: laneStep,
                      churnNorm: _churnNorm,
                      netRatio: _netRatio,
                      fileSpread: _fileSpread,
                      targetColors: _churnTargetColors,
                      churnIntro: _churnIntroCtrl,
                      previewCommits: _shownPreview,
                      previewIntro: _previewIntroCtrl,
                      resonance: _resonanceCtrl,
                      resonanceAuthorListenable: _resonanceAuthorNotifier,
                      localOnlyHashes: widget.localOnlyHashes,
                      detailByHash: _detailByHash,
                      previewLabel: widget.previewLabel,
                      captionFontFamily: inheritedStyle.fontFamily,
                      captionFontFallback: inheritedStyle.fontFamilyFallback,
                      thetaListenable: _theta,
                      fieldSettle: _fieldSettleCtrl,
                      field: _field,
                      handleHoverListenable: _handleHover,
                    ),
                    // Fills the θ-sized surface (the outer SizedBox is the
                    // one thing that relayouts per tick), replacing the
                    // old per-tick `size:` reconstruction.
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          // The caption bar IS the drag handle: a thin band at the
          // bottom edge. Pull down to open the worldline, back up to
          // close. Activate (keyboard / screen-reader) toggles.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _kWorldlineHandleBand,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              onEnter: (_) {
                _handleHovered = true;
                _syncHandleCue();
              },
              onExit: (_) {
                _handleHovered = false;
                _syncHandleCue();
              },
              // Only the Semantics wrapper listens to the posture bit —
              // the label flips at the 0.5 crossing (twice per gesture,
              // not per tick) and the detector/gesture subtree passes
              // through `child` untouched.
              child: ValueListenableBuilder<bool>(
                valueListenable: _postureOpen,
                // THE keyboard path to the posture. The strip's own
                // focus node is skipTraversal (it's the Esc catcher,
                // not a tab stop), so without this detector the handle
                // was pointer-only despite its toggle contract. Tab
                // reaches it, the grip reveals on focus, Enter/Space
                // (default ActivateIntent bindings) toggle open↔closed,
                // and Esc bubbles from here to the strip Focus above.
                child: FocusableActionDetector(
                  onShowFocusHighlight: (f) {
                    _handleFocused = f;
                    _syncHandleCue();
                  },
                  actions: <Type, Action<Intent>>{
                    ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) {
                        _toggleTheta();
                        return null;
                      },
                    ),
                  },
                  child: GestureDetector(
                    // Opaque so a pull on the band is owned by the handle
                    // and never leaks through to the scrub Listener behind.
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      _thetaSpringCtrl.stop();
                      _stripFocus.requestFocus();
                      // A fresh pull releases any failure memo — the
                      // gesture is the retry.
                      if (_fieldFailedKey.isNotEmpty) {
                        _fieldFailedKey = '';
                        _maybeLoadField();
                      }
                    },
                    onVerticalDragUpdate: (d) =>
                        _dragTheta(d.primaryDelta ?? 0.0, totalHeight),
                    onVerticalDragEnd: (d) => _springToDetent(d, totalHeight),
                    onTap: _toggleTheta,
                  ),
                ),
                builder: (_, open, child) => Semantics(
                  button: true,
                  label:
                      open ? 'Close worldline' : 'Drag to open worldline',
                  onTap: _toggleTheta,
                  child: child,
                ),
              ),
            ),
          ),
        ]),
      );
      return ValueListenableBuilder<double>(
        valueListenable: _theta,
        child: content,
        builder: (_, __, child) => SizedBox(
          height: _openHeightFor(totalHeight),
          child: child,
        ),
      );
    }));
  }

  /// Escape springs the strip shut when it's open.
  KeyEventResult _onStripKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _theta.value > 0.0) {
      _animateThetaTo(0.0);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Moves the selection ±1 through the REAL commit list (previews
  /// are read-only). No-ops at either end.
  void _stepSelection(int dir) {
    final commits = widget.commits;
    if (commits.isEmpty) return;
    final sel = widget.selectedHash;
    final i = sel == null
        ? -1
        : commits.indexWhere((c) => c.commitHash == sel);
    final next = i == -1 ? 0 : (i + dir).clamp(0, commits.length - 1);
    if (next == i) return;
    widget.onSelected(commits[next].commitHash);
  }

  // Build hash→detail lookup from the repo-keyed cache
  static Map<String, CommitDetailData> _byHash(
      Map<String, CommitDetailData> cache) {
    final out = <String, CommitDetailData>{};
    for (final e in cache.entries) {
      // cache keys are "repoPath::hash" — extract hash after last '::'
      final sep = e.key.lastIndexOf('::');
      final hash = sep >= 0 ? e.key.substring(sep + 2) : e.key;
      out[hash] = e.value;
    }
    return out;
  }

  /// Single-pass churn + netRatio computation over a pre-built
  /// hash-keyed detail map (the caller retains that map for the
  /// inline hover caption, so it's built exactly once per rebuild).
  static (Map<String, double>, Map<String, double>, Map<String, double>)
      _computeChurnRatioSpread(
      List<CommitHistoryEntry> commits,
      Map<String, CommitDetailData> byHash) {
    final raws = <String, double>{};
    final ratio = <String, double>{};
    final spread = <String, double>{};
    for (final c in commits) {
      final d = byHash[c.commitHash];
      if (d == null) continue;
      final total = d.additions + d.deletions;
      ratio[c.commitHash] = total == 0 ? 0.5 : d.additions / total;
      if (total > 0) raws[c.commitHash] = log(total + 1);
      spread[c.commitHash] = min(1.0, d.filesChanged / 20.0);
    }
    if (raws.isEmpty) {
      return (const <String, double>{}, ratio, spread);
    }
    final maxVal = raws.values.reduce(max);
    if (maxVal == 0) {
      return (const <String, double>{}, ratio, spread);
    }
    final norm = <String, double>{};
    raws.forEach((k, v) => norm[k] = v / maxVal);
    return (norm, ratio, spread);
  }

  String? _nearestHash(
      Offset pos, List<double> baseXs, double laneStep, double height) {
    final i = _nearestIndex(pos, baseXs, laneStep, height);
    return i == null ? null : _layout!.nodes[i].entry.commitHash;
  }
}


/// Worktree path normalization shared by the IN FLIGHT surfaces —
/// separators unified; case-insensitive except on Linux.
String _normalizeDeskPath(String p) {
  final n = p.replaceAll('\\', '/');
  return Platform.isLinux ? n : n.toLowerCase();
}

/// Relative age for the strip's inline hover caption — one token.
String _relAgeShort(String iso) {
  try {
    final dt = DateTime.parse(iso);
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    return '${max(diff.inMinutes, 0)}m';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}


class _CommitImpact extends StatelessWidget {
  final CommitDetailData? detail;
  final AppTokens tokens;
  const _CommitImpact({required this.detail, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    if (detail == null) {
      return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              5,
              (_) => Container(
                    width: 6,
                    height: 3,
                    margin: const EdgeInsets.only(left: 1.5),
                    decoration: BoxDecoration(
                        color: t.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(0.5)),
                  )));
    }

    final adds = detail!.additions;
    final dels = detail!.deletions;
    final total = adds + dels;
    if (total == 0) return const SizedBox.shrink();

    final addBlocks = (adds / total * 5).round();

    return Row(mainAxisSize: MainAxisSize.min, children: [
      // +/- numbers
      Text('$adds',
          style: TextStyle(
              color: t.stateAdded.withValues(alpha: 0.9),
              fontSize: 9,
              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
              fontWeight: FontWeight.w700)),
      Text('/',
          style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.3),
              fontSize: 9,
              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
      Text('$dels',
          style: TextStyle(
              color: t.stateDeleted.withValues(alpha: 0.9),
              fontSize: 9,
              fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
              fontWeight: FontWeight.w700)),
      const SizedBox(width: 4),
      // 5-block bar
      Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: t.chromeBorder.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
              color: t.chromeBorder.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
                5,
                (i) => Container(
                      width: 6,
                      height: 3,
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 1.5),
                      decoration: BoxDecoration(
                        color: (i < addBlocks ? t.stateAdded : t.stateDeleted)
                            .withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(0.5),
                      ),
                    ))),
      ),
    ]);
  }
}


/// Input bundle for the off-main-isolate profile build. Must only
/// contain isolate-transferable types — `FileCouplingMatrix`,
/// `CommitHistoryEntry`, `CommitDetailData` are all plain data
/// classes so this is safe.
class _TagProfileInput {
  final List<CommitHistoryEntry> commits;
  final Map<String, CommitDetailData> details;
  final FileCouplingMatrix? coupling;
  /// Engine-derived multi-axis coherence per commit, computed on the
  /// main isolate before [compute] hands off (the LogosGit engine isn't
  /// trivially transferable, but a Map<String, double> is). When the
  /// engine isn't warm, this is null and the isolate falls back to the
  /// matrix's single-axis Jaccard.
  final Map<String, double>? engineCoherences;
  /// Per-commit expected-token distribution, computed on the main
  /// thread via [LogosGit.projectTokenDistribution] and summed per
  /// bucket inside the isolate.
  final Map<String, Map<String, double>>? expectedTokensByHash;
  const _TagProfileInput({
    required this.commits,
    required this.details,
    required this.coupling,
    this.engineCoherences,
    this.expectedTokensByHash,
  });
}

/// Returns commit-hash → expected-token distribution, computed by
/// diffusing each commit's file churn through [engine] and projecting
/// along the token axis. Main-thread because the engine isn't
/// isolate-transferable; the tagger sums these per-bucket downstream.
Map<String, Map<String, double>>? _projectPerCommitExpectedTokens(
  LogosGit engine,
  List<CommitHistoryEntry> commits,
  Map<String, CommitDetailData> detailsByHash,
) {
  // Same tokenizer + same per-commit unit-mass as _SubjectCorpus.
  // Both sides must match exactly or the projection math diverges.
  final fileTokens = <String, Map<String, double>>{};
  for (final c in commits) {
    final detail = detailsByHash[c.commitHash];
    if (detail == null) continue;
    final body = detail.body;
    final text = body.isEmpty ? c.subject : '${c.subject} $body';
    final tokens = tagTokenize(text);
    if (tokens.isEmpty) continue;
    final weight = 1.0 / tokens.length;
    for (final f in detail.files) {
      final row =
          fileTokens.putIfAbsent(f.path, () => <String, double>{});
      for (final w in tokens) {
        row.update(w, (v) => v + weight, ifAbsent: () => weight);
      }
    }
  }
  if (fileTokens.isEmpty) return null;

  // One Chebyshev diffusion per commit, seeded by log-scaled churn.
  final expectedByHash = <String, Map<String, double>>{};
  for (final c in commits) {
    final detail = detailsByHash[c.commitHash];
    if (detail == null) continue;
    final sourceWeights = <String, double>{};
    for (final f in detail.files) {
      final churn = (f.additions + f.deletions).toDouble();
      // Floor at 0.5 so a single-line commit still registers.
      final w = log(1.0 + churn);
      sourceWeights[f.path] = w > 0.5 ? w : 0.5;
    }
    if (sourceWeights.isEmpty) continue;
    final expected = engine.projectTokenDistribution(
      sourceWeights: sourceWeights,
      fileTokenCounts: fileTokens,
    );
    if (expected.isNotEmpty) {
      expectedByHash[c.commitHash] = expected;
    }
  }
  return expectedByHash.isEmpty ? null : expectedByHash;
}

/// Top-level so `compute()` can spawn it. Thin shim that just forwards
/// to [buildTagProfile]; the isolate boundary demands a top-level fn.
RepositoryTagProfile _tagProfileIsolate(_TagProfileInput input) {
  return buildTagProfile(
    commits: input.commits,
    detailsByHash: input.details,
    coupling: input.coupling,
    engineCoherences: input.engineCoherences,
    expectedTokensByHash: input.expectedTokensByHash,
  );
}


class HistoryPage extends StatefulWidget {
  final String? initialCommitHash;
  final VoidCallback? onOpenXray;

  /// Asks the workspace shell to navigate to the Changes page. Used by
  /// the in-flight desk ghost rows at the top of the commit list — a
  /// click there should land the user IN the work (the Changes panel of
  /// the desk they jumped to), not just on its History view. Optional
  /// — when null, the ghost rows just switch the active worktree and
  /// leave the user wherever they were.
  final VoidCallback? onOpenChanges;

  const HistoryPage({
    super.key,
    this.initialCommitHash,
    this.onOpenXray,
    this.onOpenChanges,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  List<CommitHistoryEntry> _commits = [];
  bool _loading = false;
  String? _error;
  String? _selectedHash;
  List<String> _selectedRefNames = const [];
  CommitDetailData? _detail;
  bool _detailLoading = false;
  String? _detailLoadingHash;
  String? _detailError;
  final Map<String, CommitDetailData> _detailCache = {};

  /// When set, the right pane shows the diff for this file from the
  /// currently-selected commit instead of the seismograph. Existing
  /// DiffShell engine handles the rendering. The sentinel
  /// [_kAllFilesPath] means "the entire commit's diff".
  String? _commitDiffFile;
  String? _commitDiffHash;
  String? _commitDiffContent;
  bool _commitDiffLoading = false;
  String? _commitDiffError;
  int _commitDiffReqId = 0;
  static const String _kAllFilesPath = '\u0000all\u0000';
  /// Bumped on every `_detailCache` mutation. The map is shared by
  /// reference with `_TimelineStrip`, so length/identity comparisons
  /// at `didUpdateWidget` can't see the mutation. This counter is the
  /// "cache changed" signal the timeline uses to refresh churn colors.
  int _detailCacheVersion = 0;

  /// Sidecar of structural fingerprints, keyed identically to
  /// `_detailCache`. Each entry is ~132 bytes (Float32List(25) +
  /// Uint32List(8)). Computed lazily on first detail render and
  /// retained as long as the detail itself; cleared with the cache
  /// when the repo / window changes.
  final Map<String, CommitSignature> _signatureCache = {};

  /// Per-file lifecycle classification (promotion × decay) derived
  /// from the active engine's stats. Recomputed when the engine
  /// rebuilds (HEAD movement, new repo). Cheap — one O(N log N) pass
  /// over the file universe; pinned on the engine's lifetime.
  Map<String, FileLifecycle>? _fileLifecycles;
  String? _fileLifecyclesForRepo;
  int? _fileLifecyclesForCommitCount;

  /// Auto-derived tag profile for the currently-loaded history window.
  /// Rebuilt in a background isolate whenever the commit set or detail
  /// cache materially grows (debounced — see [_scheduleTagProfileRebuild]).
  /// Every field is derived from this repo's own data; nothing is
  /// hardcoded.
  RepositoryTagProfile _tagProfile = RepositoryTagProfile.empty;

  /// Per-commit Born-mixed coherence, keyed by commit hash. Computed
  /// once per tag-profile rebuild on the main isolate (the LogosGit
  /// engine can't cross isolate boundaries) and held here so every
  /// visible row's tag computation does a single map lookup instead
  /// of a fresh `engine.coherence(files)` walk. Was costing
  /// ~300-500ms on a 500-row history page with 2-axis coherence
  /// recomputation per row.
  Map<String, double>? _cachedEngineCoherences;
  int _tagProfileBuildId = 0;
  Timer? _tagProfileDebounce;

  // Per-commit coherence cache. `engine.coherence(files)` is pure for
  // a given (engine manifold revision, commit's file set) — commits
  // are immutable once recorded, so hash-keyed caching is sound.
  // Without this, every tag-profile rebuild (search change, new
  // details arriving) paid the full O(commits × avg-degree) sweep,
  // dominated by commits that were already computed last time.
  // Clears whenever the engine's manifoldRevision advances.
  final Map<String, double> _coherencePerCommitCache = {};
  int _coherencePerCommitCacheRev = -1;

  // History limit — two separate meanings, deliberately never conflated:
  // `_historyLimit` is USER INTENT (the visible control, clamped to
  // _kHistoryMax) and `_revealWiden` is TRANSIENT SYSTEM STATE (a deep
  // reveal needing a wider window). Queries read the derived
  // [_effectiveHistoryLimit]; the widening dissolves on repo switch or
  // when the user reasserts a limit, so one deep reveal can never
  // permanently escalate every later query to the ceiling.
  int _historyLimit = _kHistoryDefault;
  int? _revealWiden;
  int get _effectiveHistoryLimit => max(_historyLimit, _revealWiden ?? 0);
  final _limitCtrl = TextEditingController(text: '$_kHistoryDefault');

  // Reveal target carried across the widen-and-reload hop. `_load`'s tail
  // re-enters `_revealCommit` with this hash (falling back to
  // widget.initialCommitHash), so a reveal requested imperatively — palette
  // search, didUpdateWidget — survives the reload instead of only working
  // while it happens to match the widget prop.
  String? _pendingRevealHash;

  // Scrolls the commit list so a revealed commit (a palette search hit) can be
  // brought into view once selected.
  final ScrollController _commitScroll = ScrollController();

  // Reflog
  List<ReflogEntryData> _reflog = [];
  bool _reflogLoaded = false;

  // Inline tag
  bool _tagInputVisible = false;
  String _tagInputValue = '';
  String? _tagError;
  final _tagCtrl = TextEditingController();
  Map<String, List<String>> _createdTags = {};
  Set<String> _deletedTags = {};
  // Stable FocusNode for the tag-input KeyboardListener. Previously a
  // fresh `FocusNode()` was constructed inline every rebuild while the
  // input was visible; each such node registered with Flutter's focus
  // system and was never disposed. Owning one on the state class keeps
  // the node alive exactly as long as the panel can show the input.
  final _tagEscapeFocus = FocusNode(debugLabel: 'history.tag-input.escape');

  // Shift-select rebase range
  int? _rebaseRangeEndIndex;
  bool get _isRebaseMode => _rebaseRangeEndIndex != null;

  /// Reaches the strip's posture from page chrome: the 'History' header
  /// text toggles the worldline open/closed. Same-file private State
  /// access — the header and the strip are two limbs of one surface.
  final GlobalKey<_TimelineStripState> _timelineStripKey = GlobalKey();

  String? _lastRepo;
  int _lastActivationEpoch = -1;

  /// Hashes reachable from the repo's default branch tip (main /
  /// master / whatever origin/HEAD points at). Passed into the top
  /// timeline's `_buildLayout` so commits that are shared with trunk
  /// render on lane 0 and commits diverged on the current branch
  /// render on lane 1 — the visual "we forked here" that's missing
  /// when the painter sees only a linear parent chain.
  /// Empty when we couldn't determine the default branch (detached,
  /// no origin, fresh repo) — the timeline falls back to classic
  /// single-lane rendering. Re-populated whenever [_load] runs.
  Set<String> _trunkHashes = const {};

  /// Currently-hovered desk path from the IN FLIGHT strip, or null
  /// when nothing's hovered. When set, the commit list and timeline
  /// "populate in" that desk's diverged commits with a staggered
  /// fade — live triage by geometry, the user sees what landing the
  /// hovered desk would add without leaving their current view.
  String? _previewDeskPath;
  /// Cached preview commit lists keyed by desk path. The fetch is
  /// `git log <desk-branch> ^HEAD` so we get exactly the diverged set.
  /// Entries are self-validating: each carries the desk rev and history
  /// limit it was fetched under, and the hover path treats a mismatch as
  /// a miss — so desk activity or a window change invalidates naturally,
  /// with no bookkeeping at the mutation sites. Cleared wholesale on repo
  /// switch (a different HEAD changes the meaning of every entry).
  final Map<String, _PreviewCacheEntry> _previewCommitsCache = {};

  /// The currently-hovered desk's preview commits, or empty. The single
  /// read path for all three consumers (timeline strip, list builder,
  /// scroll math) so they can never disagree about what's showing.
  List<CommitHistoryEntry> get _activePreviewCommits => _previewDeskPath == null
      ? const []
      : (_previewCommitsCache[_previewDeskPath]?.commits ?? const []);
  /// In-flight fetch guard so a quick mouse-trail across chips doesn't
  /// fire duplicate `git log` for the same desk.
  final Set<String> _previewLoadingDesks = <String>{};

  /// Branch label of the currently-previewed desk, for the timeline
  /// caption ("↑ orrery"). Retained through the exit grace window.
  String _previewBranch = '';

  /// Grace timer between chip hover-exit and preview teardown. A
  /// cursor sliding from one IN FLIGHT chip to the next (or briefly
  /// clipping a gap) shouldn't tear the whole overlay down and
  /// rebuild it 40ms later.
  Timer? _previewExitTimer;

  /// Commits reachable from HEAD but not from `@{upstream}` — exactly
  /// `git rev-list HEAD ^@{upstream}`. Feeds the timeline's unpushed
  /// rail tint + frontier tick, and the list rows' ↑ marker. Empty
  /// when the branch has no upstream.
  Set<String> _localOnlyHashes = const {};

  /// Hover channel shared between the timeline strip and the commit
  /// list. Strip pointer-hover and row hover both write here; the
  /// strip's painter and each visible row listen. Hovering a row
  /// lights its dot on the rail, hovering a dot tints its row — the
  /// two surfaces read as one object at two zoom levels.
  final ValueNotifier<String?> _railHover = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'history.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
  }

  @override
  void didUpdateWidget(HistoryPage old) {
    super.didUpdateWidget(old);
    final newHash = widget.initialCommitHash;
    if (newHash != null && newHash != old.initialCommitHash) {
      final repo = context.read<RepositoryState>().activePath;
      if (repo != null) {
        // Reveal even when the hit is outside the loaded window — it widens the
        // window and reloads rather than silently ignoring the selection.
        unawaited(_revealCommit(repo, newHash));
      }
    }
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _limitCtrl.dispose();
    _commitScroll.dispose();
    _railHover.dispose();
    _tagEscapeFocus.dispose();
    _tagProfileDebounce?.cancel();
    _previewExitTimer?.cancel();
    super.dispose();
  }

  /// Builds (or rebuilds) the tag profile off-main-isolate. Debounced
  /// at 200 ms so a burst of detail-cache fills (the bulk-prefetch
  /// pathway) coalesces into a single profile build. Every call bumps
  /// the build-id; late arrivals drop their result if a newer build
  /// has already landed. Coupling matrix is pulled at call time so
  /// the profile always reflects whatever's loaded by the
  /// `FileCouplingState` provider.
  void _scheduleTagProfileRebuild(String repoPath) {
    _tagProfileDebounce?.cancel();
    _tagProfileDebounce = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted || _commits.isEmpty) return;
      final myBuildId = ++_tagProfileBuildId;
      // Snapshot on the main isolate before handing off.
      final coupling =
          context.read<FileCouplingState>().matrixFor(repoPath);
      final commitsCopy = List<CommitHistoryEntry>.unmodifiable(_commits);
      final detailsCopy = <String, CommitDetailData>{
        for (final e in _detailCache.entries)
          // Strip the `$repoPath::` prefix so the tagger can key by
          // commit hash directly.
          if (e.key.startsWith('$repoPath::'))
            e.key.substring(repoPath.length + 2): e.value,
      };
      // If the LogosGit engine is warm for this repo, precompute its
      // multi-axis coherence per commit on the main isolate (it isn't
      // trivially transferable). The isolate then uses these values
      // instead of the raw Jaccard fallback — strictly more informative
      // percentile splits with no extra round-trip cost.
      Map<String, double>? engineCoherences;
      Map<String, Map<String, double>>? expectedTokensByHash;
      try {
        final engine =
            context.read<LogosGitState>().engineFor(repoPath);
        if (engine != null) {
          // Invalidate the per-commit cache when the engine has moved
          // on. Otherwise honour cached values; commits we've already
          // coherence-scored against the current manifold don't need
          // to repeat the CSR walk.
          if (_coherencePerCommitCacheRev != engine.manifoldRevision) {
            _coherencePerCommitCache.clear();
            _coherencePerCommitCacheRev = engine.manifoldRevision;
          }
          engineCoherences = <String, double>{};
          for (final entry in detailsCopy.entries) {
            final hash = entry.key;
            final cached = _coherencePerCommitCache[hash];
            if (cached != null) {
              engineCoherences[hash] = cached;
              continue;
            }
            final files = entry.value.files.map((f) => f.path);
            final value = engine.coherence(files);
            _coherencePerCommitCache[hash] = value;
            engineCoherences[hash] = value;
          }
          // Project per-commit expected-token distributions on the
          // main thread so the isolate has them ready.
          expectedTokensByHash =
              _projectPerCommitExpectedTokens(engine, commitsCopy, detailsCopy);
        }
      } catch (_) {
        // No state provider, no engine — silently fall back.
      }
      // Off-isolate build. The tagger is pure-Dart data crunch; safe
      // to send across the isolate boundary.
      final profile = await compute(_tagProfileIsolate, _TagProfileInput(
        commits: commitsCopy,
        details: detailsCopy,
        coupling: coupling,
        engineCoherences: engineCoherences,
        expectedTokensByHash: expectedTokensByHash,
      ));
      if (!mounted || myBuildId != _tagProfileBuildId) return;
      setState(() {
        _tagProfile = profile;
        _cachedEngineCoherences = engineCoherences;
      });
    });
  }

  /// Best-effort trunk ancestor lookup. Resolves the repo's default
  /// branch and grabs its reachable-commit set, matched to the same
  /// history depth the timeline renders so membership checks are
  /// honest (a smaller limit would drop some of the on-screen commits
  /// out of "trunk" even when they are ancestors — just deeper ones).
  /// Any failure is silent — returns an empty set and the timeline
  /// falls back to classic single-lane layout, same as for repos
  /// without a recognizable default branch.
  Future<Set<String>> _resolveTrunkHashes(String repo) async {
    final branch = await defaultBranchName(repo);
    if (!branch.ok || branch.data == null || branch.data!.isEmpty) {
      return const <String>{};
    }
    // Deeper than the history window on purpose: the visible list is
    // HEAD's newest N commits, and on a diverged branch K of those
    // are off-trunk — so the list reaches N−K deep into trunk while
    // a trunk walk of only N stops short by K. Matching limits would
    // misclassify the oldest on-screen trunk commits as "diverged"
    // and kink the rail's tail onto lane 1. 2× covers any K ≤ N.
    final r =
        await ancestorHashes(repo, branch.data!,
            limit: _effectiveHistoryLimit * 2);
    if (!r.ok || r.data == null) return const <String>{};
    return r.data!;
  }

  /// Exact unpushed set: `git log HEAD ^@{upstream}`. Errors (no
  /// upstream, detached HEAD, fresh repo) resolve to empty — the
  /// timeline simply doesn't claim anything about push state then.
  /// Using the exclusion walk instead of comparing two depth-limited
  /// ancestor sets keeps the answer honest at any history depth.
  Future<Set<String>> _resolveLocalOnly(String repo) async {
    final r = await listCommitsAhead(
      repo,
      branch: 'HEAD',
      excluding: '@{upstream}',
      limit: _effectiveHistoryLimit,
    );
    if (!r.ok || r.data == null) return const <String>{};
    return {for (final c in r.data!) c.commitHash};
  }

  Future<void> _load(String repo) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    // Fire the commit-history load, the trunk-ancestor lookup, and
    // the unpushed-set walk in parallel. Trunk + unpushed only feed
    // the top timeline — the commit list renders without them — so a
    // failure in either just falls through to the plainer rendering
    // without blocking the main load.
    final historyFuture =
        listCommitHistory(repo, limit: _effectiveHistoryLimit);
    final trunkFuture = _resolveTrunkHashes(repo);
    final localOnlyFuture = _resolveLocalOnly(repo);
    final r = await historyFuture;
    final trunk = await trunkFuture;
    final localOnly = await localOnlyFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _trunkHashes = trunk;
      _localOnlyHashes = localOnly;
      if (r.ok) {
        _commits = r.data!;
        _createdTags = {};
        _deletedTags = {};
      } else {
        _error = r.error;
      }
    });
    if (r.ok) {
      unawaited(_prefetchAllDetails(repo));
      _scheduleTagProfileRebuild(repo);
      // Ensure the coupling matrix is available for hub/focused/sprawl
      // tags. Idempotent if already loaded from the changes page.
      unawaited(
        context.read<FileCouplingState>().loadForRepo(repo),
      );
    }

    final initialHash = widget.initialCommitHash;
    // Pending (imperative) reveal wins over the widget prop; consume it so a
    // later unrelated _load doesn't replay a stale target.
    final revealHash = _pendingRevealHash ?? initialHash;
    _pendingRevealHash = null;
    if (revealHash != null) {
      // Reveal handles the outside-the-window case (widen + reload) instead of
      // silently skipping a hit that hasn't been loaded yet.
      await _revealCommit(repo, revealHash);
    }
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'history.snapshot.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: r.ok,
      errorCode: r.ok ? null : 'history.load_failed',
    );
  }

  Future<void> _openCommitFileDiff(String repo, String hash, String filePath) async {
    if (filePath == _commitDiffFile &&
        hash == _commitDiffHash &&
        !_commitDiffLoading) {
      return;
    }
    final reqId = ++_commitDiffReqId;
    setState(() {
      _commitDiffFile = filePath;
      _commitDiffHash = hash;
      _commitDiffContent = null;
      _commitDiffError = null;
      _commitDiffLoading = true;
    });
    final isAll = filePath == _kAllFilesPath;
    final r = isAll
        ? await getCommitDiff(repo, hash)
        : await getFileDiffAtRevision(repo, filePath, hash);
    if (!mounted || reqId != _commitDiffReqId) return;
    setState(() {
      _commitDiffLoading = false;
      if (r.ok) {
        _commitDiffContent = r.data;
      } else {
        _commitDiffError = r.error ?? 'failed to load diff';
      }
    });
  }

  void _openCommitAllDiff(String repo, String hash) =>
      _openCommitFileDiff(repo, hash, _kAllFilesPath);

  void _clearCommitDiffState() {
    _commitDiffFile = null;
    _commitDiffHash = null;
    _commitDiffContent = null;
    _commitDiffError = null;
    _commitDiffLoading = false;
  }

  void _closeCommitFileDiff() {
    setState(_clearCommitDiffState);
  }

  /// Lazy structural fingerprint per commit. Computed once per
  /// (repo + commit hash) and retained for the session — same diff
  /// always produces the same signature, so a cache hit is the
  /// common case once the user has scrolled the history.
  CommitSignature _signatureFor(CommitDetailData d) {
    final cached = _signatureCache[d.commitHash];
    if (cached != null) return cached;
    final fresh = computeCommitSignature(d);
    _signatureCache[d.commitHash] = fresh;
    return fresh;
  }

  /// Lazy per-file lifecycle map. Recomputed only when the engine
  /// itself rebuilds (HEAD movement on the active repo, repo switch).
  /// `engineFor(repoPath)` is the pre-warmed cache; the lifecycle
  /// classifier is one O(N log N) sweep on top.
  Map<String, FileLifecycle>? _lifecyclesFor(String repoPath) {
    final engine =
        context.read<LogosGitState>().engineFor(repoPath);
    if (engine == null) return null;
    final commitCount = engine.stats.totalCommits;
    if (_fileLifecycles != null &&
        _fileLifecyclesForRepo == repoPath &&
        _fileLifecyclesForCommitCount == commitCount) {
      return _fileLifecycles;
    }
    final fresh = classifyFileLifecycles(engine);
    _fileLifecycles = fresh;
    _fileLifecyclesForRepo = repoPath;
    _fileLifecyclesForCommitCount = commitCount;
    return fresh;
  }

  Future<void> _loadDetail(String repo, String hash) async {
    final stopwatch = Stopwatch()..start();
    // Check cache — key includes repo path to avoid cross-repo collisions
    final cacheKey = '$repo::$hash';
    final cached = _detailCache[cacheKey];
    // A cached entry with an empty body was written by the bulk prefetch,
    // which deliberately omits the body. Show it immediately for the file list
    // but fall through to fetch the full detail (body included).
    if (cached != null && cached.body.isNotEmpty) {
      if (_selectedHash != hash) return;
      setState(() {
        _detail = cached;
        _detailLoading = false;
        _detailLoadingHash = null;
        _detailError = null;
      });
      stopwatch.stop();
      await DiagnosticsState.instance.recordUiTiming(
        event: 'history.commit-detail.load',
        phase: 'interaction',
        durationMs: stopwatch.elapsedMicroseconds / 1000,
      );
      return;
    }
    if (_selectedHash != hash) return;
    setState(() {
      // Partial cache hit (bulk-prefetched, no body): show file stats now,
      // then upgrade with the full fetch below. All state set atomically to
      // avoid an intermediate frame with stale error or missing loading indicator.
      if (cached != null) _detail = cached;
      _detailLoading = true;
      _detailLoadingHash = hash;
      _detailError = null;
    });
    final r = await getCommitDetail(repo, hash);
    if (!mounted) return;
    if (_selectedHash != hash) return;
    setState(() {
      _detailLoading = false;
      _detailLoadingHash = null;
      if (r.ok) {
        _detail = r.data;
        // Only bump the timeline's cache version when the CHURN data
        // (additions/deletions) actually changes — not just when the
        // body fills in. Otherwise every single-commit click would
        // retrigger the gray→color fade on already-colored nodes,
        // because the version is the timeline's "anything changed"
        // signal. Body text doesn't affect churn colors.
        final old = _detailCache[cacheKey];
        final churnChanged = old == null ||
            old.additions != r.data!.additions ||
            old.deletions != r.data!.deletions;
        _detailCache[cacheKey] = r.data!;
        if (churnChanged) _detailCacheVersion++;
      } else {
        _detailError = r.error;
      }
    });
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'history.commit-detail.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: r.ok,
      errorCode: r.ok ? null : 'history.detail_failed',
    );
  }

  /// Silently pre-populates _detailCache for all loaded commits using two
  /// bulk git log passes. Uses putIfAbsent so individual fetches (which
  /// include body text) always win over bulk-fetched entries.
  Future<void> _prefetchAllDetails(String repo) async {
    final commits = List<CommitHistoryEntry>.from(_commits);
    if (commits.isEmpty) return;
    final r = await bulkGetCommitDetails(repo, commits,
        limit: _effectiveHistoryLimit);
    if (!mounted || !r.ok) return;
    // Bulk fill the cache, bump the version counter, then notify.
    // The version counter is the only reliable change-signal because
    // the map is shared by reference with `_TimelineStrip` and
    // mutated in place — length/identity comparisons there can't
    // detect "cache grew" since old.detailCache is the same object.
    var addedCount = 0;
    setState(() {
      for (final entry in r.data!.entries) {
        final key = '$repo::${entry.key}';
        if (!_detailCache.containsKey(key)) {
          _detailCache[key] = entry.value;
          addedCount++;
        }
      }
      if (addedCount > 0) _detailCacheVersion++;
    });
    // Bulk fill → richer profile. Debounce swallows the burst into one
    // rebuild so we don't thrash the isolate.
    if (addedCount > 0) _scheduleTagProfileRebuild(repo);
  }

  /// Right-click on a commit row → cherry-pick / revert. Both land as
  /// uncommitted changes on the current branch so the user can review
  /// before committing (git's default behaviour). Conflicts surface
  /// via the stderr bubbled into a snackbar; the user resolves in
  /// the Changes panel.
  void _showCommitContextMenu(
    BuildContext ctx,
    Offset globalPos,
    CommitHistoryEntry commit,
    String repoPath,
  ) {
    // Template the active branch into both labels. Naming the
    // destination (and using "changes" instead of "this") does the
    // teaching work that a tooltip would otherwise have to: the user
    // sees at a glance that ONLY the commit's diff moves, and WHERE
    // it lands. Falls back to "current branch" when status hasn't
    // loaded yet (e.g. on first paint) — still parseable.
    final branch =
        context.read<RepositoryState>().status?.branch ?? 'current branch';
    final items = <AppContextMenuItem>[
      AppContextMenuItem(
        icon: Icons.content_paste_go,
        label: "Apply commit's changes onto $branch",
        onTap: () => _cherryPick(repoPath, commit.commitHash),
      ),
      AppContextMenuItem(
        icon: Icons.undo,
        label: "Revert commit's changes on $branch",
        onTap: () => _revert(repoPath, commit.commitHash),
      ),
    ];
    showAppContextMenu(ctx, globalPos, [ListMenuSection(items)]);
  }

  Future<void> _cherryPick(String repoPath, String hash) async {
    final r = await cherryPickCommit(repoPath, hash);
    if (!mounted) return;
    final short = hash.length >= 8 ? hash.substring(0, 8) : hash;
    if (!r.ok) {
      // Conflicts → unified editor → `cherry-pick --continue`. Only a
      // genuine non-conflict failure (or a cancel) falls back to the error.
      final resolved =
          await resolveSequencerConflicts(context, repoPath, SequencerKind.cherryPick);
      if (!mounted) return;
      if (!resolved) {
        // If the cherry-pick is still in progress, the text conflicts were
        // resolved but unmergeable UU (binary/rename) remain — it's paused,
        // not failed. Don't mislabel a recoverable state.
        final paused = (await inProgressOperation(repoPath)) != null;
        if (!mounted) return;
        if (paused) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Cherry-pick paused. Finish the remaining conflicts "
                "on the Changes page."),
          ));
        } else {
          // Lead with the classified reason; keep raw stderr one tap away.
          final f = r.failure;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Cherry-pick failed: ${f?.message ?? r.error}"),
            action: f != null && f.detail.isNotEmpty && f.detail != f.message
                ? SnackBarAction(
                    label: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: f.detail)),
                  )
                : null,
          ));
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cherry-picked $short (resolved conflicts)")),
      );
      // The resolved pick created a commit — reload the history list (so it
      // appears) and refresh status, matching the revert path.
      await _load(repoPath);
      if (mounted) await context.read<RepositoryState>().refreshStatus();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Cherry-picked $short")),
    );
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _revert(String repoPath, String hash) async {
    final r = await revertCommit(repoPath, hash);
    if (!mounted) return;
    final short = hash.length >= 8 ? hash.substring(0, 8) : hash;
    if (!r.ok) {
      final resolved =
          await resolveSequencerConflicts(context, repoPath, SequencerKind.revert);
      if (!mounted) return;
      if (!resolved) {
        final paused = (await inProgressOperation(repoPath)) != null;
        if (!mounted) return;
        if (paused) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Revert paused. Finish the remaining conflicts on "
                "the Changes page."),
          ));
        } else {
          final f = r.failure;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Revert failed: ${f?.message ?? r.error}"),
            action: f != null && f.detail.isNotEmpty && f.detail != f.message
                ? SnackBarAction(
                    label: 'Copy',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: f.detail)),
                  )
                : null,
          ));
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Reverted $short (resolved conflicts)")),
      );
      await _load(repoPath);
      // A resolved revert creates a commit — refresh the status bar
      // (branch pill / ahead-behind), matching the cherry-pick path.
      if (mounted) await context.read<RepositoryState>().refreshStatus();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Reverted $short")),
    );
    await _load(repoPath);
  }

  /// Fired when the user hovers (or unhovers) an IN FLIGHT chip. Sets
  /// the preview path so the list + timeline render the desk's
  /// diverged commits with a staggered fade-in. Cache miss kicks an
  /// async fetch — the preview just stays empty until results land,
  /// then the populate animation runs as the data arrives.
  /// Preview teardown goes through a short grace window: chip→chip
  /// travel, chip→ghost-row travel, and accidental 1-frame exits keep
  /// the overlay alive instead of tearing it down and replaying the
  /// whole populate-in. Anything that re-enters preview territory
  /// (chip or ghost row) cancels the pending timer.
  void _schedulePreviewExit() {
    _previewExitTimer?.cancel();
    _previewExitTimer = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || _previewDeskPath == null) return;
      setState(() => _previewDeskPath = null);
    });
  }

  /// Hover state of the preview GHOST ROWS themselves. Entering a row
  /// sustains the preview (the rows are part of what's being
  /// previewed — walking down them must not dismiss them); leaving
  /// re-arms the same grace-window teardown the chip uses.
  void _onPreviewRowHover(bool hovering) {
    if (_previewDeskPath == null) return;
    if (hovering) {
      _previewExitTimer?.cancel();
    } else {
      _schedulePreviewExit();
    }
  }

  void _onPreviewDeskHover(
      String repoPath, String? deskPath, String rev, String label) {
    if (deskPath == null) {
      _schedulePreviewExit();
      return;
    }
    _previewExitTimer?.cancel();
    _previewBranch = label;
    if (deskPath != _previewDeskPath) {
      setState(() => _previewDeskPath = deskPath);
    }
    // Serve the cache only while its preconditions still hold — same desk
    // tip, same window. A desk that gained/lost commits or a widened limit
    // reads as a miss and refetches; the stale list keeps rendering during
    // the (fast) refetch instead of flashing empty.
    final limit = _effectiveHistoryLimit;
    final cached = _previewCommitsCache[deskPath];
    if (cached != null && cached.rev == rev && cached.limit == limit) return;
    if (_previewLoadingDesks.contains(deskPath)) return;
    if (rev.isEmpty) return;
    _previewLoadingDesks.add(deskPath);
    unawaited(() async {
      // `git log <branch> ^HEAD` — diverged set in branch order
      // (newest first). Same shape as our normal commit list so the
      // existing _CommitRow + timeline layout consume it without
      // special-casing.
      final r = await listCommitsAhead(
        repoPath,
        branch: rev,
        excluding: 'HEAD',
        limit: limit,
      );
      if (!mounted) return;
      _previewLoadingDesks.remove(deskPath);
      if (!r.ok) return;
      setState(() {
        _previewCommitsCache[deskPath] =
            _PreviewCacheEntry(r.data!, rev: rev, limit: limit);
      });
    }());
  }

  Future<void> _loadReflog(String repo) async {
    if (_reflogLoaded) return;
    final r = await listReflog(repo);
    if (!mounted) return;
    if (r.ok) {
      final existingHashes = _commits.map((c) => c.commitHash).toSet();
      setState(() {
        _reflog = r.data!
            .where((e) => !existingHashes.contains(e.commitHash))
            .toList();
        _reflogLoaded = true;
      });
    }
  }

  /// Open the reflog row's recovery menu. The single action is
  /// "Create branch from here…" — given a SHA from the reflog, prompt
  /// for a branch name and run `git checkout -b <name> <sha>`. Lets
  /// the user surface a "lost" commit (post-rebase, post-hard-reset,
  /// post-branch-delete) into a real branch they can navigate.
  void _showReflogRecoveryMenu(
    String repo,
    ReflogEntryData entry,
    Offset globalPos,
  ) {
    showAppContextMenu(context, globalPos, [
      ListMenuSection([
        AppContextMenuItem(
          icon: Icons.alt_route_outlined,
          label: 'Create branch from here…',
          onTap: () => _promptReflogRecoverBranch(repo, entry),
        ),
        AppContextMenuItem(
          icon: Icons.content_copy_outlined,
          label: 'Copy commit hash',
          onTap: () =>
              Clipboard.setData(ClipboardData(text: entry.commitHash)),
        ),
      ]),
    ]);
  }

  /// Show a small prompt dialog for the new branch name, default-
  /// seeded with `recover-<short-hash>`. On confirm: `createBranch`
  /// against the reflog entry's hash, surface success/failure via
  /// `_actionMessage`, refresh the branch state.
  Future<void> _promptReflogRecoverBranch(
    String repo,
    ReflogEntryData entry,
  ) async {
    final controller = TextEditingController(
      text: 'recover-${entry.shortHash}',
    );
    final t = context.tokens;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Create branch from reflog entry',
          style: TextStyle(color: t.textStrong, fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anchor: ${entry.shortHash}  ·  ${entry.actionSummary}',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: controller,
              hintText: 'branch name',
              autofocus: true,
              onSubmitted: (s) => Navigator.of(ctx).pop(s.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final res = await createBranch(repo, name, from: entry.commitHash);
    if (!mounted) return;
    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create branch: ${res.error}')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Branch "$name" created at ${entry.shortHash}.')),
    );
  }

  void _selectCommit(String? hash) {
    _selectedHash = hash;
    if (hash != null) {
      for (final c in _commits) {
        if (c.commitHash == hash) {
          _selectedRefNames = c.refNames;
          return;
        }
      }
    }
    _selectedRefNames = const [];
  }

  /// Bring [hash] into view: select it, load its detail, and scroll to it.
  /// When the commit sits outside the loaded window, widen the window once
  /// (to [_kHistoryRevealCeiling]) and reload — a reachable-but-deep commit
  /// then comes into range and `_load`'s tail re-enters this reveal. A commit
  /// unreachable from HEAD never will, so we surface feedback rather than
  /// silently doing nothing.
  Future<void> _revealCommit(String repo, String hash) async {
    if (_commits.any((c) => c.commitHash == hash)) {
      setState(() => _selectCommit(hash));
      await _loadDetail(repo, hash);
      _scrollToCommit(hash);
      return;
    }
    if (_effectiveHistoryLimit < _kHistoryRevealCeiling) {
      _pendingRevealHash = hash;
      // Transient widening only — the user's chosen limit (and its control)
      // stay untouched; queries read the derived effective limit while the
      // widening lives, and it dissolves on repo switch or limit resubmit.
      setState(() => _revealWiden = _kHistoryRevealCeiling);
      await _load(repo); // its tail re-enters reveal with the pending hash
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('That commit is deeper than the '
          '$_kHistoryRevealCeiling commits loaded.'),
    ));
  }

  /// Proportional scroll to the row for [hash]. Commit rows are near-uniform
  /// height, so mapping the target's ROW (not commit index) across the
  /// scrollable extent lands it in view without a hardcoded row height. The
  /// row space mirrors the list builder exactly: desk-preview rows sit above
  /// the commits and the reflog section (plus its header) sits below, so both
  /// offsets must be counted or the scroll lands short whenever a preview
  /// strand is showing. Post-framed so the list is laid out (its extent
  /// known) before we move.
  void _scrollToCommit(String hash) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_commitScroll.hasClients) return;
      final idx = _commits.indexWhere((c) => c.commitHash == hash);
      if (idx < 0) return;
      final previewCount = _activePreviewCommits.length;
      final trailingRows = _reflogLoaded ? _reflog.length + 1 : 1;
      final totalRows = previewCount + _commits.length + trailingRows;
      if (totalRows < 2) return;
      final frac = (previewCount + idx) / (totalRows - 1);
      final target = frac * _commitScroll.position.maxScrollExtent;
      _commitScroll.animateTo(
        target,
        duration: context.motion(AppMotion.snap),
        curve: AppMotion.snapCurve,
      );
    });
  }

  void _onCommitTap(int index, bool shiftKey) {
    final hash = _commits[index].commitHash;
    if (shiftKey && _selectedHash != null && _selectedHash != hash) {
      setState(() => _rebaseRangeEndIndex = index);
    } else {
      setState(() {
        _selectCommit(hash);
        _rebaseRangeEndIndex = null;
        _tagInputVisible = false;
        _tagInputValue = '';
        _tagError = null;
        _clearCommitDiffState();
      });
      final repo = context.read<RepositoryState>().activePath;
      if (repo != null) _loadDetail(repo, hash);
    }
  }

  List<String> _gitTagsForHash(String hash, List<String> refNames) {
    final fromRefs = refNames
        .where((r) => r.startsWith('tag:'))
        .map((r) => r.replaceFirst('tag: ', ''))
        .toList();
    final created = _createdTags[hash];
    if (created != null) {
      final existing = fromRefs.toSet();
      for (final t in created) {
        if (!existing.contains(t)) fromRefs.add(t);
      }
    }
    if (_deletedTags.isNotEmpty) {
      fromRefs.removeWhere(_deletedTags.contains);
    }
    return fromRefs;
  }

  Future<void> _createTag(String repo, String hash) async {
    final name = _tagInputValue.trim();
    if (name.isEmpty) return;
    final r = await createTag(repo, name, hash);
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _tagInputVisible = false;
        _tagInputValue = '';
        _tagCtrl.clear();
        _tagError = null;
        _deletedTags.remove(name);
        (_createdTags[hash] ??= []).add(name);
      });
    } else {
      setState(() => _tagError = r.error);
    }
  }

  Future<void> _deleteTag(String repo, String name) async {
    final r = await deleteTag(repo, name);
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _deletedTags.add(name);
        for (final list in _createdTags.values) {
          list.remove(name);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete tag: ${r.error}')),
      );
    }
  }

  void _onLimitSubmit(String value) {
    final n = int.tryParse(value.trim());
    if (n == null) {
      _limitCtrl.text = '$_historyLimit';
      return;
    }
    final clamped = n.clamp(1, _kHistoryMax);
    setState(() {
      _historyLimit = clamped;
      // The user reasserted their window — any transient reveal widening
      // yields to it.
      _revealWiden = null;
    });
    _limitCtrl.text = '$clamped';
    final repo = context.read<RepositoryState>().activePath;
    if (repo != null) _load(repo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // History page only rebuilds when the active repo changes —
    // `git status` ticks no longer invalidate the whole history tree.
    final repoSelect = context.select<RepositoryState, (String?, int)>(
      (s) => (s.activePath, s.activationEpoch),
    );
    final repoPath = repoSelect.$1;
    final activationEpoch = repoSelect.$2;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    // Subscribe to the coupling matrix so tag profiles rebuild when it
    // arrives (hub, focused/sprawl, borrowed tags depend on it).
    final couplingReady = context.select<FileCouplingState, bool>(
      (s) => s.matrixFor(repoPath) != null,
    );

    // Whether ANY other desk is in flight. The timeline pre-reserves
    // its preview lane off this, so a chip hover can never change the
    // strip's height. Narrowed to a bool — desk activity ticks only
    // rebuild the page when the answer flips.
    final hasInFlightDesks = context.select<WorktreeState, bool>((s) {
      final activeNorm = _normalizeDeskPath(repoPath);
      for (final d in s.desks) {
        if (_normalizeDeskPath(d.path) == activeNorm) continue;
        if ((s.activityFor(d.path)?.ahead ?? 0) > 0) return true;
      }
      return false;
    });
    if (couplingReady && _tagProfile.commitCount > 0 && _commits.isNotEmpty) {
      _scheduleTagProfileRebuild(repoPath);
    }

    if (_lastRepo != repoPath) {
      _lastRepo = repoPath;
      _lastActivationEpoch = activationEpoch;
      _commits = [];
      _reflog = [];
      _reflogLoaded = false;
      // Reveal widening is per-repo transient state — a deep dive in one
      // repo must not inflate every query in the next.
      _revealWiden = null;
      _pendingRevealHash = null;
      _detail = null;
      _selectCommit(null);
      _clearCommitDiffState();
      // Commit detail is keyed by (repo?, hash) internally — but the
      // cache isn't qualified by repo, so without an explicit clear a
      // hash that existed in the outgoing repo could briefly paint
      // detail from THAT repo's commit into the incoming repo's view.
      // Clear the cache alongside the selection so nothing stale can
      // leak across the repo-switch boundary.
      _detailCache.clear();
      _detailCacheVersion++;
      // Preview commits fetched against the OLD repo's HEAD have no
      // meaning here — drop them so a chip hover after the switch
      // re-fetches against the new repo's HEAD instead of replaying
      // a stale list.
      _previewCommitsCache.clear();
      _previewLoadingDesks.clear();
      _previewDeskPath = null;
      _previewExitTimer?.cancel();
      _localOnlyHashes = const {};
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(repoPath));
    } else if (_lastActivationEpoch != activationEpoch) {
      _lastActivationEpoch = activationEpoch;
      if (_commitDiffFile != null) {
        _clearCommitDiffState();
      }
      // Re-activation is the natural "did I push since" checkpoint —
      // refresh the unpushed set quietly so the rail tint doesn't
      // claim stale local-only state after a push happened elsewhere.
      unawaited(_resolveLocalOnly(repoPath).then((s) {
        if (!mounted || setEquals(s, _localOnlyHashes)) return;
        setState(() => _localOnlyHashes = s);
      }));
    }

    if (_loading && _commits.isEmpty) {
      return const AppStatusView.loading(
        title: 'Loading history',
        message: 'Reading recent commits.',
      );
    }

    if (_error != null) {
      return AppStatusView.error(
        title: 'History unavailable',
        message: _error!,
      );
    }

    final selectedIndex = _selectedHash != null
        ? _commits.indexWhere((c) => c.commitHash == _selectedHash)
        : -1;
    final rebaseStart = selectedIndex != -1 ? selectedIndex : 0;
    final rebaseEnd = _rebaseRangeEndIndex ?? rebaseStart;
    final rangeMin = min(rebaseStart, rebaseEnd);
    final rangeMax = max(rebaseStart, rebaseEnd);

    return Column(children: [
      MaterialSurface(
        tone: AppMaterialTone.surface0,
        radius: 0,
        border: Border(
          bottom: BorderSide(color: t.chromeBorderFaint),
        ),
        elevated: false,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          // The page title doubles as the worldline toggle — visually
          // unchanged (the posture is discoverable via the handle; this
          // is a power-user shortcut, cursor + semantics only).
          Semantics(
            button: true,
            label: 'Toggle worldline',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    _timelineStripKey.currentState?._toggleTheta(),
                child: Text('History',
                    style: TextStyle(
                        color: t.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.05)),
              ),
            ),
          ),
          const Spacer(),
          Row(children: [
            Text('Viewing last',
                style: TextStyle(color: t.textMuted, fontSize: 11)),
            const SizedBox(width: 6),
            SizedBox(
              width: 56,
              child: AppTextField(
                controller: _limitCtrl,
                height: 22,
                fontSize: 11,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onSubmitted: _onLimitSubmit,
              ),
            ),
            const SizedBox(width: 6),
            Text('commits', style: TextStyle(color: t.textMuted, fontSize: 11)),
          ]),
        ]),
      ),

      if (_commits.isNotEmpty)
        _TimelineStrip(
          key: _timelineStripKey,
          commits: _commits,
          selectedHash: _selectedHash,
          onSelected: (hash) {
            setState(() {
              _selectCommit(hash);
              _rebaseRangeEndIndex = null;
              _tagInputVisible = false;
              _clearCommitDiffState();
            });
            _loadDetail(repoPath, hash);
            // Rail-originated selection (click, drag-scrub, wheel)
            // pulls the list to the commit it landed on, so the two
            // surfaces never disagree about where "here" is.
            _scrollToCommit(hash);
          },
          tokens: t,
          detailCache: _detailCache,
          detailCacheVersion: _detailCacheVersion,
          hoverNotifier: _railHover,
          repoPath: repoPath,
          historyLimit: _effectiveHistoryLimit,
          trunkHashes: _trunkHashes,
          previewCommits: _activePreviewCommits,
          previewLabel: _previewBranch,
          localOnlyHashes: _localOnlyHashes,
          reservePreviewLane: hasInFlightDesks,
        ),

      Expanded(
        child: Row(children: [
          // Left — commit list
          MaterialSurface(
            tone: AppMaterialTone.surface1,
            radius: 0,
            border: Border(
              right: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
            ),
            elevated: false,
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Other desks with commits ahead of THEIR own upstream
                // surface here as ghost rows. Click → switch to that
                // desk + drop the user on its Changes panel (where the
                // "in-flight work" lives). Mirrors the symmetric strip
                // in the Changes page so the language is consistent
                // across surfaces. Hidden when no other desk has
                // unpushed work — no chrome with nothing to say.
                _DesksInFlightStrip(
                  tokens: t,
                  activeRepoPath: repoPath,
                  onJumpToDesk: (deskPath) async {
                    await context
                        .read<RepositoryState>()
                        .setActivePath(deskPath, addToRecents: false);
                    if (!mounted) return;
                    widget.onOpenChanges?.call();
                  },
                  onPreviewHover: (deskPath, rev, label) =>
                      _onPreviewDeskHover(repoPath, deskPath, rev, label),
                ),
                Expanded(
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 200) _loadReflog(repoPath);
                      return false;
                    },
                    child: Builder(builder: (ctx) {
                      // Hovered-desk preview prefix. When the user is
                      // hovering an IN FLIGHT chip and its commits
                      // have resolved, prepend them — each row fades
                      // in with a row-index-staggered delay so the
                      // sequence reads as "landing one at a time"
                      // rather than a single snap-in.
                      final preview = _activePreviewCommits;
                      final previewCount = preview.length;
                      return ListView.builder(
                        controller: _commitScroll,
                        padding: EdgeInsets.zero,
                        itemCount: previewCount + _commits.length +
                            (_reflogLoaded ? _reflog.length + 1 : 1),
                        itemBuilder: (ctx, rawIndex) {
                          // Preview rows at the top. Each gets its own
                          // staggered animation so the list populates
                          // in sequence. Stagger budget is bounded —
                          // cap total animation to ~1.2s even when the
                          // desk has many commits, so very wide dives
                          // still complete promptly.
                          if (rawIndex < previewCount) {
                            return _PreviewCommitRow(
                              key: ValueKey(
                                  'prev:$_previewDeskPath:${preview[rawIndex].commitHash}'),
                              commit: preview[rawIndex],
                              tokens: t,
                              indexInPreview: rawIndex,
                              totalPreview: previewCount,
                              railHover: _railHover,
                              onHoverChanged: _onPreviewRowHover,
                            );
                        }
                        final i = rawIndex - previewCount;
                        if (i < _commits.length) {
                    final commit = _commits[i];
                    final isSelected = commit.commitHash == _selectedHash;
                    final inRange =
                        _isRebaseMode && i >= rangeMin && i <= rangeMax;
                    return _CommitRow(
                      commit: commit,
                      tokens: t,
                      isSelected: isSelected,
                      inRange: inRange,
                      cachedDetail: _detailCache['$repoPath::${commit.commitHash}'],
                      tagProfile: _tagProfile,
                      couplingMatrix: context
                          .read<FileCouplingState>()
                          .matrixFor(repoPath),
                      logosEngine: context
                          .read<LogosGitState>()
                          .engineFor(repoPath),
                      engineCoherences: _cachedEngineCoherences,
                      resolvedGitTags: _gitTagsForHash(
                          commit.commitHash, commit.refNames),
                      isLocalOnly:
                          _localOnlyHashes.contains(commit.commitHash),
                      railHover: _railHover,
                      onTap: (shift) => _onCommitTap(i, shift),
                      onSecondaryTap: (pos) => _showCommitContextMenu(
                          context, pos, _commits[i], repoPath),
                    );
                  }
                  if (i == _commits.length) {
                    return _ReflogDivider(
                        t: t,
                        loaded: _reflogLoaded,
                        onLoad: () => _loadReflog(repoPath));
                  }
                  final ri = i - _commits.length - 1;
                  if (ri < _reflog.length) {
                    final entry = _reflog[ri];
                    return _ReflogRow(
                        entry: entry,
                        tokens: t,
                        onTap: () {
                          setState(() {
                            _selectCommit(entry.commitHash);
                            _rebaseRangeEndIndex = null;
                            _clearCommitDiffState();
                          });
                          _loadDetail(repoPath, entry.commitHash);
                        },
                        onSecondaryTap: (pos) =>
                            _showReflogRecoveryMenu(repoPath, entry, pos));
                  }
                  return const SizedBox.shrink();
                },
              );
                    }),
            ),
                ),
              ],
            ),
          ),

          // Right — detail or rebase editor
          Expanded(
            child: MaterialSurface(
              tone: AppMaterialTone.surface0,
              radius: 0,
              borderAlpha: 0,
              elevated: false,
              child: _isRebaseMode
                  ? _RebaseEditor(
                      commits: _commits.sublist(rangeMin, rangeMax + 1),
                      tokens: t,
                      repoPath: repoPath,
                      onCancel: () =>
                          setState(() => _rebaseRangeEndIndex = null),
                    )
                  : _selectedHash == null
                      ? const AppStatusView(
                          title: 'No commit selected',
                          message: 'Select a commit to inspect its changes.',
                          compact: true,
                        )
                      : _detail != null
                          // Cross-fade between overview and per-file
                          // diff so the swap reads as a smooth depth
                          // change inside the same panel.
                          ? AnimatedSwitcher(
                              duration: context.motion(
                                  const Duration(milliseconds: 140)),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: KeyedSubtree(
                                // Key is binary (overview vs diff), NOT
                                // per-file. Switching files inside diff
                                // mode keeps the pane mounted so the
                                // rail's wake animation doesn't restart;
                                // only the inner DiffShell swaps content.
                                key: ValueKey(_commitDiffFile == null
                                    ? 'overview'
                                    : 'diff'),
                                child: _commitDiffFile != null
                                    ? _CommitFileDiffPane(
                                        detail: _detail!,
                                        filePath: _commitDiffFile!,
                                        diffContent: _commitDiffContent,
                                        loading: _commitDiffLoading,
                                        error: _commitDiffError,
                                        tokens: t,
                                        repoPath: repoPath,
                                        onOpenFile: (path) =>
                                            _openCommitFileDiff(repoPath,
                                                _detail!.commitHash, path),
                                        onClose: _closeCommitFileDiff,
                                      )
                                    : _CommitDetailTransition(
                              detail: _detail!,
                              loading:
                                  _detailLoading && _detailLoadingHash != null,
                              tokens: t,
                              repoPath: repoPath,
                              tagInputVisible: _tagInputVisible,
                              tagInputValue: _tagInputValue,
                              tagController: _tagCtrl,
                              tagError: _tagError,
                              gitTags: _gitTagsForHash(
                                _detail!.commitHash,
                                _selectedRefNames,
                              ),
                              onToggleTag: () => setState(() {
                                _tagInputVisible = !_tagInputVisible;
                                _tagError = null;
                              }),
                              onTagChanged: (v) =>
                                  setState(() => _tagInputValue = v),
                              onCreateTag: () =>
                                  _createTag(repoPath, _detail!.commitHash),
                              onDeleteTag: (name) =>
                                  _deleteTag(repoPath, name),
                              onOpenFile: (path) => _openCommitFileDiff(
                                  repoPath, _detail!.commitHash, path),
                              onOpenAllFiles: () => _openCommitAllDiff(
                                  repoPath, _detail!.commitHash),
                              onOpenDirectory: (dirPath) =>
                                  _openCommitFileDiff(repoPath,
                                      _detail!.commitHash, dirPath),
                              tagEscapeFocus: _tagEscapeFocus,
                              signature: _signatureFor(_detail!),
                              lifecycles: _lifecyclesFor(repoPath),
                            ),
                              ),
                            )
                          : _detailLoading
                              ? const AppStatusView.loading(
                                  title: 'Loading commit',
                                  message: 'Reading commit details.',
                                  compact: true,
                                )
                              : AppStatusView.error(
                                  title: 'Commit unavailable',
                                  message:
                                      _detailError ?? 'Could not load commit.',
                                  compact: true,
                                ),
            ),
          ),
        ]),
      ),
    ]);
  }
}


class _CommitRow extends StatefulWidget {
  final CommitHistoryEntry commit;
  final AppTokens tokens;
  final bool isSelected, inRange;
  final CommitDetailData? cachedDetail;
  /// Auto-derived tag profile for the current repo. Empty profile
  /// (first frame, or empty repo) yields no auto-tags — falls back
  /// to just git-native tag pills.
  final RepositoryTagProfile tagProfile;
  /// Coupling matrix used for coherence-axis tags (focused / sprawl).
  /// Null when not yet computed; rows silently skip coherence tags.
  final FileCouplingMatrix? couplingMatrix;
  /// Optional Logos engine for the active repo. When warm, supplies
  /// Born-mixed multi-axis coherence to the row's focused/sprawl gate
  /// in preference to the raw Jaccard fallback.
  final LogosGit? logosEngine;
  /// Per-commit coherence map cached at tag-profile build time. When
  /// non-null, the row reads its coherence from here instead of
  /// recomputing `engine.coherence(files)` (which is ~2-10ms per
  /// call on a wide diff). Shared reference across every row — no
  /// per-row allocation.
  final Map<String, double>? engineCoherences;
  final List<String> resolvedGitTags;
  /// True when this commit hasn't reached `@{upstream}` yet — renders
  /// the same ↑ marker language the timeline's unpushed rail tint uses.
  final bool isLocalOnly;
  /// Shared rail↔list hover channel (see `_HistoryPageState._railHover`).
  /// Row hover writes the commit hash here (lighting the dot on the
  /// rail); the row listens and tints itself when the rail hovers its
  /// dot. Null-safe no-op when absent.
  final ValueNotifier<String?>? railHover;
  final void Function(bool shift) onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  const _CommitRow({
    required this.commit,
    required this.tokens,
    required this.isSelected,
    required this.inRange,
    required this.cachedDetail,
    required this.tagProfile,
    required this.couplingMatrix,
    required this.logosEngine,
    required this.engineCoherences,
    required this.resolvedGitTags,
    this.isLocalOnly = false,
    this.railHover,
    required this.onTap,
    this.onSecondaryTap,
  });
  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _hovered = false;
  bool _pressed = false;
  /// True while the timeline strip hovers this commit's dot. Kept as
  /// a bool derived from the shared notifier so the listener only
  /// setStates on transitions — 100 rows listening costs 100 equality
  /// checks per hover tick, not 100 rebuilds.
  bool _railHovered = false;

  @override
  void initState() {
    super.initState();
    widget.railHover?.addListener(_onRailHover);
  }

  @override
  void didUpdateWidget(_CommitRow old) {
    super.didUpdateWidget(old);
    if (old.railHover != widget.railHover) {
      old.railHover?.removeListener(_onRailHover);
      widget.railHover?.addListener(_onRailHover);
    }
    _onRailHover();
  }

  @override
  void dispose() {
    widget.railHover?.removeListener(_onRailHover);
    super.dispose();
  }

  void _onRailHover() {
    final now = widget.railHover?.value == widget.commit.commitHash;
    if (now == _railHovered) return;
    setState(() => _railHovered = now);
  }

  /// Computes the auto-tags for this row. Kept trivial and
  /// synchronous — the heavy lifting (profile construction) already
  /// happened off-isolate; per-row tagging is a handful of string and
  /// numeric comparisons.
  List<CommitTag> _autoTagsFor(CommitHistoryEntry c) {
    if (widget.tagProfile.commitCount == 0) return const [];
    // Prefer the pre-computed coherence map — populated at profile
    // build time so every row does a map lookup, not an
    // `engine.coherence(...)` walk. The fallback path only fires
    // when the map is null (tag profile built before the engine
    // warmed) or doesn't have this commit (detail cached after the
    // map was built — rare race during async history scroll).
    double? engineCoherence = widget.engineCoherences?[c.commitHash];
    if (engineCoherence == null) {
      final detail = widget.cachedDetail;
      final engine = widget.logosEngine;
      if (engine != null && detail != null && detail.files.length >= 2) {
        engineCoherence = engine.coherence(detail.files.map((f) => f.path));
      }
    }
    return tagCommit(
      commit: c,
      detail: widget.cachedDetail,
      profile: widget.tagProfile,
      coupling: widget.couplingMatrix,
      engineCoherence: engineCoherence,
    );
  }

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      return '${diff.inMinutes}m ago';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final c = widget.commit;

    return InteractionFeedback(
      onTap: () {
        final shift = HardwareKeyboard.instance.logicalKeysPressed
                .contains(LogicalKeyboardKey.shiftLeft) ||
            HardwareKeyboard.instance.logicalKeysPressed
                .contains(LogicalKeyboardKey.shiftRight);
        widget.onTap(shift);
      },
      onSecondaryTapDown: widget.onSecondaryTap,
      onHoverChanged: (h) {
        // Echo row hover onto the shared rail channel so the strip
        // lights this commit's dot. Exit only clears the channel if
        // it still points at us (enter of the next row may already
        // have claimed it).
        final rail = widget.railHover;
        if (rail != null) {
          if (h) {
            rail.value = widget.commit.commitHash;
          } else if (rail.value == widget.commit.commitHash) {
            rail.value = null;
          }
        }
        if (h == _hovered) return;
        setState(() => _hovered = h);
      },
      onPressedChanged: (p) {
        if (p == _pressed) return;
        setState(() => _pressed = p);
      },
      child: AnimatedScale(
        duration: context.motion(AppMotion.snap),
        curve: AppMotion.snapCurve,
        scale: _pressed ? 0.99 : 1.0,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.fromLTRB(0, 9, 12, 9),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? t.itemActiveBg
                : widget.inRange
                    ? t.chromeAccent.withValues(alpha: 0.06)
                    : _hovered
                        ? t.itemHoverBg
                        // Rail hovering this commit's dot: a softer
                        // echo of the row's own hover, so sweeping the
                        // strip visibly tracks through the list.
                        : _railHovered
                            ? t.itemHoverBg
                                .withValues(alpha: t.itemHoverBg.a * 0.55)
                            : t.itemHoverBg.withValues(alpha: 0),
            border: Border(
              left: BorderSide(
                color: widget.isSelected
                    ? t.itemActiveBorder
                    : t.itemActiveBorder.withValues(alpha: 0),
                width: 2,
              ),
              bottom: BorderSide(color: t.chromeBorderFaint),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  c.shortHash,
                  style: TextStyle(
                    color: widget.isSelected ? t.textStrong : t.textMuted,
                    fontSize: 10,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                    fontWeight:
                        widget.isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                // Same ↑ the in-flight chips and the rail's unpushed
                // tint speak — this commit hasn't reached upstream.
                if (widget.isLocalOnly)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '↑',
                      style: TextStyle(
                        color: t.stateAdded.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        fontFamily: AppFonts.mono,
                        fontFamilyFallback: AppFonts.monoFallback,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(_formatDate(c.authoredAt),
                    style: TextStyle(
                        color: t.textMuted.withValues(alpha: 0.8),
                        fontSize: 10)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(
                  child: Text(
                    c.subject,
                    style: TextStyle(
                      color: widget.isSelected ? t.textStrong : t.textNormal,
                      fontSize: 13,
                      fontWeight:
                          widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Text(c.authorName,
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                // Tag strip — fills the space between author and impact
                // column. Longer usernames leave less room for tags.
                Expanded(
                  child: _FittingTagRow(
                    autoTags: _autoTagsFor(c),
                    gitTagNames: widget.resolvedGitTags,
                    tokens: t,
                  ),
                ),
                const SizedBox(width: 8),
                _CommitImpact(detail: widget.cachedDetail, tokens: t),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}


class _ReflogDivider extends StatelessWidget {
  final AppTokens t;
  final bool loaded;
  final VoidCallback onLoad;
  const _ReflogDivider(
      {required this.t, required this.loaded, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(children: [
          Expanded(
              child: Divider(
                  color: t.chromeBorder.withValues(alpha: 0.3), height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('reflog',
                style: TextStyle(
                    color: t.textMuted, fontSize: 10, letterSpacing: 0.05)),
          ),
          Expanded(
              child: Divider(
                  color: t.chromeBorder.withValues(alpha: 0.3), height: 1)),
        ]),
      ),
      if (!loaded)
        Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: onLoad,
            child: Text('Load reflog',
                style: TextStyle(color: t.accentBright, fontSize: 11)),
          ),
        ),
    ]);
  }
}


/// Greedy-fit tag strip: measures pills with a TextPainter and stops
/// admitting once the cumulative width would exceed the parent's max.
/// Auto-tags admit before git-native tags so the semantic pills win
/// when space is tight.
class _FittingTagRow extends StatelessWidget {
  final List<CommitTag> autoTags;
  final List<String> gitTagNames;
  final AppTokens tokens;

  const _FittingTagRow({
    required this.autoTags,
    required this.gitTagNames,
    required this.tokens,
  });

  // Pill chrome: 6px horizontal padding each side (CommitTagPill) / 5px
  // (git _TagPill, plus 9px icon + 3px gap). 2px border budget. Total
  // constant cost per pill, added to the text width.
  static const double _autoPillChrome = 12 + 2;
  static const double _gitPillChrome = 10 + 2 + 9 + 3;
  static const double _pillSpacing = 4;
  static const TextStyle _pillTextStyle = TextStyle(
    fontSize: 9,
    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
    letterSpacing: 0.2,
  );

  double _measureTextWidth(String label) {
    final tp = TextPainter(
      text: TextSpan(text: label.toLowerCase(), style: _pillTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      if (maxW <= 0 || (autoTags.isEmpty && gitTagNames.isEmpty)) {
        return const SizedBox.shrink();
      }
      final admitted = <Widget>[];
      var used = 0.0;

      bool tryAdd(Widget pill, double pillWidth) {
        final sep = admitted.isEmpty ? 0.0 : _pillSpacing;
        if (used + sep + pillWidth > maxW) return false;
        if (sep > 0) admitted.add(const SizedBox(width: _pillSpacing));
        admitted.add(pill);
        used += sep + pillWidth;
        return true;
      }

      for (final tag in autoTags) {
        final w = _measureTextWidth(tag.label) + _autoPillChrome;
        if (!tryAdd(CommitTagPill(tag: tag, tokens: tokens), w)) break;
      }
      for (final name in gitTagNames) {
        final w = _measureTextWidth(name) + _gitPillChrome;
        if (!tryAdd(_TagPill(name: name, tokens: tokens), w)) break;
      }

      // Right-aligned so tags sit against the impact column.
      return Align(
        alignment: Alignment.centerRight,
        child: Row(mainAxisSize: MainAxisSize.min, children: admitted),
      );
    });
  }
}

class _TagPill extends StatelessWidget {
  final String name;
  final AppTokens tokens;
  const _TagPill({required this.name, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: t.accentBright.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.badgeRadius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(name: 'tag', size: 9, color: t.accentBright),
        const SizedBox(width: 3),
        Text(name,
            style: TextStyle(
                color: t.accentBright,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
      ]),
    );
  }
}


class _DetailTagPill extends StatefulWidget {
  final String name;
  final AppTokens tokens;
  final VoidCallback onDelete;
  const _DetailTagPill({
    required this.name,
    required this.tokens,
    required this.onDelete,
  });
  @override
  State<_DetailTagPill> createState() => _DetailTagPillState();
}

class _DetailTagPillState extends State<_DetailTagPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final shader = context.surfaceShader;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: context.motion(shader.duration),
        curve: shader.safeCurve,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _hovered
              ? t.stateDeleted.withValues(alpha: 0.10)
              : t.accentBright.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(shader.geometry.badgeRadius),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(
              name: 'tag', size: 10, color: t.accentBright),
          const SizedBox(width: 4),
          Text(widget.name,
              style: TextStyle(
                  color: t.accentBright,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: AppFonts.monoFallback)),
          if (_hovered) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: widget.onDelete,
              child: Text('✕',
                  style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.6),
                      fontSize: 10)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The tag-creation affordance, deliberately subordinate to the real tags
/// it sits beside. At rest it's a ghost coin — a faint tag glyph + '+' that
/// reads as "a tag waiting to exist": transparent, borderless, textFaint.
/// Clicking morphs it IN PLACE (same Wrap slot) into a pill-shaped inline
/// field styled like a nascent _DetailTagPill, so you are literally typing
/// inside the tag it will become. No row drops below, no hint sentence — the
/// pill's own border + icon carry every state: accent while typing,
/// stateConflicted the instant a name collides.
class _TagCreator extends StatefulWidget {
  final AppTokens tokens;
  final bool expanded;
  final String? error;
  final TextEditingController controller;
  final FocusNode escapeFocus;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final VoidCallback onCreate;
  const _TagCreator({
    required this.tokens,
    required this.expanded,
    required this.error,
    required this.controller,
    required this.escapeFocus,
    required this.onToggle,
    required this.onChanged,
    required this.onCreate,
  });
  @override
  State<_TagCreator> createState() => _TagCreatorState();
}

class _TagCreatorState extends State<_TagCreator> {
  bool _hovered = false;
  // Guards the submit round-trip. onCreate is async: on success the parent
  // collapses us (expanded → false, field disposed → blur), on failure it
  // keeps us open with an error. Without this flag the success-path blur
  // would fire the focus-out collapse and toggle us straight back open.
  bool _submitting = false;
  final _fieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fieldFocus.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _TagCreator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The submit round-trip is over the moment the parent responds, and it
    // can respond two ways: success collapses us (expanded → false), failure
    // hands back an error while the field stays open. Release the guard on
    // *either* — otherwise a success leaves the latch stuck true and the next
    // blur can never collapse the field again.
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    if (_submitting && (!widget.expanded || hasError)) {
      _submitting = false;
    }
  }

  @override
  void dispose() {
    _fieldFocus.removeListener(_handleFocus);
    _fieldFocus.dispose();
    super.dispose();
  }

  void _handleFocus() {
    // Losing focus collapses the nascent pill — but never mid-submit, and
    // never once the parent has already begun collapsing us.
    if (!_fieldFocus.hasFocus && widget.expanded && !_submitting && mounted) {
      widget.onToggle();
    }
  }

  void _submit() {
    // Enter on nothing is a dismiss, not a create — the same contract every
    // inline input in the app honours. Sending an empty value would hit the
    // parent's silent empty-guard, which produces no state change, so neither
    // the collapse nor the error path would ever fire and the latch would
    // wedge the field open. Never latch or submit an unsendable value.
    if (widget.controller.text.trim().isEmpty) {
      if (widget.expanded) widget.onToggle();
      return;
    }
    _submitting = true;
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      // Snappy morph: grows out of the ghost coin, capped well under the
      // house 160ms ceiling.
      duration: context.motion(const Duration(milliseconds: 140)),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: widget.expanded ? _buildField(context) : _buildGhost(context),
    );
  }

  Widget _buildGhost(BuildContext context) {
    final t = widget.tokens;
    final shader = context.surfaceShader;
    final color = _hovered ? t.accentBright : t.textFaint;
    return Tooltip(
      message: 'Create tag',
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        label: 'Create tag',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: context.motion(shader.duration),
              curve: shader.safeCurve,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                // Transparent/borderless at rest; a breath of accent wash on
                // hover so it lifts without competing with the real pills.
                color: _hovered
                    ? t.accentBright.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(shader.geometry.pillRadius),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(name: 'tag', size: 10, color: color),
                const SizedBox(width: 1),
                Text('+',
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        height: 1.0,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context) {
    final t = widget.tokens;
    final shader = context.surfaceShader;
    final hasError = widget.error != null && widget.error!.isNotEmpty;
    // On collision the pill's border + icon flip to the conflict tone while
    // the input stays open; the reason rides along in Semantics for readers.
    final accent = hasError ? t.stateConflicted : t.accentBright;
    return KeyboardListener(
      focusNode: widget.escapeFocus,
      onKeyEvent: (e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.escape) {
          widget.onToggle();
        }
      },
      child: Semantics(
        textField: true,
        label: hasError ? 'New tag name — ${widget.error}' : 'New tag name',
        child: Container(
          height: 22,
          constraints: const BoxConstraints(minWidth: 84, maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: t.accentBright.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(shader.geometry.pillRadius),
            border: Border.all(
                color: hasError ? t.stateConflicted : t.itemActiveBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(name: 'tag', size: 10, color: accent),
            const SizedBox(width: 4),
            Flexible(
              child: TextField(
                controller: widget.controller,
                focusNode: _fieldFocus,
                autofocus: true,
                cursorColor: accent,
                cursorHeight: 12,
                cursorWidth: 1.5,
                // Text styled exactly like a _DetailTagPill's label — you are
                // editing the tag, not filling a form field.
                style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.mono,
                    fontFamilyFallback: AppFonts.monoFallback),
                decoration: const InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onChanged,
                onSubmitted: (_) => _submit(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReflogRow extends StatefulWidget {
  final ReflogEntryData entry;
  final AppTokens tokens;
  final VoidCallback onTap;
  /// Right-click → context menu opener. Receives the global pointer
  /// position so the parent can anchor the menu. Null disables the
  /// recovery affordance (e.g., when no repo path is bound).
  final void Function(Offset globalPosition)? onSecondaryTap;
  const _ReflogRow({
    required this.entry,
    required this.tokens,
    required this.onTap,
    this.onSecondaryTap,
  });
  @override
  State<_ReflogRow> createState() => _ReflogRowState();
}

class _ReflogRowState extends State<_ReflogRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final e = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        // Right-click opens the recovery menu — the reflog row's
        // primary value (recovering "lost" work after a rebase /
        // hard-reset / branch-delete) was previously locked behind
        // a CLI dance; now it's one click away.
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
          color: _hovered ? t.itemHoverBg : t.itemHoverBg.withValues(alpha: 0),
          child: Opacity(
            opacity: 0.7,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: t.chromeAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                        context.surfaceShader.geometry.badgeRadius)),
                child: Text(e.refSelector,
                    style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9,
                        fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
              ),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(e.actionSummary,
                      style: TextStyle(color: t.textNormal, fontSize: 11),
                      overflow: TextOverflow.ellipsis)),
              Text(e.shortHash,
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
            ]),
          ),
        ),
      ),
    );
  }
}


class _CommitDetail extends StatelessWidget {
  final CommitDetailData detail;
  final AppTokens tokens;
  final String repoPath;
  final bool tagInputVisible;
  final String tagInputValue;
  final TextEditingController tagController;
  final String? tagError;
  final List<String> gitTags;
  final VoidCallback onToggleTag;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onCreateTag;
  final ValueChanged<String> onDeleteTag;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenAllFiles;
  final ValueChanged<String>? onOpenDirectory;
  final CommitSignature? signature;
  final Map<String, FileLifecycle>? lifecycles;
  final FocusNode tagEscapeFocus;

  const _CommitDetail({
    super.key,
    required this.detail,
    required this.tokens,
    required this.repoPath,
    required this.tagInputVisible,
    required this.tagInputValue,
    required this.tagController,
    this.tagError,
    required this.gitTags,
    required this.onToggleTag,
    required this.onTagChanged,
    required this.onCreateTag,
    required this.onDeleteTag,
    required this.onOpenFile,
    required this.onOpenAllFiles,
    this.onOpenDirectory,
    required this.tagEscapeFocus,
    this.signature,
    this.lifecycles,
  });

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  /// Terse relative age ("3d ago", "2mo ago") in the app's mono voice.
  /// The absolute date rides along in a tooltip so precision is one hover
  /// away without spending a whole metadata slot on a raw ISO date.
  static String _relativeDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      final s = diff.inSeconds;
      if (s < 45) return 'just now';
      final m = diff.inMinutes;
      if (m < 60) return '${m}m ago';
      final h = diff.inHours;
      if (h < 24) return '${h}h ago';
      final days = diff.inDays;
      if (days < 7) return '${days}d ago';
      if (days < 30) return '${(days / 7).floor()}w ago';
      if (days < 365) return '${(days / 30).floor()}mo ago';
      return '${(days / 365).floor()}y ago';
    } catch (_) {
      return _formatDate(iso);
    }
  }

  /// GitHub's noreply identity is `<numeric-id>+<username>`; when a commit
  /// carries it as the *name* (web/co-authored commits), the raw digits
  /// read as a meaningless token in the leading avatar+name slot. Show the
  /// human-readable username instead. Plain names pass through untouched.
  static String _displayAuthor(String name) {
    final m = RegExp(r'^\d+\+(.+)$').firstMatch(name);
    return m != null ? m.group(1)! : name;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final d = detail;
    final authorName = _displayAuthor(d.authorName);
    final dirtyPaths = context
            .watch<RepositoryState>()
            .status
            ?.files
            .map((f) => f.path.replaceAll('\\', '/'))
            .toSet() ??
        <String>{};
    return ListView(padding: const EdgeInsets.all(20), children: [
      // Subject (primary heading) — morphs when you click a different
      // commit so the panel reads as a swap, not a teleport. Trades off
      // resonanceText's markdown styling since commit subjects are
      // overwhelmingly plain prose.
      CommitLede(
        detail: d,
        repoPath: repoPath,
        tokens: t,
        signature: signature,
        subjectStyle: TextStyle(
          color: t.textStrong,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),

      const SizedBox(height: 14),

      // Metadata row: avatar | name | · | date | · | hash | · tag* | ⊕
      // Tags lead the affordance; the ghost coin (⊕) whispers at the tail.
      Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Author avatar + name
          if (authorName.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              // Avatar coin. Routed through MaterialSurface so it wears
              // the theme's actual material (glass glaze, block bevel,
              // ink line) instead of a flat wash. Shape follows the
              // theme's geometry: a full circle wherever corners are
              // soft, snapping square only when the theme itself is
              // sharp — a rounded-rect avatar is neither coin nor tile.
              MaterialSurface(
                width: 22,
                height: 22,
                tone: t.innerPanelTone,
                radius: context.surfaceShader.geometry.radius <= 0
                    ? 0.0
                    : 11.0,
                borderAlpha: 0.22,
                innerHighlight: true,
                child: Center(
                    child: Text(
                  authorName[0].toUpperCase(),
                  style: TextStyle(
                      color: t.textStrong,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                )),
              ),
              const SizedBox(width: 6),
              Text(authorName,
                  style: TextStyle(
                      color: t.textNormal,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          Text('·',
              style: TextStyle(
                  color: t.textFaint, fontSize: 12)),
          // Date — relative in the row, absolute on hover.
          Tooltip(
            message: _formatDate(d.authoredAt),
            waitDuration: const Duration(milliseconds: 300),
            child: Text(_relativeDate(d.authoredAt),
                style: TextStyle(color: t.textMuted, fontSize: 11)),
          ),
          Text('·',
              style: TextStyle(
                  color: t.textFaint, fontSize: 12)),
          // Short hash
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: t.chromeAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.badgeRadius)),
            child: Text(d.shortHash,
                style: TextStyle(
                    color: t.accentBright,
                    fontSize: 11,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
          ),
          // Tags lead. Real tags sit immediately after the hash, each
          // introduced by its own separator dot — so zero tags means zero
          // trailing dots, no orphaned punctuation.
          for (final name in gitTags) ...[
            Text('·',
                style: TextStyle(
                    color: t.textFaint, fontSize: 12)),
            _DetailTagPill(
              name: name,
              tokens: t,
              onDelete: () => onDeleteTag(name),
            ),
          ],
          // The creation affordance is last and dotless: a ghost coin that
          // morphs in place into the tag it will become. It's an affordance
          // waiting to be a datum, not a datum — so it earns no separator.
          _TagCreator(
            tokens: t,
            expanded: tagInputVisible,
            error: tagError,
            controller: tagController,
            escapeFocus: tagEscapeFocus,
            onToggle: onToggleTag,
            onChanged: onTagChanged,
            onCreate: onCreateTag,
          ),
        ],
      ),

      if (d.body.isNotEmpty) ...[
        const SizedBox(height: 16),
        resonanceText(d.body, t,
            baseStyle: TextStyle(color: t.textNormal, fontSize: 12, height: 1.5)),
      ],

      const SizedBox(height: 20),
      Row(children: [
        // The structural sigil sits at the head of the stat row as a
        // static glyph — purely decorative-informative, NOT an
        // affordance. The chips beside it carry the click semantics.
        if (signature != null) ...[
          IgnorePointer(
            child: CommitSigil(
              fingerprint: signature!.fingerprint,
              tokens: t,
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Tapping any of these chips opens the entire commit's diff
        // (multi-file) in the existing DiffShell. The "39 files" chip
        // and the +/- chips all act as the same affordance — wherever
        // the user's eye lands when they want "show me everything."
        _StatChip(
            label: '${d.filesChanged} file${d.filesChanged == 1 ? "" : "s"}',
            color: t.textMuted,
            onTap: onOpenAllFiles),
        const SizedBox(width: 6),
        _StatChip(
            label: '+${d.additions}',
            color: t.stateAdded,
            onTap: onOpenAllFiles),
        const SizedBox(width: 4),
        _StatChip(
            label: '-${d.deletions}',
            color: t.stateDeleted,
            onTap: onOpenAllFiles),
      ]),

      const SizedBox(height: 18),
      CommitSeismograph(
        detail: d,
        tokens: t,
        dirtyPaths: dirtyPaths,
        repoPath: repoPath,
        onOpenFile: onOpenFile,
        onOpenAllFiles: onOpenAllFiles,
        onOpenDirectory: onOpenDirectory,
        lifecycles: lifecycles,
      ),
    ]);
  }
}

class _CommitDetailTransition extends StatelessWidget {
  final CommitDetailData detail;
  final bool loading;
  final AppTokens tokens;
  final String repoPath;
  final bool tagInputVisible;
  final String tagInputValue;
  final TextEditingController tagController;
  final String? tagError;
  final List<String> gitTags;
  final VoidCallback onToggleTag;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onCreateTag;
  final ValueChanged<String> onDeleteTag;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenAllFiles;
  final ValueChanged<String>? onOpenDirectory;
  final CommitSignature? signature;
  final Map<String, FileLifecycle>? lifecycles;
  final FocusNode tagEscapeFocus;

  const _CommitDetailTransition({
    required this.detail,
    required this.loading,
    required this.tokens,
    required this.repoPath,
    required this.tagInputVisible,
    required this.tagInputValue,
    required this.tagController,
    this.tagError,
    required this.gitTags,
    required this.onToggleTag,
    required this.onTagChanged,
    required this.onCreateTag,
    required this.onDeleteTag,
    required this.onOpenFile,
    required this.onOpenAllFiles,
    this.onOpenDirectory,
    required this.tagEscapeFocus,
    this.signature,
    this.lifecycles,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: context.motion(const Duration(milliseconds: 150)),
          reverseDuration: context.motion(const Duration(milliseconds: 60)),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _CommitDetail(
            key: ValueKey(detail.commitHash),
            detail: detail,
            tokens: tokens,
            repoPath: repoPath,
            tagInputVisible: tagInputVisible,
            tagInputValue: tagInputValue,
            tagController: tagController,
            tagError: tagError,
            gitTags: gitTags,
            onToggleTag: onToggleTag,
            onTagChanged: onTagChanged,
            onCreateTag: onCreateTag,
            onDeleteTag: onDeleteTag,
            onOpenFile: onOpenFile,
            onOpenAllFiles: onOpenAllFiles,
            onOpenDirectory: onOpenDirectory,
            tagEscapeFocus: tagEscapeFocus,
            signature: signature,
            lifecycles: lifecycles,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: loading ? 1 : 0,
            duration: context.motion(const Duration(milliseconds: 80)),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: tokens.accentBright.withValues(alpha: 0.75),
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-detail-pane wrapper around the existing [DiffShell]. The
/// seismograph metaphor follows the user in: a compact rail above the
/// diff lets you hop to any other file in the commit without going
/// back to the overview. Esc / Backspace returns to the seismograph.
class _CommitFileDiffPane extends StatefulWidget {
  final CommitDetailData detail;
  final String filePath;
  final String? diffContent;
  final bool loading;
  final String? error;
  final AppTokens tokens;
  final String repoPath;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onClose;

  const _CommitFileDiffPane({
    required this.detail,
    required this.filePath,
    required this.diffContent,
    required this.loading,
    required this.error,
    required this.tokens,
    required this.repoPath,
    required this.onOpenFile,
    required this.onClose,
  });

  @override
  State<_CommitFileDiffPane> createState() => _CommitFileDiffPaneState();
}

class _CommitFileDiffPaneState extends State<_CommitFileDiffPane> {
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'CommitFileDiffPane');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape ||
        e.logicalKey == LogicalKeyboardKey.backspace) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final isAll = widget.filePath == _HistoryPageState._kAllFilesPath;
    final headerPath = isAll
        ? '${widget.detail.filesChanged} '
            'file${widget.detail.filesChanged == 1 ? "" : "s"} · all changes'
        : widget.filePath;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: AppIcon(
                        name: 'arrow-left',
                        size: 13,
                        color: t.textMuted),
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  headerPath,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CommitSeismographRail(
              detail: widget.detail,
              // In all-files mode no specific bar is "live" — let the
              // rail show every file equally so the user can scrub or
              // tap straight into a single file's diff.
              currentFile: isAll ? '' : widget.filePath,
              tokens: t,
              onOpenFile: widget.onOpenFile,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: DiffShell(
              // In all-files mode pass a synthetic label DiffShell can
              // display as the file header — it natively renders
              // multi-file diffs containing per-file `+++/---` markers.
              filePath: isAll ? 'all changes' : widget.filePath,
              tokens: t,
              diffContent: widget.diffContent,
              loading: widget.loading,
              error: widget.error,
              repositoryPath: widget.repoPath,
              showFileHeader: isAll,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMiniButton extends StatefulWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;

  const _HistoryMiniButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_HistoryMiniButton> createState() => _HistoryMiniButtonState();
}

class _HistoryMiniButtonState extends State<_HistoryMiniButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: true,
      baseBorderColor: t.secondaryBtnBorder,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 80)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: chrome.background,
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.radius),
            border: Border.all(color: chrome.borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(name: widget.icon, size: 12, color: t.textMuted),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(color: t.textNormal, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _StatChip({required this.label, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.badgeRadius),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}


class _RebaseEditor extends StatefulWidget {
  final List<CommitHistoryEntry> commits;
  final AppTokens tokens;
  final String repoPath;
  final VoidCallback onCancel;
  const _RebaseEditor(
      {required this.commits,
      required this.tokens,
      required this.repoPath,
      required this.onCancel});
  @override
  State<_RebaseEditor> createState() => _RebaseEditorState();
}

class _RebaseEditorState extends State<_RebaseEditor> {
  late List<Map<String, String>> _todo;
  late List<Map<String, String>> _original;
  bool _running = false;
  String? _error;
  int? _rewordIndex;
  late TextEditingController _rewordCtrl;
  static const _actions = ['pick', 'reword', 'squash', 'fixup', 'drop'];

  @override
  void initState() {
    super.initState();
    _todo = widget.commits
        .map((c) =>
            {'action': 'pick', 'hash': c.commitHash, 'subject': c.subject})
        .toList();
    _original = _todo.map((e) => Map<String, String>.of(e)).toList();
    _rewordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _rewordCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    if (_todo.length != _original.length) return true;
    for (var i = 0; i < _todo.length; i++) {
      if (_todo[i]['hash'] != _original[i]['hash']) return true;
      if (_todo[i]['action'] != _original[i]['action']) return true;
      if (_todo[i]['subject'] != _original[i]['subject']) return true;
    }
    return false;
  }

  String? get _validationError {
    if (_todo.isEmpty) return null;
    final first = _todo[0]['action']!;
    if (first == 'squash' || first == 'fixup') {
      return 'First commit cannot be ${_todo[0]['action']}';
    }
    return null;
  }

  void _reset() {
    setState(() {
      _todo = _original.map((e) => Map<String, String>.of(e)).toList();
      _rewordIndex = null;
    });
  }

  void _setAction(int i, String action) {
    setState(() {
      final entry = _todo[i];
      if (action == 'reword' && _rewordIndex != i) {
        _rewordIndex = i;
        _rewordCtrl.text = entry['subject']!;
      } else if (action != 'reword' && _rewordIndex == i) {
        _rewordIndex = null;
      }
      _todo[i] = {...entry, 'action': action};
    });
  }

  void _commitReword(int i) {
    final text = _rewordCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _todo[i] = {..._todo[i], 'subject': text};
        _rewordIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final validation = _validationError;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                  'Rebase ${_todo.length} commit${_todo.length == 1 ? "" : "s"}',
                  style: TextStyle(
                      color: t.textStrong,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
            if (_isDirty)
              GestureDetector(
                onTap: _reset,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text('reset',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
                ),
              ),
          ]),
          const SizedBox(height: 2),
          Text('drag to reorder, pick action per commit',
              style: TextStyle(color: t.textMuted, fontSize: 11)),
        ]),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _todo.length,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Material(
                color: Colors.transparent,
                elevation: 4 * animation.value,
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.cardRadius),
                child: child,
              ),
              child: child,
            );
          },
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _todo.removeAt(oldIndex);
              _todo.insert(newIndex, item);
              _rewordIndex = null;
            });
          },
          itemBuilder: (ctx, i) {
            final entry = _todo[i];
            final action = entry['action']!;
            final isDropped = action == 'drop';
            final isSquash = action == 'squash' || action == 'fixup';
            final isReword = action == 'reword';
            final isEditing = _rewordIndex == i;

            // Visual grouping: squash/fixup merges into the commit above
            final mergesUp = isSquash && i > 0;
            final borderColor = mergesUp
                ? t.stateModified.withValues(alpha: 0.3)
                : isDropped
                    ? t.chromeBorder.withValues(alpha: 0.1)
                    : t.chromeBorder.withValues(alpha: 0.2);

            return Container(
              key: ValueKey(entry['hash']),
              margin: EdgeInsets.only(
                top: mergesUp ? 0 : 3,
                bottom: 3,
                left: mergesUp ? 16 : 0,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDropped
                    ? t.surface1.withValues(alpha: 0.4)
                    : mergesUp
                        ? t.stateModified.withValues(alpha: 0.04)
                        : t.surface1,
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.cardRadius),
                border: Border.all(color: borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.drag_indicator,
                              size: 14,
                              color: t.textFaint.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: AppDropdownField<String>(
                        value: action,
                        height: 24,
                        fontSize: 11,
                        menuColor: t.bg2,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        items: _actions
                            .map((a) =>
                                DropdownMenuItem(value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _setAction(i, v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                        entry['hash']!
                            .substring(0, min(7, entry['hash']!.length)),
                        style: TextStyle(
                            color: isDropped ? t.textFaint : t.textMuted,
                            fontSize: 10,
                            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(entry['subject']!,
                            style: TextStyle(
                                color:
                                    isDropped ? t.textFaint : t.textNormal,
                                fontSize: 11,
                                fontStyle: isReword
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                decoration: isDropped
                                    ? TextDecoration.lineThrough
                                    : null),
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  if (isEditing) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const SizedBox(width: 20),
                      Expanded(
                        child: TextField(
                          controller: _rewordCtrl,
                          autofocus: true,
                          style: TextStyle(
                            color: t.textStrong,
                            fontSize: 11,
                            fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            hintText: 'new message',
                            hintStyle: TextStyle(
                                color: t.textFaint, fontSize: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  context.surfaceShader.geometry.badgeRadius),
                              borderSide: BorderSide(
                                  color: t.inputBorder, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  context.surfaceShader.geometry.badgeRadius),
                              borderSide: BorderSide(
                                  color: t.accentBright, width: 0.8),
                            ),
                          ),
                          onSubmitted: (_) => _commitReword(i),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _commitReword(i),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Icon(Icons.check,
                              size: 14, color: t.stateAdded),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      if (validation != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(validation,
                style: TextStyle(color: t.stateConflicted, fontSize: 11))),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(_error!,
                style: TextStyle(color: t.stateConflicted, fontSize: 11))),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
              child: _RebaseBtn(
                  label: _running ? '…' : 'Start Rebase',
                  t: t,
                  primary: true,
                  enabled: !_running && validation == null,
                  onTap: _execute)),
          const SizedBox(width: 8),
          Expanded(
              child: _RebaseBtn(
                  label: 'Cancel',
                  t: t,
                  primary: false,
                  enabled: !_running,
                  onTap: widget.onCancel)),
        ]),
      ),
    ]);
  }

  Future<void> _execute() async {
    setState(() {
      _running = true;
      _error = null;
    });
    final r = await startInteractiveRebase(
      widget.repoPath,
      _todo
          .map((e) => RebaseTodoEntry(
                action: e['action']!,
                commitHash: e['hash']!,
                subject: e['subject']!,
              ))
          .toList(),
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      if (!r.ok) _error = r.error;
    });
    if (r.ok) widget.onCancel(); // collapse back on success
  }
}

class _RebaseBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool primary, enabled;
  final VoidCallback onTap;
  const _RebaseBtn(
      {required this.label,
      required this.t,
      required this.primary,
      required this.enabled,
      required this.onTap});
  @override
  State<_RebaseBtn> createState() => _RebaseBtnState();
}

class _RebaseBtnState extends State<_RebaseBtn> {
  bool _hov = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = widget.primary
        ? primaryButtonChrome(
            t,
            hovered: _hov,
            pressed: _pressed,
            enabled: widget.enabled,
          )
        : ghostButtonChrome(
            t,
            hovered: _hov,
            pressed: _pressed,
            enabled: widget.enabled,
            baseBorderColor: t.secondaryBtnBorder,
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: context.motion(const Duration(milliseconds: 80)),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 80)),
            height: 32,
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(
                  context.surfaceShader.geometry.radius),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows,
            ),
            child: Center(
              child: Transform.translate(
                offset: chrome.offset,
                child: Text(widget.label,
                    style: TextStyle(
                        color: widget.primary ? t.btnText : t.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky strip above the commit list surfacing other desks with
/// commits ahead of their upstream — i.e. work-in-flight that isn't
/// visible from the active worktree's history. Each ghost row is one
/// click away from "drop me into that desk's Changes panel" so the
/// strip closes the symmetric gap with the Changes-page strip that
/// already lists the same set.
/// Watches WorktreeState so when a desk gains / loses ahead commits
/// (commit, push, fetch) the strip re-renders without a manual
/// refresh. Returns SizedBox.shrink when no other desk is ahead — no
/// chrome with nothing to say.
class _DesksInFlightStrip extends StatefulWidget {
  final AppTokens tokens;
  final String activeRepoPath;
  final ValueChanged<String> onJumpToDesk;
  /// Hover-preview signal. Fires `(deskPath, rev, label)` when the
  /// cursor enters a chip; fires `(null, '', '')` when it leaves.
  /// `rev` is always fetchable (branch name, or raw HEAD hash for a
  /// detached desk); `label` is the display form the chip shows. The
  /// page uses it to populate its commit list + timeline with the
  /// desk's diverged commits in real time. Optional — when null the
  /// chips are click-only and behave like the original strip.
  final void Function(String? deskPath, String rev, String label)?
      onPreviewHover;

  const _DesksInFlightStrip({
    required this.tokens,
    required this.activeRepoPath,
    required this.onJumpToDesk,
    this.onPreviewHover,
  });

  @override
  State<_DesksInFlightStrip> createState() => _DesksInFlightStripState();
}

class _DesksInFlightStripState extends State<_DesksInFlightStrip> {
  /// Owned so the chip rail can be wheel-scrolled — with many desks
  /// in flight the overflow is otherwise unreachable with a mouse.
  final ScrollController _chipScroll = ScrollController();

  @override
  void dispose() {
    _chipScroll.dispose();
    super.dispose();
  }

  String _normalize(String p) => _normalizeDeskPath(p);

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final worktreeState = context.watch<WorktreeState>();
    final activeNorm = _normalize(widget.activeRepoPath);
    // Other desks with at least one commit ahead of their upstream.
    // Behind-only desks are excluded — "in flight" means there's
    // outgoing work to surface, not just a stale local copy of remote
    // history. Same convention the Changes-page strip uses.
    final inFlight = <(WorktreeData, int)>[];
    for (final d in worktreeState.desks) {
      if (_normalize(d.path) == activeNorm) continue;
      final activity = worktreeState.activityFor(d.path);
      final ahead = activity?.ahead ?? 0;
      if (ahead > 0) inFlight.add((d, ahead));
    }
    if (inFlight.isEmpty) return const SizedBox.shrink();
    inFlight.sort((a, b) => b.$2.compareTo(a.$2));
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: t.accentBright.withValues(alpha: 0.04),
        border: Border(
          bottom:
              BorderSide(color: t.chromeBorder.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'IN FLIGHT',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.85),
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 22,
              // Wheel-scrollable like every standalone horizontal
              // strip — with n desks in flight the tail chips must
              // stay reachable with a plain mouse.
              child: HorizontalWheelScroll(
                controller: _chipScroll,
                child: ListView.separated(
                  controller: _chipScroll,
                  scrollDirection: Axis.horizontal,
                  itemCount: inFlight.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    final (desk, ahead) = inFlight[i];
                    final label = desk.branch ??
                        (desk.isDetached
                            ? desk.head.substring(0,
                                desk.head.length < 7 ? desk.head.length : 7)
                            : 'desk');
                    return _InFlightDeskChip(
                      tokens: t,
                      label: label,
                      ahead: ahead,
                      onTap: () => widget.onJumpToDesk(desk.path),
                      onHoverChange: (hovering) =>
                          widget.onPreviewHover?.call(
                              hovering ? desk.path : null,
                              hovering ? (desk.branch ?? desk.head) : '',
                              hovering ? label : ''),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single ghost row in the IN FLIGHT strip. Compact pill, branch name
/// + ahead count + a tiny up-arrow glyph. Hover lifts to accent so
/// the click affordance is obvious.
class _InFlightDeskChip extends StatefulWidget {
  final AppTokens tokens;
  final String label;
  final int ahead;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHoverChange;
  const _InFlightDeskChip({
    required this.tokens,
    required this.label,
    required this.ahead,
    required this.onTap,
    this.onHoverChange,
  });
  @override
  State<_InFlightDeskChip> createState() => _InFlightDeskChipState();
}

class _InFlightDeskChipState extends State<_InFlightDeskChip> {
  bool _hovered = false;

  @override
  void dispose() {
    // If we're disposed mid-hover (chip removed because the desk
    // pushed and is no longer in the in-flight set), tell the parent
    // to drop the preview — otherwise the preview commits stay onscreen
    // even though the chip that triggered them is gone.
    if (_hovered) widget.onHoverChange?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHoverChange?.call(true);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHoverChange?.call(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 90)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered
                ? t.accentBright.withValues(alpha: 0.10)
                : t.surface1,
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.pillRadius),
            border: Border.all(
              color: _hovered
                  ? t.accentBright.withValues(alpha: 0.5)
                  : t.chromeBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Capped so a marathon branch name can't stretch the
              // chip into a scroll-eating slab — the name ellipsizes,
              // the ↑n count always stays visible beside it.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _hovered ? t.textStrong : t.textNormal,
                    fontSize: 10.5,
                    fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '↑${widget.ahead}',
                style: TextStyle(
                  color: t.stateAdded,
                  fontSize: 10,
                  fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ghost-style row used when an IN FLIGHT chip is hovered. Mirrors a
/// real _CommitRow's information density at a glance (short hash,
/// subject) but renders with an accent-washed background + a leading
/// "↑" glyph to read as "arriving from elsewhere" rather than
/// "already on this branch". Each row's opacity + subtle translate-in
/// is driven by a delay proportional to its preview index, so the
/// sequence populates in rather than snap-appearing.
/// Not clickable in v1 — the preview is read-only. The IN FLIGHT
/// chip above is the action surface; these rows just show what
/// clicking would bring.
class _PreviewCommitRow extends StatefulWidget {
  final CommitHistoryEntry commit;
  final AppTokens tokens;
  final int indexInPreview;
  final int totalPreview;
  /// Shared rail↔list hover channel — hovering a ghost row lights its
  /// preview dot on the timeline, same as real rows do.
  final ValueNotifier<String?>? railHover;
  /// Fires on pointer enter/exit so the page can SUSTAIN the preview
  /// while the cursor walks the ghost rows — without this, leaving
  /// the chip to read the rows would dismiss the very rows being read.
  final ValueChanged<bool>? onHoverChanged;
  const _PreviewCommitRow({
    super.key,
    required this.commit,
    required this.tokens,
    required this.indexInPreview,
    required this.totalPreview,
    this.railHover,
    this.onHoverChanged,
  });
  @override
  State<_PreviewCommitRow> createState() => _PreviewCommitRowState();
}

class _PreviewCommitRowState extends State<_PreviewCommitRow>
    with SingleTickerProviderStateMixin {
  static const Duration _authored = Duration(milliseconds: 260);
  static const Duration _staggerBudget = Duration(milliseconds: 1400);
  late final AnimationController _ac;
  bool _kicked = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: _authored);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kicked) return;
    _kicked = true;
    final scaled = context.motionRead(_authored);
    if (scaled == Duration.zero) {
      _ac.value = 1.0;
      return;
    }
    _ac.duration = scaled;
    final staggerCount = widget.totalPreview <= 20
        ? widget.totalPreview
        : 20;
    final perStep = _staggerBudget ~/ staggerCount.clamp(1, 1 << 30);
    final delay = perStep *
        (widget.indexInPreview < staggerCount
            ? widget.indexInPreview
            : staggerCount);
    final scaledDelay = context.motionRead(delay);
    Future<void>.delayed(scaledDelay, () {
      if (!mounted) return;
      _ac.forward();
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final c = widget.commit;
    final shortHash = c.commitHash.length >= 8
        ? c.commitHash.substring(0, 8)
        : c.commitHash;
    return FadeTransition(
      opacity: _ac,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.2),
          end: Offset.zero,
        ).animate(CurvedAnimation(
            parent: _ac, curve: Curves.easeOutCubic)),
        child: MouseRegion(
          onEnter: (_) {
            widget.railHover?.value = c.commitHash;
            widget.onHoverChanged?.call(true);
          },
          onExit: (_) {
            if (widget.railHover?.value == c.commitHash) {
              widget.railHover?.value = null;
            }
            widget.onHoverChanged?.call(false);
          },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: t.accentBright.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.cardRadius),
            border: Border.all(
              color: t.accentBright.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Text('↑',
                  style: TextStyle(
                      color: t.stateAdded,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
              const SizedBox(width: 6),
              Text(shortHash,
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontFamily: AppFonts.mono, fontFamilyFallback: AppFonts.monoFallback)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.textNormal,
                      fontSize: 11,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
