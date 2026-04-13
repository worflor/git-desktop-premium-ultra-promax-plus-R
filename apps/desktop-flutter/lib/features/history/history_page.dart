import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
import '../../ui/morph_text.dart';
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
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';
import 'commit_tag_pill.dart';
import 'commit_tagger.dart';

// ── Constants (matching original) ────────────────────────────────────────────

const double _kNodeRadius = 3;
const double _kVertInset = 8;
const double _kHorizPad = 4;
const double _kLeftPad = 6;
const double _kMinLaneH = 42;
const double _kScaleFocus = 0.45;
const double _kScaleSelected = 1.25;
const double _kScaleHover = 1.1;
const double _kScaleMerge = 1.05;
const double _kGapLog = 1.1;
const double _kTemporalBlend = 0.32;
const double _kLensMin = 32;
const double _kLensMax = 64;
const int _kHistoryDefault = 50;
const int _kHistoryMax = 500;

// ── Graph types ───────────────────────────────────────────────────────────────

class _GNode {
  final CommitHistoryEntry entry;
  final int row, lane;
  final List<String> visibleParents;
  const _GNode(
      {required this.entry,
      required this.row,
      required this.lane,
      required this.visibleParents});
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

// ── Graph builder ─────────────────────────────────────────────────────────────

_GLayout _buildLayout(List<CommitHistoryEntry> entries) {
  final visibleHashes = entries.map((e) => e.commitHash).toSet();
  final activeLanes = <String?>[];
  final hashToNode = <String, _GNode>{};
  int laneCount = 1;

  int reserveLane(String hash, {int? preferred}) {
    final existing = activeLanes.indexWhere((h) => h == hash);
    if (existing >= 0) return existing;
    if (preferred != null &&
        preferred < activeLanes.length &&
        activeLanes[preferred] == null) {
      activeLanes[preferred] = hash;
      return preferred;
    }
    final empty = activeLanes.indexWhere((h) => h == null);
    if (empty >= 0) {
      activeLanes[empty] = hash;
      return empty;
    }
    activeLanes.add(hash);
    return activeLanes.length - 1;
  }

  final nodes = <_GNode>[];
  for (int row = 0; row < entries.length; row++) {
    final entry = entries[row];
    int lane = activeLanes.indexWhere((h) => h == entry.commitHash);
    if (lane < 0) lane = reserveLane(entry.commitHash);
    activeLanes[lane] = null;

    final parents =
        entry.parentHashes.where((h) => visibleHashes.contains(h)).toList();
    if (parents.isNotEmpty) reserveLane(parents[0], preferred: lane);
    for (int p = 1; p < parents.length; p++) reserveLane(parents[p]);

    while (activeLanes.isNotEmpty && activeLanes.last == null)
      activeLanes.removeLast();
    laneCount = max(laneCount, max(lane + 1, activeLanes.length));

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

  // Build hash→index once so the painter can drop its per-paint map.
  final hashToIndex = <String, int>{
    for (var i = 0; i < nodes.length; i++) nodes[i].entry.commitHash: i,
  };
  return _GLayout(
      nodes: nodes,
      edges: edges,
      laneCount: laneCount,
      hashToIndex: hashToIndex);
}

// ── Temporal position computation ─────────────────────────────────────────────

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

// ── Lens metrics ─────────────────────────────────────────────────────────────

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

// ── Timeline painter ──────────────────────────────────────────────────────────

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
  }) : super(
          repaint: Listenable.merge(
              [hoveredHashListenable, hoverXListenable, churnIntro]),
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

    // Rail
    final railY = vertInset + laneStep / 2;
    final leftX =
        baseXs.isNotEmpty ? max(baseXs.first - _kNodeRadius, 0.0) : 0.0;
    final rightX =
        baseXs.isNotEmpty ? min(baseXs.last + _kNodeRadius, width) : width;
    canvas.drawLine(
      Offset(leftX, railY),
      Offset(rightX, railY),
      Paint()
        ..color = tokens.chromeAccent.withValues(alpha: 0.22)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Edges ───────────────────────────────────────────────────────
    // Two reusable Paints (mainline vs. branch) + one reusable Path
    // shared across every edge. Previously allocated ~2 objects per
    // edge per frame = up to 2000 allocs/frame on a 1000-edge graph.
    final mainlineEdgePaint = Paint()
      ..color = tokens.chromeAccent.withValues(alpha: 0.45)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final branchEdgePaint = Paint()
      ..color = tokens.textNormal.withValues(alpha: 0.28)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final edgePath = Path();
    for (final edge in layout.edges) {
      final fromIdx = hashToIndex[edge.from];
      final toIdx = hashToIndex[edge.to];
      if (fromIdx == null || toIdx == null) continue;
      final from = metrics[fromIdx];
      final to = metrics[toIdx];

      final dx = to.x - from.x;
      final dy = to.y - from.y;
      final dist2 = dx * dx + dy * dy;
      if (dist2 < 0.01) continue;
      // Sqrt once — downstream math needs scalar distance.
      final dist = sqrt(dist2);
      final inv = 1.0 / dist;
      final nx = dx * inv;
      final ny = dy * inv;
      final startX = from.x + nx * (_kNodeRadius * from.scale);
      final startY = from.y + ny * (_kNodeRadius * from.scale);
      final endX = to.x - nx * (_kNodeRadius * to.scale);
      final endY = to.y - ny * (_kNodeRadius * to.scale);

      final isMainline = edge.fromLane == 0 && edge.toLane == 0;
      final isSameLane = edge.fromLane == edge.toLane;

      edgePath.reset();
      edgePath.moveTo(startX, startY);
      if (isSameLane) {
        edgePath.lineTo(endX, endY);
      } else {
        final ctrlX = startX + (endX - startX) * 0.48;
        edgePath.cubicTo(ctrlX, startY, ctrlX, endY, endX, endY);
      }
      canvas.drawPath(
          edgePath, isMainline ? mainlineEdgePaint : branchEdgePaint);
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

    // ── Nodes ───────────────────────────────────────────────────────
    // Two reusable Paints — fill (color swaps per node) and selected
    // ring (constant). Replaces 2 Paint allocs per commit per frame.
    final nodeFillPaint = Paint()..style = PaintingStyle.fill;
    final selectedRingPaint = Paint()
      ..color = tokens.accentBright.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final fallbackNodeColor = tokens.chromeBorder.withValues(alpha: 0.7);
    final selectedNodeColor = tokens.accentBright;
    // Hoist intro value once per paint — avoids re-reading the
    // animation getter inside the per-node hot loop.
    final introValue = churnIntro.value;
    final introAtRest = introValue >= 1.0;
    final introAtStart = introValue <= 0.0;

    for (final node in drawOrder) {
      final hash = node.entry.commitHash;
      final idx = hashToIndex[hash];
      if (idx == null) continue;
      final m = metrics[idx];
      final isSelected = hash == selectedHash;

      final churn = churnNorm[hash] ?? 0.0;
      final r = _kNodeRadius * m.scale * (1.0 + churn * 0.5);

      final Color nodeColor;
      if (isSelected) {
        nodeColor = selectedNodeColor;
      } else {
        final target = targetColors[hash];
        if (target == null) {
          nodeColor = fallbackNodeColor;
        } else if (introAtRest) {
          // Steady state — vast majority of paints. Skip the lerp.
          nodeColor = target;
        } else if (introAtStart) {
          nodeColor = fallbackNodeColor;
        } else {
          // Only allocate a Color during the ~320ms intro fade.
          nodeColor =
              Color.lerp(fallbackNodeColor, target, introValue)!;
        }
      }

      nodeFillPaint.color = nodeColor;
      final center = Offset(m.x, m.y);
      canvas.drawCircle(center, r, nodeFillPaint);

      if (isSelected) {
        canvas.drawCircle(center, r + 1.5, selectedRingPaint);
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
      old.netRatio != netRatio;
}

// ── Timeline strip ────────────────────────────────────────────────────────────

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

  const _TimelineStrip({
    required this.commits,
    required this.selectedHash,
    required this.onSelected,
    required this.tokens,
    required this.detailCache,
    required this.detailCacheVersion,
  });

  @override
  State<_TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends State<_TimelineStrip>
    with SingleTickerProviderStateMixin {
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
  int _cacheVersion = 0;

  /// 0 → 1 fade controller for the gray→churn-color crossfade. Driven
  /// from `_rebuildChurnMaps`. The painter receives this as `repaint:`
  /// and lerps each node's color from `fallbackNodeColor` toward its
  /// computed churn color over the controller's value.
  late final AnimationController _churnIntroCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  static String _signatureOf(List<CommitHistoryEntry> commits) {
    if (commits.isEmpty) return '';
    return '${commits.length}|${commits.first.commitHash}|${commits.last.commitHash}';
  }

  @override
  void dispose() {
    _hoverXNotifier.dispose();
    _hoveredHashNotifier.dispose();
    _churnIntroCtrl.dispose();
    super.dispose();
  }

  void _rebuildLayout() {
    _layout = _buildLayout(widget.commits);
    _percents = _computePercents(widget.commits);
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
    _cacheVersion = widget.detailCacheVersion;
    // Crossfade the new colors in from the gray fallback. Same anim
    // for first-load AND subsequent refreshes — uniform feel.
    _churnIntroCtrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(_TimelineStrip old) {
    super.didUpdateWidget(old);
    final newSig = _signatureOf(widget.commits);
    if (_signatureOf(old.commits) != newSig) {
      // Content changed (length OR first/last hash). Force full rebuild;
      // _rebuildLayout also rebuilds churn maps so colors stay synced
      // with the new commit set.
      _layout = null;
    } else if (old.detailCacheVersion != widget.detailCacheVersion) {
      // Commits unchanged but cache mutated. The map is shared by
      // reference and mutated in place, so length/identity won't
      // change — only the parent-bumped version counter detects this.
      _rebuildChurnMaps();
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
      final laneCount = _layout!.laneCount;
      final height = max(_kMinLaneH, laneCount * 14.0 + 18.0);
      final laneStep =
          (height - _kVertInset * 2) / max(laneCount.toDouble(), 1);
      final totalHeight = height + _kVertInset * 2;

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

// ── CommitImpact ──────────────────────────────────────────────────────────────

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
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w700)),
      Text('/',
          style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.3),
              fontSize: 9,
              fontFamily: 'JetBrainsMono')),
      Text('$dels',
          style: TextStyle(
              color: t.stateDeleted.withValues(alpha: 0.9),
              fontSize: 9,
              fontFamily: 'JetBrainsMono',
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

// ── Tag-profile isolate payload ──────────────────────────────────────────────

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
  const _TagProfileInput({
    required this.commits,
    required this.details,
    required this.coupling,
    this.engineCoherences,
  });
}

/// Top-level so `compute()` can spawn it. Thin shim that just forwards
/// to [buildTagProfile]; the isolate boundary demands a top-level fn.
RepositoryTagProfile _tagProfileIsolate(_TagProfileInput input) {
  return buildTagProfile(
    commits: input.commits,
    detailsByHash: input.details,
    coupling: input.coupling,
    engineCoherences: input.engineCoherences,
  );
}

// ── History page ──────────────────────────────────────────────────────────────

class HistoryPage extends StatefulWidget {
  final String? initialCommitHash;
  final VoidCallback? onOpenXray;

  const HistoryPage({super.key, this.initialCommitHash, this.onOpenXray});

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
  /// Bumped on every `_detailCache` mutation. The map is shared by
  /// reference with `_TimelineStrip`, so length/identity comparisons
  /// at `didUpdateWidget` can't see the mutation. This counter is the
  /// "cache changed" signal the timeline uses to refresh churn colors.
  int _detailCacheVersion = 0;

  /// Auto-derived tag profile for the currently-loaded history window.
  /// Rebuilt in a background isolate whenever the commit set or detail
  /// cache materially grows (debounced — see [_scheduleTagProfileRebuild]).
  /// Every field is derived from this repo's own data; nothing is
  /// hardcoded.
  RepositoryTagProfile _tagProfile = RepositoryTagProfile.empty;
  int _tagProfileBuildId = 0;
  Timer? _tagProfileDebounce;

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

  // Shift-select rebase range
  int? _rebaseRangeEndIndex;
  bool get _isRebaseMode => _rebaseRangeEndIndex != null;

  String? _lastRepo;

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
      try {
        final engine =
            context.read<LogosGitState>().engineFor(repoPath);
        if (engine != null) {
          engineCoherences = <String, double>{};
          for (final entry in detailsCopy.entries) {
            final files = entry.value.files.map((f) => f.path);
            engineCoherences[entry.key] = engine.coherence(files);
          }
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
      ));
      if (!mounted || myBuildId != _tagProfileBuildId) return;
      setState(() => _tagProfile = profile);
    });
  }

  Future<void> _load(String repo) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await listCommitHistory(repo, limit: _historyLimit);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _commits = r.data!;
      } else {
        _error = r.error;
      }
    });
    // Kick off bulk prefetch immediately — runs in background, no await
    if (r.ok) {
      unawaited(_prefetchAllDetails(repo));
      // First profile build runs on subject-only data (no details yet).
      // Prefix/scope/merge tags light up immediately; axis + cluster
      // tags fill in as the bulk prefetch populates the detail cache.
      _scheduleTagProfileRebuild(repo);
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
    final repo = context.watch<RepositoryState>();
    final repoPath = repo.activePath;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    if (_lastRepo != repoPath) {
      _lastRepo = repoPath;
      _commits = [];
      _reflog = [];
      _reflogLoaded = false;
      _detail = null;
      _selectedHash = null;
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
      // ── History controls ─────────────────────────────────────────────
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
          if (widget.onOpenXray != null) ...[
            const SizedBox(width: 10),
            _HistoryMiniButton(
              label: 'Repo X-Ray',
              icon: 'search',
              onTap: widget.onOpenXray!,
            ),
          ],
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

      // ── Timeline strip ───────────────────────────────────────────────
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
        ),

      // ── Main content ─────────────────────────────────────────────────
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
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 200) _loadReflog(repoPath);
                return false;
              },
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount:
                    _commits.length + (_reflogLoaded ? _reflog.length + 1 : 1),
                itemBuilder: (ctx, i) {
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
                      onTap: (shift) => _onCommitTap(i, shift),
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
                          });
                          _loadDetail(repoPath, entry.commitHash);
                        });
                  }
                  return const SizedBox.shrink();
                },
              ),
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
                          ? _CommitDetailTransition(
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

// ── Commit row ────────────────────────────────────────────────────────────────

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
  final void Function(bool shift) onTap;
  const _CommitRow({
    required this.commit,
    required this.tokens,
    required this.isSelected,
    required this.inRange,
    required this.cachedDetail,
    required this.tagProfile,
    required this.couplingMatrix,
    required this.logosEngine,
    required this.onTap,
  });
  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _hovered = false;

  /// Computes the auto-tags for this row. Kept trivial and
  /// synchronous — the heavy lifting (profile construction) already
  /// happened off-isolate; per-row tagging is a handful of string and
  /// numeric comparisons.
  List<CommitTag> _autoTagsFor(CommitHistoryEntry c) {
    if (widget.tagProfile.commitCount == 0) return const [];
    double? engineCoherence;
    final detail = widget.cachedDetail;
    final engine = widget.logosEngine;
    if (engine != null && detail != null && detail.files.length >= 2) {
      engineCoherence = engine.coherence(detail.files.map((f) => f.path));
    }
    return tagCommit(
      commit: c,
      detail: detail,
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

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final shift = HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.shiftLeft) ||
              HardwareKeyboard.instance.logicalKeysPressed
                  .contains(LogicalKeyboardKey.shiftRight);
          widget.onTap(shift);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
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
                    fontFamily: 'JetBrainsMono',
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
                // Auto-derived semantic tags (repo-learned vocabulary,
                // zero hardcoded values). Computed here per-build; the
                // work is microseconds once the profile is warm.
                ..._autoTagsFor(c).map(
                  (tg) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: CommitTagPill(tag: tg, tokens: t),
                  ),
                ),
                // Git-native tag pills (annotated tags on the commit).
                ...c.refNames.where((r) => r.startsWith('tag:')).take(2).map(
                      (r) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: _TagPill(
                              name: r.replaceFirst('tag: ', ''), tokens: t)),
                    ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Text(c.authorName,
                    style: TextStyle(color: t.textMuted, fontSize: 11)),
                const Spacer(),
                _CommitImpact(detail: widget.cachedDetail, tokens: t),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Reflog divider ────────────────────────────────────────────────────────────

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

// ── Tag pill ──────────────────────────────────────────────────────────────────

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
                fontFamily: 'JetBrainsMono')),
      ]),
    );
  }
}

// ── Reflog row ────────────────────────────────────────────────────────────────

class _ReflogRow extends StatefulWidget {
  final ReflogEntryData entry;
  final AppTokens tokens;
  final VoidCallback onTap;
  const _ReflogRow(
      {required this.entry, required this.tokens, required this.onTap});
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
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
                        fontFamily: 'JetBrainsMono')),
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
                      fontFamily: 'JetBrainsMono')),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Commit detail ─────────────────────────────────────────────────────────────

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
  });

  static String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  List<Widget> _buildGroupedFiles(List<CommitFileStatData> files,
      AppTokens t, Set<String> dirtyPaths) {
    // Group by module
    final grouped = <String, List<CommitFileStatData>>{};
    for (final f in files) {
      grouped.putIfAbsent(_moduleFromPath(f.path), () => []).add(f);
    }

    final widgets = <Widget>[];
    bool first = true;
    for (final entry in grouped.entries) {
      if (!first) widgets.add(const SizedBox(height: 10));
      first = false;

      // Module header
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text(entry.key,
              style: TextStyle(
                  color: t.textFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(width: 3),
          Text('/',
              style: TextStyle(color: t.textFaint.withValues(alpha: 0.5), fontSize: 10)),
        ]),
      ));

      // File rows
      for (final f in entry.value) {
        final normalizedPath = f.path.replaceAll('\\', '/');
        // Both dirtyPaths (from git status) and normalizedPath (from
        // git show) are repo-root-relative, so direct equality is correct.
        final isDirty = dirtyPaths.contains(normalizedPath);
        final displayName = _displayPath(f.path, entry.key);

        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(children: [
            // Change type badge
            _ChangeTypeBadge(type: f.changeType, tokens: t),
            const SizedBox(width: 6),
            // Dirty indicator dot
            if (isDirty) ...[
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: t.accentBright,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            // File name
            Expanded(
              child: Text(displayName,
                  style: TextStyle(
                      color: isDirty ? t.textStrong : t.textNormal,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono'),
                  overflow: TextOverflow.ellipsis),
            ),
            // Stats
            Text('+${f.additions}',
                style: TextStyle(color: t.stateAdded, fontSize: 10)),
            const SizedBox(width: 4),
            Text('-${f.deletions}',
                style: TextStyle(color: t.stateDeleted, fontSize: 10)),
          ]),
        ));
      }
    }
    return widgets;
  }

  static String _moduleFromPath(String path) {
    final p = path.replaceAll('\\', '/');
    final libIdx = p.indexOf('/lib/');
    if (libIdx >= 0) {
      final afterLib = p.substring(libIdx + 5);
      final slash = afterLib.indexOf('/');
      return slash >= 0 ? afterLib.substring(0, slash) : afterLib;
    }
    if (p.contains('/test/')) return 'test';
    final parts = p.split('/').where((s) => s.isNotEmpty).toList();
    return parts.length > 1 ? parts[parts.length - 2] : 'other';
  }

  static String _displayPath(String path, String module) {
    final p = path.replaceAll('\\', '/');
    final marker = '/lib/$module/';
    final idx = p.indexOf(marker);
    if (idx >= 0) return p.substring(idx + marker.length);
    final testIdx = p.indexOf('/test/');
    if (testIdx >= 0) return p.substring(testIdx + 6);
    return p.split('/').last;
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
      ThemeMorphText(
        d.subject,
        style: TextStyle(
            color: t.textStrong,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.35),
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
                    fontFamily: 'JetBrainsMono')),
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
              focusNode: FocusNode(),
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
                hintText: 'Tag name...',
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
        _StatChip(
            label: '${d.filesChanged} file${d.filesChanged == 1 ? "" : "s"}',
            color: t.textMuted),
        const SizedBox(width: 6),
        _StatChip(label: '+${d.additions}', color: t.stateAdded),
        const SizedBox(width: 4),
        _StatChip(label: '-${d.deletions}', color: t.stateDeleted),
      ]),

      const SizedBox(height: 16),
      ..._buildGroupedFiles(d.files, t, dirtyPaths),
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
          duration: const Duration(milliseconds: 80),
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
  const _StatChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

class _ChangeTypeBadge extends StatelessWidget {
  final String type;
  final AppTokens tokens;
  const _ChangeTypeBadge({required this.type, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final Color color;
    switch (type) {
      case 'A':
        color = t.stateAdded;
        break;
      case 'D':
        color = t.stateDeleted;
        break;
      case 'R':
        color = t.accentBright;
        break;
      case 'C':
        color = t.accentBright.withValues(alpha: 0.8);
        break;
      default: // 'M' and others
        color = t.textFaint;
    }
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(type.substring(0, 1),
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrainsMono')),
    );
  }
}

// ── Rebase editor ─────────────────────────────────────────────────────────────

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
                        fontFamily: 'JetBrainsMono')),
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
