import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/context_menu.dart';
import '../../ui/control_chrome.dart';
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


const double _kNodeRadius = 3;
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
const int _kHistoryDefault = 100;
const int _kHistoryMax = 500;


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
  /// Cached hash→nodes-index lookup. Built once at layout time so the
  /// painter can resolve `edge.from`/`edge.to` and z-priority sort
  /// indices in O(1) instead of walking the nodes list each paint.
  final Map<String, int> hashToIndex;
  const _GLayout({
    required this.nodes,
    required this.edges,
    required this.laneCount,
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
  int laneCount = 1;
  final nodes = <_GNode>[];

  for (int i = 0; i < previewCommits.length; i++) {
    final entry = previewCommits[i];
    final visibleParents = entry.parentHashes
        .where((h) => visibleHashes.contains(h))
        .toList();
    final node = _GNode(
      entry: entry,
      row: i,
      lane: 1,
      visibleParents: visibleParents,
      isPreview: true,
    );
    nodes.add(node);
    hashToNode[entry.commitHash] = node;
    laneCount = max(laneCount, 2);
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
    laneCount = max(laneCount, lane + 1);

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

List<double> _projectXs(
    int n, double width, List<double> percents, double lInset, double rInset) {
  if (n == 0) return [];
  if (n == 1) return [width * 0.5];

  final minX = max(0.0, lInset);
  final maxX = max(minX, width - rInset);
  final drawable = max(0.0, maxX - minX);
  final pMin = percents.reduce(min), pMax = percents.reduce(max);
  final pRange = max(pMax - pMin, 1.0);

  return List.generate(n, (i) {
    if (i == 0) return minX;
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
    required this.targetColors,
    required this.churnIntro,
    required this.previewCommits,
    required this.previewIntro,
  }) : super(
          repaint: Listenable.merge([
            hoveredHashListenable,
            hoverXListenable,
            churnIntro,
            previewIntro,
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

    final railPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lanesUsed = <int>{};
    for (final n in layout.nodes) lanesUsed.add(n.lane);
    for (final lane in lanesUsed) {
      final laneNodes = <int>[];
      for (var i = 0; i < layout.nodes.length; i++) {
        if (layout.nodes[i].lane == lane) laneNodes.add(i);
      }
      if (laneNodes.isEmpty) continue;

      final isMain = lane == 0;
      final lx = baseXs.length > laneNodes.first
          ? max(baseXs[laneNodes.first] - _kNodeRadius, 0.0) : 0.0;
      final rx = baseXs.length > laneNodes.last
          ? min(baseXs[laneNodes.last] + _kNodeRadius, width) : width;
      final ry = vertInset + lane * laneStep + laneStep / 2;
      railPaint
        ..color = isMain
            ? tokens.chromeAccent.withValues(alpha: 0.14)
            : tokens.textMuted.withValues(alpha: 0.08)
        ..strokeWidth = isMain ? 1.0 : 0.8;
      canvas.drawLine(Offset(lx, ry), Offset(rx, ry), railPaint);
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
      final fromNode = layout.nodes[fromIdx];

      final isCrossLane = edge.fromLane != edge.toLane;
      final isMainline = !isCrossLane && edge.fromLane == 0;

      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.01) continue;
      final inv = 1.0 / dist;
      final fromR = _kNodeRadius * from.scale;
      final toR = _kNodeRadius * to.scale;
      final startX = from.x + dx * inv * fromR;
      final startY = from.y + dy * inv * fromR;
      final endX = to.x - dx * inv * toR;
      final endY = to.y - dy * inv * toR;

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
      if (isCrossLane) {
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

    for (final node in drawOrder) {
      final hash = node.entry.commitHash;
      final idx = hashToIndex[hash];
      if (idx == null) continue;
      final m = metrics[idx];
      final isSelected = hash == selectedHash;

      // Preview branch — same node-loop entry, distinct visual
      // language. The node EMERGES from the parent commit it'll
      // eventually attach to, sliding outward to its final lane along
      // an ease-out cubic. No regular churn-color logic (preview
      // commits aren't in the churn map yet — their detail isn't
      // fetched at hover time).
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

        final center = Offset(m.x, m.y);
        final r = _kNodeRadius * m.scale;
        nodeFillPaint.color =
            tokens.stateAdded.withValues(alpha: 0.85 * localT);
        canvas.drawCircle(center, r, nodeFillPaint);
        continue;
      }

      final churn = churnNorm[hash] ?? 0.0;
      final r = _kNodeRadius * m.scale * (1.0 + churn * 0.8);

      // Temporal luminance: real nodes near HEAD (low realIndex) are
      // vivid, nodes further back fade. Preview nodes skip this.
      final realIndex = idx - previewCommits.length;
      final temporal = realNodeCount <= 1 || realIndex < 0
          ? 1.0
          : 1.0 - (realIndex / (realNodeCount - 1)) * 0.4;

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
        nodeColor = base.withValues(alpha: base.a * temporal);
      }

      // Merge convergence: merges are structurally dense — slightly
      // larger fill so they read as junction points.
      final isMerge = node.entry.isMerge;
      final effectiveR = isMerge ? r * 1.12 : r;

      nodeFillPaint.color = nodeColor;
      final center = Offset(m.x, m.y);
      canvas.drawCircle(center, effectiveR, nodeFillPaint);

      if (isSelected) {
        canvas.drawCircle(center, effectiveR + 1.5, selectedRingPaint);
      }

      // Ref-tip ring: nodes with branch/tag refs get a subtle ring.
      // HEAD uses accentBright, tags use stateModified, other refs
      // use chromeAccent. The ring says "this node has a name."
      final refs = node.entry.refNames;
      if (refs.isNotEmpty && !isSelected) {
        final hasHead = refs.any((n) => n.contains('HEAD'));
        final hasTag = refs.any((n) => n.startsWith('tag:'));
        refRingPaint
          ..color = hasHead
              ? tokens.accentBright.withValues(alpha: 0.55 * temporal)
              : hasTag
                  ? tokens.stateModified.withValues(alpha: 0.40 * temporal)
                  : tokens.chromeAccent.withValues(alpha: 0.35 * temporal)
          ..strokeWidth = hasHead ? 1.4 : 1.0;
        canvas.drawCircle(center, effectiveR + 2.0, refRingPaint);
      }
    }
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
      old.previewCommits.length != previewCommits.length;
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

  const _TimelineStrip({
    required this.commits,
    required this.selectedHash,
    required this.onSelected,
    required this.tokens,
    required this.detailCache,
    required this.detailCacheVersion,
    this.trunkHashes = const {},
    this.previewCommits = const [],
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
  final ValueNotifier<String?> _hoveredHashNotifier = ValueNotifier(null);
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
  /// Pre-resolved per-hash target color (the lerp result of churnLerpA→B
  /// at netRatio[hash]). Computed once per `_rebuildChurnMaps` so the
  /// painter does ONE `Color.lerp` per node per frame (gray→target)
  /// instead of two (gray→target AND churnA→churnB at netRatio).
  Map<String, Color> _churnTargetColors = const {};

  static const Duration _churnAuthored = Duration(milliseconds: 320);
  static const Duration _previewAuthored = Duration(milliseconds: 1800);

  late final AnimationController _churnIntroCtrl = AnimationController(
    vsync: this,
    duration: _churnAuthored,
  );

  late final AnimationController _previewIntroCtrl = AnimationController(
    vsync: this,
    duration: _previewAuthored,
  );

  static String _signatureOf(List<CommitHistoryEntry> commits) {
    if (commits.isEmpty) return '';
    return '${commits.length}|${commits.first.commitHash}|${commits.last.commitHash}';
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
  }

  @override
  void dispose() {
    _hoverXNotifier.dispose();
    _hoveredHashNotifier.dispose();
    _churnIntroCtrl.dispose();
    _previewIntroCtrl.dispose();
    super.dispose();
  }

  void _rebuildLayout() {
    final previewCount = widget.previewCommits.length;
    final trimmedReals = widget.commits;
    _layout = _buildLayout(
      trimmedReals,
      trunkHashes: widget.trunkHashes.isEmpty ? null : widget.trunkHashes,
      previewCommits: widget.previewCommits,
    );
    // Compute x-percents from main branch commits only. Preview
    // commits spread evenly between the left edge (newest) and the
    // merge base position on the main timeline — they're ahead
    // commits that don't exist on main, so there's no main-branch
    // time range to interpolate into.
    final realPercents = _computePercents(trimmedReals);
    if (previewCount == 0) {
      _percents = realPercents;
    } else {
      double forkPercent = realPercents.isEmpty ? 100.0 : realPercents.first;
      if (widget.previewCommits.isNotEmpty) {
        final lastPreview = widget.previewCommits.last;
        for (final ph in lastPreview.parentHashes) {
          final idx = trimmedReals.indexWhere((e) => e.commitHash == ph);
          if (idx >= 0) {
            forkPercent = realPercents[idx];
            break;
          }
        }
      }
      // Run preview commits through the same timestamp-aware spacing
      // the main branch uses, then remap into the fork→tipSlot range
      // so they share the DAG's visual rhythm instead of even-spacing
      // across the full width.
      final rawPreview = _computePercents(widget.previewCommits);
      final gap = realPercents.isEmpty
          ? 0.0
          : (forkPercent - realPercents.first).abs();
      final spreadGap = max(gap, forkPercent * 0.15);
      final tipSlot = realPercents.isEmpty
          ? 0.0
          : (forkPercent - spreadGap).clamp(0.0, forkPercent);
      final previewPercents = rawPreview.map((p) {
        return tipSlot + (forkPercent - tipSlot) * (p / 100.0);
      }).toList();
      _percents = [...previewPercents, ...realPercents];
    }
    _layoutSignature = _signatureOf(widget.commits);
    _rebuildChurnMaps();
  }

  void _rebuildChurnMaps() {
    final (norm, ratio) =
        _computeChurnAndRatio(widget.commits, widget.detailCache);
    _churnNorm = norm;
    _netRatio = ratio;
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
    final trunkChanged = old.trunkHashes.length != widget.trunkHashes.length;
    // Match the real-commit signature exactly: length + tip + tail. The
    // tail check catches the case where a non-tip preview commit was
    // amended (hash changed) but length and tip stayed the same — that
    // mutation must invalidate `_layout` or the timeline renders stale.
    final previewChanged =
        _signatureOf(old.previewCommits) != _signatureOf(widget.previewCommits);
    if (_signatureOf(old.commits) != newSig ||
        trunkChanged ||
        previewChanged) {
      // Content changed: real commits, trunk set, or preview set.
      // Previews ARE part of layout now (folded in as nodes with
      // isPreview=true) so a swap or count change re-runs the layout
      // pass — but only the preview-node tail of `nodes` and the
      // appended `baseXs` change; real nodes' positions are stable.
      _layout = null;
    } else if (old.detailCacheVersion != widget.detailCacheVersion) {
      // Commits unchanged but cache mutated. The map is shared by
      // reference and mutated in place, so length/identity won't
      // change — only the parent-bumped version counter detects this.
      _rebuildChurnMaps();
    }
    // Preview set appeared, disappeared, or swapped → kick the
    // populate-in animation. The single shared controller drives the
    // per-node stagger window inside the painter.
    if (previewChanged) {
      _previewIntroCtrl.reset();
      if (widget.previewCommits.isNotEmpty) {
        if (context.reduceMotionRead) {
          _previewIntroCtrl.value = 1.0;
        } else {
          _previewIntroCtrl.forward();
        }
      }
    }
  }

  void _selectNearest(double x, List<double> baseXs) {
    if (baseXs.isEmpty || _layout == null) return;
    int nearest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < baseXs.length; i++) {
      final d = (baseXs[i] - x).abs();
      if (d < minDist) {
        minDist = d;
        nearest = i;
      }
    }
    final hash = _layout!.nodes[nearest].entry.commitHash;
    _hoveredHashNotifier.value = hash;
    widget.onSelected(hash);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.commits.isEmpty) return const SizedBox.shrink();

    if (_layout == null || _layoutSignature != _signatureOf(widget.commits))
      _rebuildLayout();

    return LayoutBuilder(builder: (ctx, constraints) {
      final width = max(constraints.maxWidth, 64.0);
      // Always allocate for at least `_kReservedLaneCount` lanes of
      // vertical space — this is what makes the strip's height stable
      // when a preview hover adds lane 1. Empty lanes cost nothing;
      // they just sit as dark surface.
      final laneCount = max(_layout!.laneCount, _kReservedLaneCount);
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
        _kNodeRadius,
      );

      return Container(
        height: totalHeight,
        decoration: BoxDecoration(
          color: widget.tokens.surface0,
          border: Border(
            bottom: BorderSide(
                color: widget.tokens.chromeBorder.withValues(alpha: 0.1)),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _kHorizPad),
          child: Listener(
            onPointerHover: (e) {
              _hoverXNotifier.value = e.localPosition.dx;
              _hoveredHashNotifier.value =
                  _nearestHash(e.localPosition.dx, baseXs);
            },
            onPointerDown: (e) {
              _hoverXNotifier.value = e.localPosition.dx;
              _dragging = true;
              _selectNearest(e.localPosition.dx, baseXs);
            },
            onPointerMove: (e) {
              if (_dragging) {
                _hoverXNotifier.value = e.localPosition.dx;
                _selectNearest(e.localPosition.dx, baseXs);
              }
            },
            onPointerUp: (_) => _dragging = false,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onExit: (_) {
                _hoverXNotifier.value = null;
                _hoveredHashNotifier.value = null;
              },
              // RepaintBoundary isolates the timeline's repaint region
              // so the header/siblings don't get invalidated on every
              // hover tick.
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TimelinePainter(
                    layout: _layout!,
                    baseXs: baseXs,
                    selectedHash: widget.selectedHash,
                    hoveredHashListenable: _hoveredHashNotifier,
                    hoverXListenable: _hoverXNotifier,
                    tokens: widget.tokens,
                    width: width,
                    height: height,
                    vertInset: _kVertInset,
                    laneStep: laneStep,
                    churnNorm: _churnNorm,
                    netRatio: _netRatio,
                    targetColors: _churnTargetColors,
                    churnIntro: _churnIntroCtrl,
                    previewCommits: widget.previewCommits,
                    previewIntro: _previewIntroCtrl,
                  ),
                  size: Size(width, totalHeight),
                ),
              ),
            ),
          ),
        ),
      );
    });
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

  /// Single-pass churn + netRatio computation. Shares one `byHash`
  /// build and one iteration over `commits` instead of two — prior
  /// code called `_byHash` twice (once per output map), wastefully
  /// reparsing every cache key on every `_rebuildChurnMaps`.
  static (Map<String, double>, Map<String, double>) _computeChurnAndRatio(
      List<CommitHistoryEntry> commits,
      Map<String, CommitDetailData> cache) {
    final byHash = _byHash(cache);
    final raws = <String, double>{};
    final ratio = <String, double>{};
    for (final c in commits) {
      final d = byHash[c.commitHash];
      if (d == null) continue;
      final total = d.additions + d.deletions;
      ratio[c.commitHash] = total == 0 ? 0.5 : d.additions / total;
      if (total > 0) raws[c.commitHash] = log(total + 1);
    }
    if (raws.isEmpty) return (const <String, double>{}, ratio);
    final maxVal = raws.values.reduce(max);
    if (maxVal == 0) return (const <String, double>{}, ratio);
    final norm = <String, double>{};
    raws.forEach((k, v) => norm[k] = v / maxVal);
    return (norm, ratio);
  }

  String? _nearestHash(double x, List<double> baseXs) {
    if (baseXs.isEmpty || _layout == null) return null;
    int nearest = 0;
    double minDist = double.infinity;
    for (int i = 0; i < baseXs.length; i++) {
      final d = (baseXs[i] - x).abs();
      if (d < minDist) {
        minDist = d;
        nearest = i;
      }
    }
    return _layout!.nodes[nearest].entry.commitHash;
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
              fontFamily: AppFonts.mono,
              fontWeight: FontWeight.w700)),
      Text('/',
          style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.3),
              fontSize: 9,
              fontFamily: AppFonts.mono)),
      Text('$dels',
          style: TextStyle(
              color: t.stateDeleted.withValues(alpha: 0.9),
              fontSize: 9,
              fontFamily: AppFonts.mono,
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

  // History limit
  int _historyLimit = _kHistoryDefault;
  final _limitCtrl = TextEditingController(text: '$_kHistoryDefault');

  // Reflog
  List<ReflogEntryData> _reflog = [];
  bool _reflogLoaded = false;

  // Inline tag
  bool _tagInputVisible = false;
  String _tagInputValue = '';
  String? _tagError;
  final _tagCtrl = TextEditingController();
  // Stable FocusNode for the tag-input KeyboardListener. Previously a
  // fresh `FocusNode()` was constructed inline every rebuild while the
  // input was visible; each such node registered with Flutter's focus
  // system and was never disposed. Owning one on the state class keeps
  // the node alive exactly as long as the panel can show the input.
  final _tagEscapeFocus = FocusNode(debugLabel: 'history.tag-input.escape');

  // Shift-select rebase range
  int? _rebaseRangeEndIndex;
  bool get _isRebaseMode => _rebaseRangeEndIndex != null;

  String? _lastRepo;

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
  /// Cleared on _load (repo switch invalidation).
  final Map<String, List<CommitHistoryEntry>> _previewCommitsCache = {};
  /// In-flight fetch guard so a quick mouse-trail across chips doesn't
  /// fire duplicate `git log` for the same desk.
  final Set<String> _previewLoadingDesks = <String>{};

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
      if (repo != null && _commits.any((c) => c.commitHash == newHash)) {
        setState(() => _selectedHash = newHash);
        _loadDetail(repo, newHash);
      }
    }
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _limitCtrl.dispose();
    _tagEscapeFocus.dispose();
    _tagProfileDebounce?.cancel();
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
    final r = await ancestorHashes(repo, branch.data!, limit: _historyLimit);
    if (!r.ok || r.data == null) return const <String>{};
    return r.data!;
  }

  Future<void> _load(String repo) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    // Fire the commit-history load and the trunk-ancestor lookup in
    // parallel. Trunk is only needed by the top timeline for lane
    // assignment — the commit list renders without it — so if the
    // lookup fails we just fall through to single-lane rendering
    // without blocking the main load.
    final historyFuture = listCommitHistory(repo, limit: _historyLimit);
    final trunkFuture = _resolveTrunkHashes(repo);
    final r = await historyFuture;
    final trunk = await trunkFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      _trunkHashes = trunk;
      if (r.ok) {
        _commits = r.data!;
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
    if (initialHash != null &&
        _commits.any((c) => c.commitHash == initialHash)) {
      setState(() => _selectedHash = initialHash);
      await _loadDetail(repo, initialHash);
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
    // Clicking the same rail bar twice should be a no-op — no flicker,
    // no refetch, no state churn. The diff is already showing.
    if (filePath == _commitDiffFile && !_commitDiffLoading) return;
    final reqId = ++_commitDiffReqId;
    setState(() {
      _commitDiffFile = filePath;
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

  void _closeCommitFileDiff() {
    setState(() {
      _commitDiffFile = null;
      _commitDiffContent = null;
      _commitDiffError = null;
      _commitDiffLoading = false;
    });
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
    final r = await bulkGetCommitDetails(repo, commits, limit: _historyLimit);
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
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cherry-pick failed: ${r.error}")),
      );
      return;
    }
    final short = hash.length >= 8 ? hash.substring(0, 8) : hash;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Cherry-picked $short")),
    );
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _revert(String repoPath, String hash) async {
    final r = await revertCommit(repoPath, hash);
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Revert failed: ${r.error}")),
      );
      return;
    }
    final short = hash.length >= 8 ? hash.substring(0, 8) : hash;
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
  void _onPreviewDeskHover(String repoPath, String? deskPath, String branch) {
    if (deskPath == _previewDeskPath) return;
    setState(() => _previewDeskPath = deskPath);
    if (deskPath == null) return;
    if (_previewCommitsCache.containsKey(deskPath)) return;
    if (_previewLoadingDesks.contains(deskPath)) return;
    _previewLoadingDesks.add(deskPath);
    unawaited(() async {
      // `git log <branch> ^HEAD` — diverged set in branch order
      // (newest first). Same shape as our normal commit list so the
      // existing _CommitRow + timeline layout consume it without
      // special-casing.
      final r = await listCommitsAhead(
        repoPath,
        branch: branch,
        excluding: 'HEAD',
        limit: _historyLimit,
      );
      if (!mounted) return;
      _previewLoadingDesks.remove(deskPath);
      if (!r.ok) return;
      setState(() {
        _previewCommitsCache[deskPath] = r.data!;
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
                  fontFamily: AppFonts.mono),
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

  void _onCommitTap(int index, bool shiftKey) {
    final hash = _commits[index].commitHash;
    if (shiftKey && _selectedHash != null && _selectedHash != hash) {
      setState(() => _rebaseRangeEndIndex = index);
    } else {
      setState(() {
        _selectedHash = hash;
        _rebaseRangeEndIndex = null;
        _tagInputVisible = false;
        _tagInputValue = '';
        _tagError = null;
      });
      final repo = context.read<RepositoryState>().activePath;
      if (repo != null) _loadDetail(repo, hash);
    }
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
      });
    } else {
      setState(() => _tagError = r.error);
    }
  }

  void _onLimitSubmit(String value) {
    final n = int.tryParse(value.trim());
    if (n == null) {
      _limitCtrl.text = '$_historyLimit';
      return;
    }
    final clamped = n.clamp(1, _kHistoryMax);
    setState(() => _historyLimit = clamped);
    _limitCtrl.text = '$clamped';
    final repo = context.read<RepositoryState>().activePath;
    if (repo != null) _load(repo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // History page only rebuilds when the active repo changes —
    // `git status` ticks no longer invalidate the whole history tree.
    final repoPath = context.select<RepositoryState, String?>(
      (s) => s.activePath,
    );

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    // Subscribe to the coupling matrix so tag profiles rebuild when it
    // arrives (hub, focused/sprawl, borrowed tags depend on it).
    final couplingReady = context.select<FileCouplingState, bool>(
      (s) => s.matrixFor(repoPath) != null,
    );
    if (couplingReady && _tagProfile.commitCount > 0 && _commits.isNotEmpty) {
      _scheduleTagProfileRebuild(repoPath);
    }

    if (_lastRepo != repoPath) {
      _lastRepo = repoPath;
      _commits = [];
      _reflog = [];
      _reflogLoaded = false;
      _detail = null;
      _selectedHash = null;
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(repoPath));
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
          Text('History',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.05)),
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
          commits: _commits,
          selectedHash: _selectedHash,
          onSelected: (hash) {
            setState(() {
              _selectedHash = hash;
              _rebaseRangeEndIndex = null;
              _tagInputVisible = false;
            });
            _loadDetail(repoPath, hash);
          },
          tokens: t,
          detailCache: _detailCache,
          detailCacheVersion: _detailCacheVersion,
          trunkHashes: _trunkHashes,
          previewCommits: _previewDeskPath == null
              ? const []
              : (_previewCommitsCache[_previewDeskPath] ?? const []),
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
                  onPreviewHover: (deskPath, branch) =>
                      _onPreviewDeskHover(repoPath, deskPath, branch),
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
                      final preview = _previewDeskPath == null
                          ? const <CommitHistoryEntry>[]
                          : (_previewCommitsCache[_previewDeskPath] ??
                              const <CommitHistoryEntry>[]);
                      final previewCount = preview.length;
                      return ListView.builder(
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
                                  'prev:${_previewDeskPath}:${preview[rawIndex].commitHash}'),
                              commit: preview[rawIndex],
                              tokens: t,
                              indexInPreview: rawIndex,
                              totalPreview: previewCount,
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
                            _selectedHash = entry.commitHash;
                            _rebaseRangeEndIndex = null;
                            // A new commit selection clears any
                            // open per-file diff from the previous one.
                            _commitDiffFile = null;
                            _commitDiffContent = null;
                            _commitDiffError = null;
                            _commitDiffLoading = false;
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
                              onToggleTag: () => setState(() {
                                _tagInputVisible = !_tagInputVisible;
                                _tagError = null;
                              }),
                              onTagChanged: (v) =>
                                  setState(() => _tagInputValue = v),
                              onCreateTag: () =>
                                  _createTag(repoPath, _detail!.commitHash),
                              onOpenFile: (path) => _openCommitFileDiff(
                                  repoPath, _detail!.commitHash, path),
                              onOpenAllFiles: () => _openCommitAllDiff(
                                  repoPath, _detail!.commitHash),
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
    required this.onTap,
    this.onSecondaryTap,
  });
  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _hovered = false;
  bool _pressed = false;

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
                    : (_hovered
                        ? t.itemHoverBg
                        : t.itemHoverBg.withValues(alpha: 0)),
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
                    fontFamily: AppFonts.mono,
                    fontWeight:
                        widget.isSelected ? FontWeight.w700 : FontWeight.w600,
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
                    // Greedy fit is the only gate; show what fits.
                    gitTagNames: c.refNames
                        .where((r) => r.startsWith('tag:'))
                        .map((r) => r.replaceFirst('tag: ', ''))
                        .toList(),
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
    fontFamily: AppFonts.mono,
    letterSpacing: 0.2,
  );

  double _measureTextWidth(String label) {
    final tp = TextPainter(
      text: TextSpan(text: label.toLowerCase(), style: _pillTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
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
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon(name: 'tag', size: 9, color: t.accentBright),
        const SizedBox(width: 3),
        Text(name,
            style: TextStyle(
                color: t.accentBright,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                fontFamily: AppFonts.mono)),
      ]),
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
                    borderRadius: BorderRadius.circular(3)),
                child: Text(e.refSelector,
                    style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9,
                        fontFamily: AppFonts.mono)),
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
                      fontFamily: AppFonts.mono)),
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
  final VoidCallback onToggleTag;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onCreateTag;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenAllFiles;
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
    required this.onToggleTag,
    required this.onTagChanged,
    required this.onCreateTag,
    required this.onOpenFile,
    required this.onOpenAllFiles,
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

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final d = detail;
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

      // Metadata row: avatar | name | · | date | · | hash | · | tag
      Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Author avatar + name
          if (d.authorName.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: t.chromeAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                    child: Text(
                  d.authorName[0].toUpperCase(),
                  style: TextStyle(
                      color: t.textStrong,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                )),
              ),
              const SizedBox(width: 6),
              Text(d.authorName,
                  style: TextStyle(
                      color: t.textNormal,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ]),
          Text('·',
              style: TextStyle(
                  color: t.textFaint, fontSize: 12)),
          // Date
          Text(_formatDate(d.authoredAt),
              style: TextStyle(color: t.textMuted, fontSize: 11)),
          Text('·',
              style: TextStyle(
                  color: t.textFaint, fontSize: 12)),
          // Short hash
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: t.chromeAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4)),
            child: Text(d.shortHash,
                style: TextStyle(
                    color: t.accentBright,
                    fontSize: 11,
                    fontFamily: AppFonts.mono)),
          ),
          Text('·',
              style: TextStyle(
                  color: t.textFaint, fontSize: 12)),
          // Tag affordance
          GestureDetector(
            onTap: onToggleTag,
            child: AnimatedContainer(
              duration: context.motion(context.surfaceShader.duration),
              curve: context.surfaceShader.safeCurve,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tagInputVisible
                    ? t.itemActiveBg
                    : t.chromeAccent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: tagInputVisible
                      ? t.itemActiveBorder
                      : t.chromeAccent.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    name: 'tag',
                    size: 12,
                    color: tagInputVisible
                        ? t.accentBright
                        : t.textMuted.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tagInputVisible ? 'Close tag' : 'Create tag',
                    style: TextStyle(
                      color: tagInputVisible ? t.accentBright : t.textNormal,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // Inline tag input (expands below metadata when visible)
      if (tagInputVisible) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: KeyboardListener(
              focusNode: tagEscapeFocus,
              onKeyEvent: (e) {
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.escape) {
                  onToggleTag();
                }
              },
              child: AppTextField(
                controller: tagController,
                autofocus: true,
                height: 28,
                fontSize: 12,
                hintText: 'tag name...',
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                onChanged: onTagChanged,
                onSubmitted: (_) => onCreateTag(),
              ),
            ),
          ),
        ]),
      ],

      if (tagError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tagError!,
              style: TextStyle(color: t.stateConflicted, fontSize: 10)),
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
  final VoidCallback onToggleTag;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onCreateTag;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onOpenAllFiles;
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
    required this.onToggleTag,
    required this.onTagChanged,
    required this.onCreateTag,
    required this.onOpenFile,
    required this.onOpenAllFiles,
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
            onToggleTag: onToggleTag,
            onTagChanged: onTagChanged,
            onCreateTag: onCreateTag,
            onOpenFile: onOpenFile,
            onOpenAllFiles: onOpenAllFiles,
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
                    fontFamily: AppFonts.mono,
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
            borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(4),
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
  bool _running = false;
  String? _error;
  static const _actions = ['pick', 'reword', 'squash', 'fixup', 'drop'];

  @override
  void initState() {
    super.initState();
    _todo = widget.commits
        .map((c) =>
            {'action': 'pick', 'hash': c.commitHash, 'subject': c.subject})
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rebase ${_todo.length} commit${_todo.length == 1 ? "" : "s"}',
              style: TextStyle(
                  color: t.textStrong,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Select actions for each commit',
              style: TextStyle(color: t.textMuted, fontSize: 11)),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _todo.length,
          itemBuilder: (ctx, i) {
            final entry = _todo[i];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(7),
                border:
                    Border.all(color: t.chromeBorder.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                SizedBox(
                  width: 120,
                  child: AppDropdownField<String>(
                    value: entry['action']!,
                    height: 24,
                    fontSize: 11,
                    menuColor: t.bg2,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    items: _actions
                        .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _todo[i] = {...entry, 'action': v});
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(entry['hash']!.substring(0, min(7, entry['hash']!.length)),
                    style: TextStyle(
                        color: t.textMuted,
                        fontSize: 10,
                        fontFamily: AppFonts.mono)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(entry['subject']!,
                        style: TextStyle(color: t.textNormal, fontSize: 11),
                        overflow: TextOverflow.ellipsis)),
              ]),
            );
          },
        ),
      ),
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
                  enabled: !_running,
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
              borderRadius: BorderRadius.circular(8),
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
class _DesksInFlightStrip extends StatelessWidget {
  final AppTokens tokens;
  final String activeRepoPath;
  final ValueChanged<String> onJumpToDesk;
  /// Hover-preview signal. Fires `(deskPath, branch)` when the cursor
  /// enters a chip; fires `(null, '')` when it leaves. The page uses
  /// it to populate its commit list + timeline with the desk's
  /// diverged commits in real time. Optional — when null the chips
  /// are click-only and behave like the original IN FLIGHT strip.
  final void Function(String? deskPath, String branch)? onPreviewHover;

  const _DesksInFlightStrip({
    required this.tokens,
    required this.activeRepoPath,
    required this.onJumpToDesk,
    this.onPreviewHover,
  });

  String _normalize(String p) {
    final n = p.replaceAll('\\', '/');
    return Platform.isLinux ? n : n.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final worktreeState = context.watch<WorktreeState>();
    final activeNorm = _normalize(activeRepoPath);
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
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: inFlight.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final (desk, ahead) = inFlight[i];
                  final label = desk.branch ??
                      (desk.isDetached
                          ? desk.head.substring(
                              0, desk.head.length < 7 ? desk.head.length : 7)
                          : 'desk');
                  return _InFlightDeskChip(
                    tokens: t,
                    label: label,
                    ahead: ahead,
                    onTap: () => onJumpToDesk(desk.path),
                    onHoverChange: (hovering) =>
                        onPreviewHover?.call(
                            hovering ? desk.path : null,
                            hovering ? (desk.branch ?? '') : ''),
                  );
                },
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
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _hovered
                  ? t.accentBright.withValues(alpha: 0.5)
                  : t.chromeBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: _hovered ? t.textStrong : t.textNormal,
                  fontSize: 10.5,
                  fontFamily: AppFonts.mono,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '↑${widget.ahead}',
                style: TextStyle(
                  color: t.stateAdded,
                  fontSize: 10,
                  fontFamily: AppFonts.mono,
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
  const _PreviewCommitRow({
    super.key,
    required this.commit,
    required this.tokens,
    required this.indexInPreview,
    required this.totalPreview,
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
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          decoration: BoxDecoration(
            color: t.accentBright.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
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
                      fontFamily: AppFonts.mono)),
              const SizedBox(width: 6),
              Text(shortHash,
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontFamily: AppFonts.mono)),
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
    );
  }
}
