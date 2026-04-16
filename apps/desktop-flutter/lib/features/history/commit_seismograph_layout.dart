import 'dart:math' as math;

import '../../backend/dtos.dart';

/// Pure layout for the commit-detail seismograph.
/// The panel is a recursively-subdivided view of the directory tree of a
/// commit's touched files. The shape emerges from two real visual
/// constraints — `minTrackPx` (one readable line of label) and
/// `minSegmentPx` (one legible glyph wide) — plus the panel rect. There
/// are no file-count thresholds; a 1-file commit and a 10000-file commit
/// flow through the same code path.

/// Internal dir-tree node. Aggregates churn upward at construction time.
class SeismographNode {
  final String name;
  final List<String> path;
  final Map<String, SeismographNode> children = {};
  CommitFileStatData? file;
  int additions = 0;
  int deletions = 0;
  int leafCount = 0;

  SeismographNode(this.name, this.path);

  int get churn => additions + deletions;
  bool get isLeaf => file != null;
}

/// One vertical band — represents the immediate child of the focus node.
class SeismographTrack {
  final List<String> path;
  final String label;
  final double top;
  final double height;
  final List<SeismographSegment> segments;
  final bool isOverflowBucket;

  const SeismographTrack({
    required this.path,
    required this.label,
    required this.top,
    required this.height,
    required this.segments,
    this.isOverflowBucket = false,
  });
}

/// One horizontal cell within a track. Either a file (leaf), a
/// container the user can drill into, or an info-only fold (when there
/// is no meaningful place to drill — e.g. an overflow bucket whose
/// children are already at the focus level).
class SeismographSegment {
  final List<String> path;
  final String label;
  final double left;
  final double width;
  final int additions;
  final int deletions;
  final CommitFileStatData? file;
  final int containedFileCount;
  final bool isDrillable;

  const SeismographSegment({
    required this.path,
    required this.label,
    required this.left,
    required this.width,
    required this.additions,
    required this.deletions,
    this.file,
    required this.containedFileCount,
    this.isDrillable = false,
  });

  bool get isLeaf => file != null;
  int get churn => additions + deletions;
}

/// Final laid-out panel. Either a single-file row OR a stack of tracks.
class SeismographLayout {
  final List<String> focusPath;
  final List<SeismographTrack> tracks;
  final SeismographSegment? singleFile;

  const SeismographLayout({
    required this.focusPath,
    required this.tracks,
    this.singleFile,
  });

  bool get isEmpty => tracks.isEmpty && singleFile == null;
}

class SeismographConstraints {
  final double width;
  final double height;
  final double minTrackPx;
  final double minSegmentPx;

  const SeismographConstraints({
    required this.width,
    required this.height,
    required this.minTrackPx,
    required this.minSegmentPx,
  });
}

/// Build a directory tree from a commit's file list. Aggregates additions,
/// deletions, and leaf counts at every ancestor.
SeismographNode buildSeismographTree(List<CommitFileStatData> files) {
  final root = SeismographNode('', const []);
  for (final f in files) {
    final parts = f.path
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) continue;
    var cur = root;
    cur.additions += f.additions;
    cur.deletions += f.deletions;
    cur.leafCount += 1;
    for (var i = 0; i < parts.length; i++) {
      final name = parts[i];
      final childPath = [...cur.path, name];
      final node = cur.children
          .putIfAbsent(name, () => SeismographNode(name, childPath));
      node.additions += f.additions;
      node.deletions += f.deletions;
      node.leafCount += 1;
      if (i == parts.length - 1) node.file = f;
      cur = node;
    }
  }
  return root;
}

/// Walk the focus path. If the focus lands on a node with exactly one
/// child, hoist *down* through the single-child chain so the user lands
/// on the first node with real branching (or a leaf). The effective
/// path is what the breadcrumb should show.
({SeismographNode node, List<String> effectivePath}) _resolveFocus(
    SeismographNode root, List<String> focusPath) {
  var cur = root;
  for (final seg in focusPath) {
    final next = cur.children[seg];
    if (next == null) break;
    cur = next;
  }
  while (!cur.isLeaf && cur.children.length == 1) {
    cur = cur.children.values.first;
  }
  return (node: cur, effectivePath: List.unmodifiable(cur.path));
}

/// Hoist a node down through any single-child chain; return the
/// resolved descendant and the joined display label
/// (e.g. `lib/backend/ai`).
({SeismographNode node, String label}) _hoist(SeismographNode n) {
  var cur = n;
  final names = <String>[cur.name];
  while (!cur.isLeaf && cur.children.length == 1) {
    cur = cur.children.values.first;
    names.add(cur.name);
  }
  return (
    node: cur,
    label: names.where((s) => s.isNotEmpty).join('/'),
  );
}

/// Allocate vertical space across tracks: share-based by churn, clamped
/// to `minTrackPx`. Reclaims slack from over-min tracks to satisfy the
/// floor. If even the floors don't fit, height is divided equally.
List<double> _allocateHeights(
    List<int> churns, double height, double minTrackPx) {
  final n = churns.length;
  if (n == 0) return const [];
  final floorTotal = n * minTrackPx;
  if (floorTotal >= height) {
    return List.filled(n, height / n);
  }
  final total = churns.fold<int>(0, (a, c) => a + c);
  final ideal = total == 0
      ? List.filled(n, height / n)
      : churns.map((c) => (c / total) * height).toList();
  // Clamp up to the floor; debt is the extra we owe.
  final clamped = ideal.map((h) => math.max(h, minTrackPx)).toList();
  final overshoot = clamped.fold<double>(0, (a, h) => a + h) - height;
  if (overshoot <= 0) return clamped;
  // Take the overshoot back, proportionally, from tracks that have slack
  // above the floor.
  final slack = clamped.map((h) => h - minTrackPx).toList();
  final slackTotal = slack.fold<double>(0, (a, s) => a + s);
  if (slackTotal <= 0) return List.filled(n, height / n);
  return [
    for (var i = 0; i < n; i++)
      clamped[i] - overshoot * (slack[i] / slackTotal)
  ];
}

/// All leaves (files) anywhere under `n`, in DFS order. For a leaf
/// node, returns `[n]` itself.
List<SeismographNode> _collectLeaves(SeismographNode n) {
  if (n.isLeaf) return [n];
  final out = <SeismographNode>[];
  for (final c in n.children.values) {
    out.addAll(_collectLeaves(c));
  }
  return out;
}

/// Display path for a leaf relative to the track's subdir. Strips the
/// track's path prefix; falls back to the file's own basename.
String _relPath(SeismographNode leaf, List<String> trackPath) {
  if (leaf.path.length <= trackPath.length) return leaf.name;
  return leaf.path.skip(trackPath.length).join('/');
}

SeismographLayout layoutSeismograph({
  required SeismographNode root,
  required SeismographConstraints c,
  List<String> focusPath = const [],
}) {
  final resolved = _resolveFocus(root, focusPath);
  final focus = resolved.node;

  if (focus.isLeaf) {
    return SeismographLayout(
      focusPath: resolved.effectivePath,
      tracks: const [],
      singleFile: SeismographSegment(
        path: focus.path,
        label: focus.path.join('/'),
        left: 0,
        width: c.width,
        additions: focus.additions,
        deletions: focus.deletions,
        file: focus.file,
        containedFileCount: 1,
      ),
    );
  }

  if (focus.children.isEmpty) {
    return SeismographLayout(
      focusPath: resolved.effectivePath, tracks: const [],
    );
  }

  // Partition focus's direct children into subdir-tracks and a single
  // synthetic "here" track holding any leaves residing directly under
  // the focus dir.
  final subdirChildren = <SeismographNode>[];
  final hereLeaves = <SeismographNode>[];
  for (final ch in focus.children.values) {
    if (ch.isLeaf) {
      hereLeaves.add(ch);
    } else {
      subdirChildren.add(ch);
    }
  }
  subdirChildren.sort((a, b) => b.churn.compareTo(a.churn));

  // Each subdir becomes a candidate track; the "here" group becomes one.
  final candidates = <_TrackInput>[
    for (final n in subdirChildren) _TrackInput.subdir(n),
    if (hereLeaves.isNotEmpty)
      _TrackInput.here(focus.path, focus.name, hereLeaves),
  ]..sort((a, b) => b.churn.compareTo(a.churn));

  final selected = _selectTracks(candidates, c.height, c.minTrackPx);
  final overflow = candidates.skip(selected.length).toList();
  final laidOut = <_TrackInput>[
    ...selected,
    if (overflow.isNotEmpty) _TrackInput.overflow(focus.path, overflow),
  ];

  final heights = _allocateHeights(
    laidOut.map((t) => t.churn).toList(),
    c.height,
    c.minTrackPx,
  );

  final tracks = <SeismographTrack>[];
  double y = 0;
  for (var i = 0; i < laidOut.length; i++) {
    final t = laidOut[i];
    // Snap the final track to consume the panel exactly — kills the
    // accumulated float drift that would let the bottom hairline draw
    // half a pixel outside the clip.
    final h = (i == laidOut.length - 1) ? c.height - y : heights[i];
    tracks.add(t.layout(
      top: y, height: h, width: c.width, minSegmentPx: c.minSegmentPx,
    ));
    y += h;
  }

  return SeismographLayout(
    focusPath: resolved.effectivePath,
    tracks: tracks,
  );
}

/// Greedy pick from a churn-sorted list of candidate tracks; reserve a
/// floor for the overflow bucket if anything won't fit.
List<_TrackInput> _selectTracks(
    List<_TrackInput> sortedDesc, double height, double minTrackPx) {
  final selected = <_TrackInput>[];
  for (var i = 0; i < sortedDesc.length; i++) {
    final wouldOverflow = i + 1 < sortedDesc.length;
    final reserve = wouldOverflow ? minTrackPx : 0.0;
    if ((selected.length + 1) * minTrackPx + reserve <= height) {
      selected.add(sortedDesc[i]);
    } else {
      break;
    }
  }
  return selected;
}

/// Internal track spec — knows how to render itself once allocated a slot.
sealed class _TrackInput {
  int get churn;

  factory _TrackInput.subdir(SeismographNode n) = _SubdirTrack;
  factory _TrackInput.here(
          List<String> path, String name, List<SeismographNode> leaves) =
      _HereTrack;
  factory _TrackInput.overflow(
          List<String> parentPath, List<_TrackInput> children) =
      _OverflowTrack;

  SeismographTrack layout({
    required double top,
    required double height,
    required double width,
    required double minSegmentPx,
  });
}

class _SubdirTrack implements _TrackInput {
  final SeismographNode node;
  _SubdirTrack(this.node);

  @override
  int get churn => node.churn;

  @override
  SeismographTrack layout({
    required double top,
    required double height,
    required double width,
    required double minSegmentPx,
  }) {
    final hoisted = _hoist(node);
    final h = hoisted.node;
    final leaves = _collectLeaves(h);
    final segments = _layoutLeafSegments(
      trackPath: h.path,
      leaves: leaves,
      width: width,
      minSegmentPx: minSegmentPx,
      foldDrillPath: h.path,
      // A subdir-track fold drills *into* the subdir — meaningful action.
      foldIsDrillable: true,
    );
    return SeismographTrack(
      path: h.path, label: hoisted.label, top: top, height: height,
      segments: segments,
    );
  }
}

class _HereTrack implements _TrackInput {
  final List<String> path;
  final String name;
  final List<SeismographNode> leaves;
  _HereTrack(this.path, this.name, this.leaves);

  @override
  int get churn => leaves.fold<int>(0, (a, n) => a + n.churn);

  @override
  SeismographTrack layout({
    required double top,
    required double height,
    required double width,
    required double minSegmentPx,
  }) {
    final segments = _layoutLeafSegments(
      trackPath: path,
      leaves: leaves,
      width: width,
      minSegmentPx: minSegmentPx,
      // Here-track folds can't be drilled — they're already at the
      // focus level. Fold target = focus = no-op.
      foldDrillPath: null,
      foldIsDrillable: false,
    );
    return SeismographTrack(
      path: path,
      // Loose-files-at-focus-dir track. Show the focus dir's name in
      // parens so first-time readers see "(backend)" rather than the
      // cryptic "./".
      label: path.isEmpty ? '(root)' : '(${path.last})',
      top: top, height: height,
      segments: segments,
    );
  }
}

class _OverflowTrack implements _TrackInput {
  final List<String> parentPath;
  final List<_TrackInput> children;
  _OverflowTrack(this.parentPath, this.children);

  @override
  int get churn => children.fold<int>(0, (a, c) => a + c.churn);

  @override
  SeismographTrack layout({
    required double top,
    required double height,
    required double width,
    required double minSegmentPx,
  }) {
    // The overflow bucket's "leaves" are actually the dropped tracks'
    // collected leaves. Each contributes its own subtree's leaves so
    // segment widths reflect real per-file churn.
    final allLeaves = <SeismographNode>[];
    for (final c in children) {
      switch (c) {
        case _SubdirTrack(:final node):
          allLeaves.addAll(_collectLeaves(node));
        case _HereTrack(:final leaves):
          allLeaves.addAll(leaves);
        case _OverflowTrack():
          // Overflow buckets can't nest in our pipeline.
          break;
      }
    }
    final segments = _layoutLeafSegments(
      trackPath: parentPath,
      leaves: allLeaves,
      width: width,
      minSegmentPx: minSegmentPx,
      // Overflow bucket lives at the focus dir. Drilling its fold would
      // re-enter the same focus → no-op. Mark the fold informational.
      foldDrillPath: parentPath,
      foldIsDrillable: false,
    );
    return SeismographTrack(
      path: parentPath,
      label: '+${children.length} more',
      top: top, height: height,
      segments: segments,
      isOverflowBucket: true,
    );
  }
}

/// Lay out leaf files as horizontal segments inside a track. Sort by
/// churn desc; the first leaf whose share-width would fall below
/// `minSegmentPx` triggers a tail-fold into one segment. If
/// `foldDrillPath` is non-null, the fold segment carries that path as
/// its drill target; otherwise it's purely informational.
List<SeismographSegment> _layoutLeafSegments({
  required List<String> trackPath,
  required List<SeismographNode> leaves,
  required double width,
  required double minSegmentPx,
  required List<String>? foldDrillPath,
  required bool foldIsDrillable,
}) {
  if (leaves.isEmpty) return const [];
  final sorted = [...leaves]..sort((a, b) => b.churn.compareTo(a.churn));
  final total = sorted.fold<int>(0, (a, n) => a + n.churn);
  // Pure-rename / pure-mode-only commits have all-zero churn. Fall back
  // to equal-share segments so the track is still legible (otherwise it
  // renders as an empty band — bug surfaced by reviewer).
  final shareOf = total == 0
      ? (SeismographNode _) => 1.0 / sorted.length
      : (SeismographNode n) => n.churn / total;

  final segments = <SeismographSegment>[];
  double x = 0;
  double remaining = width;
  for (var i = 0; i < sorted.length; i++) {
    final leaf = sorted[i];
    final share = shareOf(leaf);
    final w = share * width;
    final isLast = i == sorted.length - 1;

    if (w < minSegmentPx) {
      final tail = sorted.sublist(i);
      if (remaining < minSegmentPx) break;
      final tailAdd = tail.fold<int>(0, (a, n) => a + n.additions);
      final tailDel = tail.fold<int>(0, (a, n) => a + n.deletions);
      segments.add(SeismographSegment(
        path: foldDrillPath ?? trackPath,
        // "+5 more" instead of "+5" so it can't read as "+5 lines added".
        label: '+${tail.length} more',
        left: x, width: remaining,
        additions: tailAdd, deletions: tailDel,
        containedFileCount: tail.length,
        isDrillable: foldIsDrillable,
      ));
      break;
    }

    final actualWidth = isLast ? remaining : w;
    segments.add(SeismographSegment(
      path: leaf.path,
      label: _relPath(leaf, trackPath),
      left: x, width: actualWidth,
      additions: leaf.additions, deletions: leaf.deletions,
      file: leaf.file,
      containedFileCount: 1,
    ));
    x += actualWidth;
    remaining -= actualWidth;
  }
  return segments;
}
